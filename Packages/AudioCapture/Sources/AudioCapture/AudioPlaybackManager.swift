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
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    /// Play audio from a file URL
    /// - Parameter url: The URL of the audio file to play
    public func play(url: URL) throws {
        // Stop any current playback
        stop()
        
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
        print("⏹️ [AudioPlaybackManager] Stopped")
    }
    
    /// Seek to a specific time
    /// - Parameter time: The time to seek to
    public func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
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
            print("✅ [AudioPlaybackManager] Finished playing")
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
