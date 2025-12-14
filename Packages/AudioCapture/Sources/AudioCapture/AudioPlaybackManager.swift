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
    
    /// Play a single audio file (clears any queue)
    /// - Parameter url: The URL of the audio file to play
    public func playSingle(url: URL) throws {
        // Stop any current playback and clear queue
        stop()
        try play(url: url)
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
