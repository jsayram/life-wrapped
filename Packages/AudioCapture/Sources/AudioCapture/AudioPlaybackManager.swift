// =============================================================================
// AudioCapture — Audio Playback Manager
// =============================================================================

import AVFoundation
import Foundation

/// Manager for playing back recorded audio files
@MainActor
public final class AudioPlaybackManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval = 0
    @Published public private(set) var currentlyPlayingURL: URL?
    
    // MARK: - Private Properties
    
    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    
    // Sequential playback
    private var playQueue: [URL] = []
    private var currentQueueIndex: Int = 0
    private var onQueueComplete: (() -> Void)?
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Play a single audio file
    /// - Parameter url: The URL of the audio file to play
    public func play(url: URL) async throws {
        try await playInternal(url: url)
    }
    
    /// Play multiple audio files in sequence
    /// - Parameters:
    ///   - urls: Array of audio file URLs to play
    ///   - onComplete: Optional completion handler called when all files finish
    public func playSequence(urls: [URL], onComplete: (() -> Void)? = nil) async throws {
        stop() // Stop any existing playback
        
        guard !urls.isEmpty else { return }
        
        playQueue = urls
        currentQueueIndex = 0
        onQueueComplete = onComplete
        
        // Start playing first file
        if currentQueueIndex < playQueue.count {
            try await playInternal(url: playQueue[currentQueueIndex])
        }
    }
    
    /// Play audio from a file URL
    /// - Parameter url: The URL of the audio file to play
    private func playInternal(url: URL) async throws {
        // Configure audio session for playback
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif
        
        // Create and configure player
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()
        
        duration = audioPlayer?.duration ?? 0
        currentTime = 0
        currentlyPlayingURL = url
        
        // Start playback
        audioPlayer?.play()
        isPlaying = true
        
        // Start progress timer
        startProgressTimer()
        
        print("▶️ [AudioPlaybackManager] Started playing: \(url.lastPathComponent)")
    }
    
    /// Pause the current playback
    public func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopProgressTimer()
        print("⏸️ [AudioPlaybackManager] Paused")
    }
    
    /// Resume paused playback
    public func resume() {
        audioPlayer?.play()
        isPlaying = true
        startProgressTimer()
        print("▶️ [AudioPlaybackManager] Resumed")
    }
    
    /// Toggle play/pause
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else if audioPlayer != nil {
            resume()
        }
    }
    
    /// Stop playback and reset
    public func stop() {
        stopProgressTimer()
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentlyPlayingURL = nil
        
        // Clear queue
        playQueue = []
        currentQueueIndex = 0
        onQueueComplete = nil
        
        print("⏹️ [AudioPlaybackManager] Stopped")
    }
    
    /// Seek to a specific time
    /// - Parameter time: The time to seek to
    public func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    // MARK: - Sequential Playback
    
    private func playNextInQueue() {
        guard currentQueueIndex < playQueue.count else {
            // Queue complete
            print("✅ [AudioPlaybackManager] Queue complete")
            playQueue = []
            currentQueueIndex = 0
            onQueueComplete?()
            onQueueComplete = nil
            return
        }
        
        Task {
            do {
                try await playInternal(url: playQueue[currentQueueIndex])
            } catch {
                print("❌ [AudioPlaybackManager] Failed to play next in queue: \(error)")
                currentQueueIndex += 1
                playNextInQueue()
            }
        }
    }
    
    // MARK: - Progress Timer
    
    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateProgress()
            }
        }
        if let timer = progressTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func updateProgress() {
        currentTime = audioPlayer?.currentTime ?? 0
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlaybackManager: AVAudioPlayerDelegate {
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.stopProgressTimer()
            
            // If playing from queue, advance to next
            if !self.playQueue.isEmpty {
                self.currentQueueIndex += 1
                self.playNextInQueue()
            } else {
                print("✅ [AudioPlaybackManager] Finished playing")
            }
        }
    }
    
    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.stop()
            if let error = error {
                print("❌ [AudioPlaybackManager] Decode error: \(error)")
            }
        }
    }
}
