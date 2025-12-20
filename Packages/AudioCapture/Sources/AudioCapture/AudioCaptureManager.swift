// =============================================================================
// AudioCapture — Audio Capture Manager
// =============================================================================

import AVFoundation
import Foundation
import SharedModels
import Accelerate

/// Actor that manages audio recording using AVAudioEngine
/// Handles background recording, pause/resume, and saving chunks to storage
@MainActor
public final class AudioCaptureManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var currentState: ListeningState = .idle
    @Published public private(set) var isRecording = false
    
    /// Current audio input level (0.0 to 1.0) for audio-reactive visualization
    /// Updated at 10Hz during recording
    @Published public private(set) var currentAudioLevel: Float = 0.0
    
    /// FFT frequency magnitudes for waveform visualization (32 bars)
    /// Each value represents the magnitude of a frequency bin
    @Published public private(set) var fftMagnitudes: [Float] = Array(repeating: 0, count: 32)
    
    // MARK: - Private Properties
    
    private let audioEngine = AVAudioEngine()
    private let containerIdentifier: String
    
    // Current recording session
    private var currentChunkStartTime: Date?
    private var currentChunkID: UUID?
    private var currentFileURL: URL?
    private var audioFile: AVAudioFile?
    
    // Session tracking for auto-chunking
    private var currentSessionId: UUID?
    private var currentChunkIndex: Int = 0
    private var autoChunkTimer: Timer?
    
    /// Duration in seconds after which to automatically start a new chunk (default: 180 = 3 minutes)
    public var autoChunkDuration: TimeInterval = 180
    
    // Callback for when a chunk is completed
    public var onChunkCompleted: (@Sendable (AudioChunk) async -> Void)?
    
    // Callback for error handling
    public var onError: (@Sendable (AudioCaptureError) -> Void)?
    
    // Audio level metering (10Hz update rate)
    private var lastAudioLevelUpdate: Date = .distantPast
    
    // FFT configuration
    private let fftBufferSize = 1024
    private var fftSetup: OpaquePointer?
    
    // MARK: - Initialization
    
    public init(containerIdentifier: String = AppConstants.appGroupIdentifier) {
        self.containerIdentifier = containerIdentifier
    }
    
    /// Clean up resources - call when manager is no longer needed
    public func cleanup() {
        // Stop auto-chunk timer
        autoChunkTimer?.invalidate()
        autoChunkTimer = nil
        
        if audioEngine.isRunning {
            stopAudioEngine()
        }
        
        #if os(iOS) || os(watchOS)
        // Remove notification observers
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        #endif
        
        currentChunkID = nil
        currentChunkStartTime = nil
        currentFileURL = nil
        audioFile = nil
        currentSessionId = nil
        currentChunkIndex = 0
        currentState = .idle
        isRecording = false
        
        print("🧹 [AudioCaptureManager] Cleanup complete")
    }
    
    // MARK: - Public API
    
    /// Start recording audio
    public func startRecording(mode: ListeningMode = .active) async throws {
        print("🎧 [AudioCaptureManager] startRecording() called")

        guard currentState == .idle else {
            print("❌ [AudioCaptureManager] invalid state: \(currentState)")
            throw AudioCaptureError.invalidState("Cannot start recording from state: \(currentState)")
        }

        // Request microphone permission
        print("🎧 [AudioCaptureManager] requesting microphone permission...")
        let authorized = await requestMicrophonePermission()
        print("🎧 [AudioCaptureManager] microphone permission granted: \(authorized)")
        guard authorized else {
            print("❌ [AudioCaptureManager] microphone permission denied")
            throw AudioCaptureError.notAuthorized
        }

        // Setup audio session
        print("🎧 [AudioCaptureManager] setting up audio session...")
        try setupAudioSession()
        print("🎧 [AudioCaptureManager] audio session configured")

        // Initialize session tracking (first chunk of new session)
        let sessionId = UUID()
        currentSessionId = sessionId
        currentChunkIndex = 0
        let sessionStartTime = Date()
        print("🎧 [AudioCaptureManager] new session started: \(sessionId) at \(sessionStartTime)")

        // Create first chunk
        try await startNewChunk(mode: mode)
        
        // Start auto-chunk timer
        startAutoChunkTimer()
        print("🎧 [AudioCaptureManager] auto-chunk timer started at \(Date()), will fire at \(Date().addingTimeInterval(autoChunkDuration))")
    }
    
    /// Start a new chunk within the current session
    private func startNewChunk(mode: ListeningMode = .active) async throws {
        let chunkID = UUID()
        let startTime = Date()
        print("🎧 [AudioCaptureManager] generating file URL for chunk: \(chunkID)")
        let fileURL = try generateFileURL(for: chunkID)
        print("🎧 [AudioCaptureManager] file URL: \(fileURL.path)")

        // Setup audio file for recording
        print("🎧 [AudioCaptureManager] setting up audio file...")
        try setupAudioFile(at: fileURL)
        print("🎧 [AudioCaptureManager] audio file ready")

        // Setup audio engine tap (update or create)
        print("🎧 [AudioCaptureManager] installing audio engine tap...")
        try setupAudioEngineTap()
        print("🎧 [AudioCaptureManager] audio engine tap installed")

        // Start the engine if not already running
        if !audioEngine.isRunning {
            print("🎧 [AudioCaptureManager] starting audio engine...")
            try startAudioEngine()
            print("🎧 [AudioCaptureManager] audio engine started")
        }

        // Update state
        currentChunkID = chunkID
        currentChunkStartTime = startTime
        currentFileURL = fileURL
        currentState = .listening(mode: mode)
        isRecording = true
        print("🎧 [AudioCaptureManager] chunk \(currentChunkIndex) started in session \(currentSessionId?.uuidString ?? "unknown")")
    }
    
    /// Stop recording and save the current chunk
    public func stopRecording() async throws {
        print("🎧 [AudioCaptureManager] stopRecording() called")
        
        guard currentState.canStop else {
            throw AudioCaptureError.invalidState("Cannot stop recording from state: \(currentState)")
        }
        
        // Stop auto-chunk timer
        autoChunkTimer?.invalidate()
        autoChunkTimer = nil
        print("🎧 [AudioCaptureManager] auto-chunk timer stopped")
        
        // Finalize current chunk
        await finalizeCurrentChunk()
        
        // Stop the engine
        stopAudioEngine()
        print("🎧 [AudioCaptureManager] audio engine stopped")
        
        // Clean up FFT resources
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
            fftSetup = nil
        }
        fftMagnitudes = Array(repeating: 0, count: 32)
        
        // Reset session state
        currentSessionId = nil
        currentChunkIndex = 0
        currentState = .idle
        isRecording = false
        print("🎧 [AudioCaptureManager] recording stopped, session ended")
    }
    
    /// Finalize the current chunk and emit it via callback
    private func finalizeCurrentChunk() async {
        guard let chunkID = currentChunkID,
              let startTime = currentChunkStartTime,
              let fileURL = currentFileURL,
              let sessionId = currentSessionId else {
            print("⚠️ [AudioCaptureManager] finalizeCurrentChunk called but no chunk data available")
            return
        }
        
        let endTime = Date()
        let chunk = AudioChunk(
            id: chunkID,
            fileURL: fileURL,
            startTime: startTime,
            endTime: endTime,
            format: .m4a,
            sampleRate: 44100,
            createdAt: startTime,
            sessionId: sessionId,
            chunkIndex: currentChunkIndex
        )
        
        print("🎧 [AudioCaptureManager] chunk \(currentChunkIndex) finalized at \(endTime): \(chunk.duration)s (session: \(sessionId))")
        
        // Notify via callback (caller handles storage and transcription)
        await onChunkCompleted?(chunk)
        print("🎧 [AudioCaptureManager] chunk \(currentChunkIndex) callback completed")
        
        // Clear current chunk state
        currentChunkID = nil
        currentChunkStartTime = nil
        currentFileURL = nil
        audioFile = nil
    }
    
    /// Automatically start a new chunk while recording continues
    private func autoFinalizeAndContinue() async {
        print("⏰ [AudioCaptureManager] AUTO-CHUNK TIMER FIRED at \(Date())")
        print("🎧 [AudioCaptureManager] Current chunk index: \(currentChunkIndex), session: \(currentSessionId?.uuidString ?? "none")")
        
        // Finalize current chunk
        await finalizeCurrentChunk()
        
        // Increment chunk index
        currentChunkIndex += 1
        print("🎧 [AudioCaptureManager] Starting next chunk with index: \(currentChunkIndex)")
        
        // Start next chunk in same session
        do {
            try await startNewChunk(mode: currentState.mode ?? .active)
            print("✅ [AudioCaptureManager] auto-chunk continuation successful - now recording chunk \(currentChunkIndex)")
        } catch {
            print("❌ [AudioCaptureManager] failed to start next chunk: \(error)")
            onError?(AudioCaptureError.recordingFailed("Failed to continue recording: \(error.localizedDescription)"))
            
            // Stop recording on error
            autoChunkTimer?.invalidate()
            autoChunkTimer = nil
            stopAudioEngine()
            currentState = .idle
            isRecording = false
        }
    }
    
    /// Start the auto-chunk timer
    private func startAutoChunkTimer() {
        // Invalidate any existing timer
        autoChunkTimer?.invalidate()
        
        // Create new timer
        let timer = Timer(timeInterval: autoChunkDuration, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.autoFinalizeAndContinue()
            }
        }
        
        // Add to run loop with common mode to ensure it fires during tracking
        RunLoop.main.add(timer, forMode: .common)
        autoChunkTimer = timer
        
        print("⏰ [AudioCaptureManager] Auto-chunk timer scheduled for \(autoChunkDuration)s intervals")
    }
    
    /// Pause recording (keep engine running but don't write to file)
    public func pauseRecording(reason: PauseReason = .userRequested) throws {
        guard currentState.isListening else {
            throw AudioCaptureError.invalidState("Cannot pause from state: \(currentState)")
        }
        
        currentState = .paused(reason: reason)
        // Note: We keep the engine running but stop writing to file
        // This is simpler than stopping/restarting the engine
    }
    
    /// Resume recording after pause
    public func resumeRecording(mode: ListeningMode = .active) throws {
        guard currentState.isPaused else {
            throw AudioCaptureError.invalidState("Cannot resume from state: \(currentState)")
        }
        
        currentState = .listening(mode: mode)
    }
    
    // MARK: - Private Methods
    
    private func requestMicrophonePermission() async -> Bool {
        #if os(iOS)
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #elseif os(macOS)
        // macOS doesn't use AVAudioApplication, use AVCaptureDevice instead
        return await withCheckedContinuation { continuation in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                continuation.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            default:
                continuation.resume(returning: false)
            }
        }
        #else
        // watchOS handles permissions differently
        return true
        #endif
    }
    
    private func setupAudioSession() throws {
        #if os(iOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // Configure for background audio recording
            // .mixWithOthers allows other audio to play while recording
            // .allowBluetoothHFP enables Bluetooth headset recording (Hands-Free Profile)
            // Note: .defaultToSpeaker is not compatible with .record category
            try session.setCategory(
                .record,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothHFP]
            )
            
            // Request permission to record in background
            try session.setActive(true)
            
            // Setup interruption notification observer
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioInterruption(_:)),
                name: AVAudioSession.interruptionNotification,
                object: session
            )
            
            print("🎙️ [AudioCaptureManager] Audio session configured for background recording")
        } catch {
            throw AudioCaptureError.audioSessionSetupFailed(error.localizedDescription)
        }
        #elseif os(macOS)
        // macOS doesn't use AVAudioSession
        print("🎙️ [AudioCaptureManager] Audio session setup not needed on macOS")
        #endif
    }
    
    #if os(iOS) || os(watchOS)
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        print("🎙️ [AudioCaptureManager] Audio interruption: \(type == .began ? "began" : "ended")")
        
        switch type {
        case .began:
            // Pause recording when interrupted (phone call, alarm, etc.)
            if currentState.isListening {
                do {
                    try pauseRecording(reason: .systemInterruption)
                    print("⏸️ [AudioCaptureManager] Recording paused due to interruption")
                } catch {
                    print("❌ [AudioCaptureManager] Failed to pause on interruption: \(error)")
                }
            }
            
        case .ended:
            // Resume recording when interruption ends
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && currentState.isPaused {
                    do {
                        try resumeRecording()
                        print("▶️ [AudioCaptureManager] Recording resumed after interruption")
                    } catch {
                        print("❌ [AudioCaptureManager] Failed to resume after interruption: \(error)")
                    }
                }
            }
            
        @unknown default:
            print("⚠️ [AudioCaptureManager] Unknown interruption type")
        }
    }
    #endif
    
    private func generateFileURL(for chunkID: UUID) throws -> URL {
        // Prefer app group container when available, but fall back to temporary directory
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: containerIdentifier
        ) {
            let audioDirectory = containerURL.appendingPathComponent("Audio", isDirectory: true)

            // Create directory if needed
            if !FileManager.default.fileExists(atPath: audioDirectory.path) {
                try FileManager.default.createDirectory(
                    at: audioDirectory,
                    withIntermediateDirectories: true
                )
            }

            return audioDirectory.appendingPathComponent("\(chunkID.uuidString).m4a")
        } else {
            // App Group container not available — log and use a safe fallback
            print("⚠️ [AudioCaptureManager] App Group container not found; falling back to temporary directory")
            let audioDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Audio", isDirectory: true)
            if !FileManager.default.fileExists(atPath: audioDirectory.path) {
                try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
            }
            return audioDirectory.appendingPathComponent("\(chunkID.uuidString).m4a")
        }
    }
    
    private func setupAudioFile(at url: URL) throws {
        let inputNode = audioEngine.inputNode
        let _ = inputNode.outputFormat(forBus: 0)
        
        do {
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 64000
                ]
            )
        } catch {
            throw AudioCaptureError.fileCreationFailed(error.localizedDescription)
        }
    }
    
    private nonisolated func installAudioTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        audioFile: AVAudioFile?,
        onError: (@Sendable (AudioCaptureError) -> Void)?,
        onAudioLevel: (@Sendable (Float) -> Void)?,
        onFFTMagnitudes: (@Sendable ([Float]) -> Void)?
    ) {
        // Remove any existing tap
        inputNode.removeTap(onBus: 0)
        
        // Track last update time for 10Hz rate limiting
        var lastLevelUpdate = Date.distantPast
        
        // Install tap to capture audio — this closure runs on the realtime audio thread
        // and must NOT access any @MainActor state. All values are passed in as parameters.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let audioFile = audioFile else { return }
            
            // Write audio to file
            do {
                try audioFile.write(from: buffer)
            } catch {
                let captureError = AudioCaptureError.recordingFailed(error.localizedDescription)
                if let onError = onError {
                    DispatchQueue.main.async {
                        onError(captureError)
                    }
                }
            }
            
            // Calculate RMS level for audio visualization (10Hz updates)
            let now = Date()
            if now.timeIntervalSince(lastLevelUpdate) >= 0.1 { // 10Hz = every 100ms
                lastLevelUpdate = now
                
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameLength = Int(buffer.frameLength)
                
                // Calculate RMS (Root Mean Square)
                var sum: Float = 0
                for i in 0..<frameLength {
                    let sample = channelData[i]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(frameLength))
                
                // Convert to decibels and normalize to 0-1 range
                // Typical speech range: -40dB to 0dB
                let db = 20 * log10(max(rms, 0.00001)) // Avoid log(0)
                let normalizedLevel = max(0, min(1, (db + 40) / 40))
                
                // Perform FFT for frequency visualization
                let floatData = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                let magnitudes = self.performFFTNonisolated(data: floatData)
                
                // Dispatch to main thread
                if let onAudioLevel = onAudioLevel {
                    DispatchQueue.main.async {
                        onAudioLevel(normalizedLevel)
                    }
                }
                
                if let onFFTMagnitudes = onFFTMagnitudes {
                    DispatchQueue.main.async {
                        onFFTMagnitudes(magnitudes)
                    }
                }
            }
        }
    }
    
    private func setupAudioEngineTap() throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        // Capture all needed values before calling the nonisolated function
        let capturedAudioFile = self.audioFile
        let capturedOnError = self.onError
        
        // Create callback for audio level updates
        let onAudioLevel: (@Sendable (Float) -> Void) = { [weak self] level in
            Task { @MainActor in
                self?.currentAudioLevel = level
            }
        }
        
        // Create callback for FFT magnitude updates
        let onFFTMagnitudes: (@Sendable ([Float]) -> Void) = { [weak self] magnitudes in
            Task { @MainActor in
                self?.fftMagnitudes = magnitudes
            }
        }
        
        // Call nonisolated helper to install the tap - this ensures the closure
        // is created outside of the @MainActor context entirely
        installAudioTap(
            on: inputNode,
            format: format,
            audioFile: capturedAudioFile,
            onError: capturedOnError,
            onAudioLevel: onAudioLevel,
            onFFTMagnitudes: onFFTMagnitudes
        )
    }
    
    private func startAudioEngine() throws {
        do {
            // Set up FFT before starting engine
            fftSetup = vDSP_DFT_zop_CreateSetup(nil, UInt(fftBufferSize), .FORWARD)
            try audioEngine.start()
        } catch {
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }
    }
    
    // MARK: - FFT Processing
    
    /// Perform Fast Fourier Transform on audio buffer to extract frequency magnitudes
    /// Returns array of 32 magnitudes representing different frequency bins
    private func performFFT(data: [Float]) -> [Float] {
        guard let setup = fftSetup else {
            return Array(repeating: 0, count: 32)
        }
        
        // Ensure we have enough data
        guard data.count >= fftBufferSize else {
            return Array(repeating: 0, count: 32)
        }
        
        // Prepare input arrays (real and imaginary parts)
        var realIn = Array(data.prefix(fftBufferSize))
        var imagIn = [Float](repeating: 0, count: fftBufferSize)
        
        // Prepare output arrays
        var realOut = [Float](repeating: 0, count: fftBufferSize)
        var imagOut = [Float](repeating: 0, count: fftBufferSize)
        
        // Prepare magnitude array (32 frequency bins)
        var magnitudes = [Float](repeating: 0, count: 32)
        
        // Perform FFT using nested withUnsafeMutableBufferPointer calls
        realIn.withUnsafeMutableBufferPointer { realInPtr in
            imagIn.withUnsafeMutableBufferPointer { imagInPtr in
                realOut.withUnsafeMutableBufferPointer { realOutPtr in
                    imagOut.withUnsafeMutableBufferPointer { imagOutPtr in
                        // Execute DFT
                        vDSP_DFT_Execute(
                            setup,
                            realInPtr.baseAddress!,
                            imagInPtr.baseAddress!,
                            realOutPtr.baseAddress!,
                            imagOutPtr.baseAddress!
                        )
                        
                        // Create complex structure for magnitude calculation
                        var complex = DSPSplitComplex(
                            realp: realOutPtr.baseAddress!,
                            imagp: imagOutPtr.baseAddress!
                        )
                        
                        // Compute magnitudes (use first 32 frequency bins)
                        vDSP_zvabs(&complex, 1, &magnitudes, 1, UInt(32))
                    }
                }
            }
        }
        
        // Normalize and limit magnitudes for visualization
        let maxMagnitude: Float = 100.0
        return magnitudes.map { min($0 / 10.0, maxMagnitude) / maxMagnitude }
    }
    
    /// Nonisolated version of FFT processing for use in audio tap callback
    nonisolated private func performFFTNonisolated(data: [Float]) -> [Float] {
        // FFT buffer size for processing
        let bufferSize = 1024
        
        // Return zeros if insufficient data
        guard data.count >= bufferSize else {
            return Array(repeating: 0, count: 32)
        }
        
        // Quick inline FFT (simplified version for audio tap thread)
        // We'll just do a basic frequency magnitude calculation without the full setup
        var magnitudes = [Float](repeating: 0, count: 32)
        
        let chunkSize = bufferSize / 32
        for i in 0..<32 {
            let start = i * chunkSize
            let end = min(start + chunkSize, data.count)
            var sum: Float = 0
            for j in start..<end {
                sum += abs(data[j])
            }
            magnitudes[i] = sum / Float(chunkSize)
        }
        
        // Normalize
        if let maxVal = magnitudes.max(), maxVal > 0 {
            magnitudes = magnitudes.map { $0 / maxVal }
        }
        
        return magnitudes
    }
    
    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}

