// =============================================================================
// AudioCapture — Audio Playback Manager
// =============================================================================

import AVFoundation
import Foundation
import Accelerate

/// Manager for playing back recorded audio files
@MainActor
public final class AudioPlaybackManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval = 0
    @Published public private(set) var currentlyPlayingURL: URL?
    @Published public private(set) var fftMagnitudes: [Float] = Array(repeating: 0, count: 80)
    
    // MARK: - Private Properties
    
    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    
    // Sequential playback
    private var playQueue: [URL] = []
    private var currentQueueIndex: Int = 0
    private var onQueueComplete: (() -> Void)?
    
    // Audio engine for FFT analysis
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?
    nonisolated(unsafe) private var fftSetup: OpaquePointer?
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        // Create FFT setup for 1024 samples (log2(1024) = 10)
        fftSetup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }
    
    // MARK: - Public API
    
    /// Play audio from a file URL
    /// - Parameter url: The URL of the audio file to play
    private func play(url: URL) throws {
        // Configure audio session for playback
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif
        
        // Setup audio engine for FFT
        setupAudioEngine(url: url)
        
        print("▶️ [AudioPlaybackManager] Started playing: \(url.lastPathComponent)")
    }
    
    private func setupAudioEngine(url: URL) {
        // Stop existing engine
        stopAudioEngine()
        
        do {
            // Create audio engine and player node
            audioEngine = AVAudioEngine()
            playerNode = AVAudioPlayerNode()
            
            guard let engine = audioEngine, let player = playerNode else { return }
            
            // Load audio file
            audioFile = try AVAudioFile(forReading: url)
            guard let file = audioFile else { return }
            
            let format = file.processingFormat
            duration = Double(file.length) / format.sampleRate
            currentTime = 0
            currentlyPlayingURL = url
            
            // Attach and connect player node
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            
            // Install tap for FFT analysis
            let tapFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: format.sampleRate,
                                         channels: 1,
                                         interleaved: false)
            
            engine.mainMixerNode.installTap(onBus: 0,
                                           bufferSize: 4096,
                                           format: tapFormat) { [weak self] buffer, time in
                self?.performFFTNonisolated(buffer: buffer)
            }
            
            // Start engine
            try engine.start()
            
            // Schedule audio file
            player.scheduleFile(file, at: nil) { [weak self] in
                Task { @MainActor in
                    self?.handlePlaybackFinished()
                }
            }
            
            // Start playback
            player.play()
            isPlaying = true
            
            // Start progress timer
            startProgressTimer()
            
        } catch {
            print("❌ [AudioPlaybackManager] Failed to setup audio engine: \(error)")
        }
    }
    
    private func stopAudioEngine() {
        playerNode?.stop()
        audioEngine?.mainMixerNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        audioFile = nil
    }
    
    private func handlePlaybackFinished() {
        isPlaying = false
        currentTime = 0
        stopProgressTimer()
        
        // If playing from queue, advance to next
        if !playQueue.isEmpty {
            currentQueueIndex += 1
            playNextInQueue()
        } else {
            print("✅ [AudioPlaybackManager] Finished playing")
            stopAudioEngine()
        }
    }
    
    /// Play a single audio file (clears any queue)
    /// - Parameter url: The URL of the audio file to play
    public func playSingle(url: URL) throws {
        // Stop any current playback and clear queue
        stop()
        try play(url: url)
    }
    
    /// Pause the current playback
    public func pause() {
        playerNode?.pause()
        isPlaying = false
        stopProgressTimer()
        print("⏸️ [AudioPlaybackManager] Paused")
    }
    
    /// Resume paused playback
    public func resume() {
        playerNode?.play()
        isPlaying = true
        startProgressTimer()
        print("▶️ [AudioPlaybackManager] Resumed")
    }
    
    /// Toggle play/pause
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else if playerNode != nil {
            resume()
        }
    }
    
    /// Stop playback and reset
    public func stop() {
        stopProgressTimer()
        stopAudioEngine()
        isPlaying = false
        currentTime = 0
        duration = 0
        currentlyPlayingURL = nil
        
        // Clear queue
        playQueue = []
        currentQueueIndex = 0
        onQueueComplete = nil
        
        // Reset FFT
        fftMagnitudes = Array(repeating: 0, count: 80)
        
        print("⏹️ [AudioPlaybackManager] Stopped")
    }
    
    /// Seek to a specific time
    /// - Parameter time: The time to seek to
    public func seek(to time: TimeInterval) {
        guard let player = playerNode, let file = audioFile else { return }
        
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(time * sampleRate)
        let frameCount = AVAudioFrameCount(file.length - startFrame)
        
        // Stop current playback
        player.stop()
        
        // Schedule from new position
        player.scheduleSegment(file,
                              startingFrame: startFrame,
                              frameCount: frameCount,
                              at: nil) { [weak self] in
            Task { @MainActor in
                self?.handlePlaybackFinished()
            }
        }
        
        // Resume if was playing
        if isPlaying {
            player.play()
        }
        
        currentTime = time
    }
    
    // MARK: - Sequential Playback
    
    /// Play multiple audio files sequentially
    /// - Parameters:
    ///   - urls: Array of audio file URLs to play in order
    ///   - completion: Optional callback when all files finish playing
    public func playSequence(urls: [URL], completion: (() -> Void)? = nil) {
        guard !urls.isEmpty else {
            print("⚠️ [AudioPlaybackManager] Empty playback queue")
            return
        }
        
        // Stop current playback but don't clear timer
        stopProgressTimer()
        audioPlayer?.stop()
        audioPlayer = nil
        
        playQueue = urls
        currentQueueIndex = 0
        onQueueComplete = completion
        
        print("🎵 [AudioPlaybackManager] Starting sequential playback: \(urls.count) files")
        playNextInQueue()
    }
    
    /// Play the next file in the queue
    private func playNextInQueue() {
        guard currentQueueIndex < playQueue.count else {
            print("✅ [AudioPlaybackManager] Queue completed")
            playQueue = []
            currentQueueIndex = 0
            onQueueComplete?()
            onQueueComplete = nil
            return
        }
        
        let url = playQueue[currentQueueIndex]
        print("🎵 [AudioPlaybackManager] Playing \(currentQueueIndex + 1)/\(playQueue.count): \(url.lastPathComponent)")
        
        do {
            try play(url: url)
        } catch {
            print("❌ [AudioPlaybackManager] Failed to play \(url.lastPathComponent): \(error)")
            // Skip to next
            currentQueueIndex += 1
            playNextInQueue()
        }
    }
    
    /// Check if currently playing from a queue
    public var isPlayingSequence: Bool {
        !playQueue.isEmpty
    }
    
    /// Get current position in queue
    public var queueProgress: (current: Int, total: Int)? {
        guard !playQueue.isEmpty else { return nil }
        return (currentQueueIndex + 1, playQueue.count)
    }
    
    // MARK: - Private Helpers
    
    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateProgress()
            }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func updateProgress() {
        // Calculate current time from player node
        if let player = playerNode, let nodeTime = player.lastRenderTime,
           let playerTime = player.playerTime(forNodeTime: nodeTime) {
            let sampleRate = audioFile?.processingFormat.sampleRate ?? 44100
            currentTime = Double(playerTime.sampleTime) / sampleRate
        }
    }
    
    // MARK: - FFT Processing
    
    private nonisolated func performFFTNonisolated(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        
        // Take samples for FFT (max 1024)
        let samplesToProcess = min(frameCount, 1024)
        var samples = Array(UnsafeBufferPointer(start: channelData, count: samplesToProcess))
        
        // Pad if needed
        while samples.count < 1024 {
            samples.append(0)
        }
        
        // Perform FFT
        var realParts = [Float](repeating: 0, count: 512)
        var imagParts = [Float](repeating: 0, count: 512)
        
        // Convert samples to complex format
        for i in 0..<512 {
            realParts[i] = i * 2 < samples.count ? samples[i * 2] : 0
            imagParts[i] = i * 2 + 1 < samples.count ? samples[i * 2 + 1] : 0
        }
        
        var splitComplex = DSPSplitComplex(realp: &realParts, imagp: &imagParts)
        
        // Perform FFT using stored setup
        let log2n = vDSP_Length(10) // log2(1024)
        
        if let setup = fftSetup {
            vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            
            // Calculate magnitudes
            var magnitudes = [Float](repeating: 0, count: 512)
            vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(512))
            
            // Normalize and group into 80 bins
            let binSize = magnitudes.count / 80
            var outputMagnitudes = [Float](repeating: 0, count: 80)
            
            for i in 0..<80 {
                let startIdx = i * binSize
                let endIdx = min(startIdx + binSize, magnitudes.count)
                let binMagnitudes = magnitudes[startIdx..<endIdx]
                
                if !binMagnitudes.isEmpty {
                    let average = binMagnitudes.reduce(0, +) / Float(binMagnitudes.count)
                    outputMagnitudes[i] = min(average / 100.0, 1.0) // Normalize to 0-1
                }
            }
            
            // Update on main actor
            Task { @MainActor in
                self.fftMagnitudes = outputMagnitudes
            }
        }
    }
}
