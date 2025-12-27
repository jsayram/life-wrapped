// =============================================================================
// RecordingCoordinator — Manages recording lifecycle and state
// =============================================================================

import Foundation
import SwiftUI
import AudioCapture
import SharedModels

/// Manages the recording lifecycle, state transitions, and audio capture operations
@MainActor
public final class RecordingCoordinator: ObservableObject {
    
    // MARK: - Dependencies
    
    private let audioCapture: AudioCaptureManager
    
    // MARK: - State
    
    @Published public private(set) var recordingState: RecordingState = .idle
    private var recordingStartTime: Date?
    private var lastCompletedChunk: AudioChunk?
    
    // MARK: - Callbacks
    
    /// Called when recording state changes
    public var onStateChanged: ((RecordingState) -> Void)?
    
    /// Called when widget data needs to be refreshed
    public var onWidgetUpdateNeeded: (() async -> Void)?
    
    /// Called when a chunk is completed during recording
    public var onChunkCompleted: ((AudioChunk) async -> Void)?
    
    // MARK: - Initialization
    
    public init(audioCapture: AudioCaptureManager) {
        self.audioCapture = audioCapture
    }
    
    // MARK: - Recording State Queries
    
    public var isRecording: Bool {
        recordingState.isRecording
    }
    
    public var isProcessing: Bool {
        recordingState.isProcessing
    }
    
    // MARK: - Recording Lifecycle
    
    /// Start a new recording session
    public func startRecording() async throws {
        print("🎙️ [RecordingCoordinator] Starting recording...")
        
        guard !recordingState.isRecording else {
            print("❌ [RecordingCoordinator] Cannot start recording: already in progress")
            throw AppCoordinatorError.recordingInProgress
        }
        
        // Clear any previous chunk
        lastCompletedChunk = nil
        
        // Start recording
        print("🎤 [RecordingCoordinator] Starting AudioCaptureManager...")
        try await audioCapture.startRecording(mode: .active)
        print("✅ [RecordingCoordinator] Audio capture started")
        
        recordingStartTime = Date()
        recordingState = .recording(startTime: Date())
        onStateChanged?(recordingState)
        print("🎙️ [RecordingCoordinator] Recording state updated to .recording")
    }
    
    /// Stop the current recording and process it through the pipeline
    public func stopRecording() async throws {
        print("⏹️ [RecordingCoordinator] Stopping recording...")
        
        guard case .recording = recordingState else {
            print("❌ [RecordingCoordinator] Cannot stop: no active recording")
            throw AppCoordinatorError.noActiveRecording
        }
        
        recordingState = .processing
        onStateChanged?(recordingState)
        print("🔄 [RecordingCoordinator] State changed to .processing")
        
        do {
            // 1. Stop audio capture - this triggers onChunkCompleted callback for final chunk
            print("🎤 [RecordingCoordinator] Stopping audio capture...")
            try await audioCapture.stopRecording()
            print("✅ [RecordingCoordinator] Audio capture stopped")
            
            // Wait for final chunk to be processed
            try? await Task.sleep(for: .milliseconds(500))
            
            // 2. Update widget data
            print("🧩 [RecordingCoordinator] Requesting widget update...")
            await onWidgetUpdateNeeded?()
            
            // Reset recording state
            recordingStartTime = nil
            lastCompletedChunk = nil
            recordingState = .completed(chunkId: UUID())
            onStateChanged?(recordingState)
            print("🎉 [RecordingCoordinator] Recording session completed successfully")
            
            // Auto-reset to idle after brief success display
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await MainActor.run {
                    if case .completed = self.recordingState {
                        self.recordingState = .idle
                        self.onStateChanged?(self.recordingState)
                        print("🔄 [RecordingCoordinator] Auto-reset to idle state")
                    }
                }
            }
            
        } catch {
            print("❌ [RecordingCoordinator] Recording failed: \(error.localizedDescription)")
            print("❌ [RecordingCoordinator] Error details: \(error)")
            recordingState = .failed(error.localizedDescription)
            onStateChanged?(recordingState)
            throw error
        }
    }
    
    /// Cancel the current recording without saving
    public func cancelRecording() async {
        guard recordingState.isRecording else { return }
        
        do {
            try await audioCapture.stopRecording()
        } catch {
            // Ignore errors when canceling
        }
        
        recordingStartTime = nil
        lastCompletedChunk = nil
        recordingState = .idle
        onStateChanged?(recordingState)
    }
    
    /// Reset to idle state after viewing completed/failed state
    public func resetRecordingState() {
        if case .idle = recordingState { return }
        if case .recording = recordingState { return }
        if case .processing = recordingState { return }
        
        recordingState = .idle
        onStateChanged?(recordingState)
    }
}
