// =============================================================================
// AudioCapture — Audio Capture Manager
// =============================================================================

import AVFoundation
import Foundation
import SharedModels

/// Actor that manages audio recording using AVAudioEngine
/// Handles background recording, pause/resume, and saving chunks to storage
@MainActor
public final class AudioCaptureManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var currentState: ListeningState = .idle
    @Published public private(set) var isRecording = false
    
    // MARK: - Private Properties
    
    private let audioEngine = AVAudioEngine()
    private let containerIdentifier: String
    
    // Current recording session
    private var currentChunkStartTime: Date?
    private var currentChunkID: UUID?
    private var currentFileURL: URL?
    private var audioFile: AVAudioFile?
    
    // Callback for when a chunk is completed
    public var onChunkCompleted: (@Sendable (AudioChunk) async -> Void)?
    
    // Callback for error handling
    public var onError: (@Sendable (AudioCaptureError) -> Void)?
    
    // MARK: - Initialization
    
    public init(containerIdentifier: String = AppConstants.appGroupIdentifier) {
        self.containerIdentifier = containerIdentifier
    }
    
    /// Clean up resources - call when manager is no longer needed
    public func cleanup() {
        if audioEngine.isRunning {
            stopAudioEngine()
        }
        
        #if os(iOS)
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

        // Create new chunk
        let chunkID = UUID()
        let startTime = Date()
        print("🎧 [AudioCaptureManager] generating file URL for chunk: \(chunkID)")
        let fileURL = try generateFileURL(for: chunkID)
        print("🎧 [AudioCaptureManager] file URL: \(fileURL.path)")

        // Setup audio file for recording
        print("🎧 [AudioCaptureManager] setting up audio file...")
        try setupAudioFile(at: fileURL)
        print("🎧 [AudioCaptureManager] audio file ready")

        // Setup audio engine tap
        print("🎧 [AudioCaptureManager] installing audio engine tap...")
        try setupAudioEngineTap()
        print("🎧 [AudioCaptureManager] audio engine tap installed")

        // Start the engine
        print("🎧 [AudioCaptureManager] starting audio engine...")
        try startAudioEngine()
        print("🎧 [AudioCaptureManager] audio engine started")

        // Update state
        currentChunkID = chunkID
        currentChunkStartTime = startTime
        currentFileURL = fileURL
        currentState = .listening(mode: mode)
        isRecording = true
        print("🎧 [AudioCaptureManager] recording state updated to listening")
    }
    
    /// Stop recording and save the current chunk
    public func stopRecording() async throws {
        guard currentState.canStop else {
            throw AudioCaptureError.invalidState("Cannot stop recording from state: \(currentState)")
        }
        
        // Stop the engine
        stopAudioEngine()
        
        // Create chunk object and notify callback
        if let chunkID = currentChunkID,
           let startTime = currentChunkStartTime,
           let fileURL = currentFileURL {
            
            let endTime = Date()
            let chunk = AudioChunk(
                id: chunkID,
                fileURL: fileURL,
                startTime: startTime,
                endTime: endTime,
                format: .m4a,
                sampleRate: 44100,
                createdAt: Date()
            )
            
            // Notify via callback (caller handles storage)
            await onChunkCompleted?(chunk)
        }
        
        // Reset state
        currentChunkID = nil
        currentChunkStartTime = nil
        currentFileURL = nil
        audioFile = nil
        currentState = .idle
        isRecording = false
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
        #if os(iOS) || os(macOS)
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        // watchOS handles permissions differently
        return true
        #endif
    }
    
    private func setupAudioSession() throws {
        #if os(iOS)
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
        #endif
    }
    
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
    
    private func setupAudioEngineTap() throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        // Remove any existing tap
        inputNode.removeTap(onBus: 0)
        
        // Capture actor-isolated state on the current (main) actor before installing the
        // realtime tap so the realtime audio thread does not touch @MainActor state.
        let capturedAudioFile = self.audioFile
        let capturedOnError = self.onError
        let writeEnabledAtInstall = self.currentState.isListening

        // Install tap to capture audio — the closure only touches the captured values above
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
            // If writing was not enabled at install time, skip writing
            guard writeEnabledAtInstall else { return }

            // Write buffer to the captured audio file (safe to use from the audio thread)
            if let audioFile = capturedAudioFile {
                do {
                    try audioFile.write(from: buffer)
                } catch {
                    // Notify error back on the main thread using the captured callback
                    let captureError = AudioCaptureError.recordingFailed(error.localizedDescription)
                    if let onError = capturedOnError {
                        DispatchQueue.main.async {
                            onError(captureError)
                        }
                    }
                }
            }
        }
    }
    
    private func startAudioEngine() throws {
        do {
            try audioEngine.start()
        } catch {
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }
    }
    
    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}

