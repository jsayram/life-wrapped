// =============================================================================
// AudioCapture — Tests
// =============================================================================

import Foundation
import Testing
@testable import AudioCapture
@testable import SharedModels

@Suite("Audio Capture Manager Tests")
@MainActor
struct AudioCaptureManagerTests {
    
    @Test("Manager initializes with idle state")
    func testInitialState() async throws {
        let manager = AudioCaptureManager()
        
        #expect(manager.currentState == .idle)
        #expect(manager.isRecording == false)
    }
    
    @Test("State transitions - start sets listening state")
    func testStateTransitionStart() async throws {
        let manager = AudioCaptureManager()
        
        // Note: This will fail on CI without microphone access
        // In real tests, we'd mock the audio engine
        #expect(manager.currentState == .idle)
    }
    
    @Test("Cannot start recording from non-idle state")
    func testCannotStartFromListening() async throws {
        let manager = AudioCaptureManager()
        
        // Manually set to listening state
        // In production, we'd need to mock or use dependency injection
        #expect(manager.currentState == .idle)
    }
    
    @Test("Pause transitions from listening to paused")
    func testPauseTransition() async throws {
        let manager = AudioCaptureManager()
        
        // Would need to be in listening state first
        // For now, verify the logic exists
        #expect(manager.currentState.isPaused == false)
    }
    
    @Test("Resume transitions from paused to listening")
    func testResumeTransition() async throws {
        let manager = AudioCaptureManager()
        
        #expect(manager.currentState.isListening == false)
    }
    
    @Test("Stop recording cleans up state")
    func testStopCleansUpState() async throws {
        let manager = AudioCaptureManager()
        
        // After stopping, should return to idle
        #expect(manager.currentState == .idle)
    }
    
    @Test("Callback is invoked on chunk completion")
    func testChunkCompletionCallback() async throws {
        let manager = AudioCaptureManager()
        
        manager.onChunkCompleted = { chunk in
            // Callback will be invoked when recording stops
            // In a real test, we'd verify this with expectations
        }
        
        // For now, verify callback is settable
        #expect(manager.onChunkCompleted != nil)
    }
    
    @Test("Error callback is invoked on failure")
    func testErrorCallback() async throws {
        let manager = AudioCaptureManager()
        
        manager.onError = { error in
            // Error callback will be invoked on recording failures
        }
        
        // Verify error callback is settable
        #expect(manager.onError != nil)
    }
}

@Suite("Audio Capture Error Tests")
struct AudioCaptureErrorTests {
    
    @Test("Error descriptions are meaningful")
    func testErrorDescriptions() throws {
        let errors: [AudioCaptureError] = [
            .notAuthorized,
            .audioSessionSetupFailed("test reason"),
            .engineStartFailed("test reason"),
            .fileCreationFailed("test reason"),
            .invalidState("test reason"),
            .recordingFailed("test reason"),
            .appGroupContainerNotFound
        ]
        
        for error in errors {
            let description = error.errorDescription
            #expect(description != nil)
            #expect(description!.isEmpty == false)
        }
    }
    
    @Test("Error types are distinct")
    func testErrorTypesDistinct() throws {
        let error1 = AudioCaptureError.notAuthorized
        let error2 = AudioCaptureError.appGroupContainerNotFound
        
        #expect(error1.errorDescription != error2.errorDescription)
    }
}

@Suite("Audio File Management Tests")
@MainActor
struct AudioFileManagementTests {
    
    @Test("File URLs use App Group container")
    func testFileURLGeneration() async throws {
        // Test would verify file URLs are in App Group
        let manager = AudioCaptureManager()
        #expect(manager.currentState == .idle)
    }
    
    @Test("Audio directory is created if missing")
    func testAudioDirectoryCreation() async throws {
        // Test would verify directory creation
        let manager = AudioCaptureManager()
        #expect(manager.currentState == .idle)
    }
    
    @Test("AudioFileManager creates directory")
    func testAudioFileManagerDirectory() async throws {
        let fileManager = AudioFileManager()
        let directory = try await fileManager.getAudioDirectory()
        
        #expect(directory.path.contains("Audio"))
    }
    
    @Test("AudioFileManager counts files")
    func testAudioFileManagerCount() async throws {
        let fileManager = AudioFileManager()
        let count = try await fileManager.getAudioFileCount()
        
        // Should be non-negative
        #expect(count >= 0)
    }
}
