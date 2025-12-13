// =============================================================================
// SharedModels — Tests
// =============================================================================

import Foundation
import Testing
@testable import SharedModels

@Suite("Audio Chunk Tests")
struct AudioChunkTests {
    @Test("Audio chunk calculates duration correctly")
    func testDuration() {
        let start = Date()
        let end = start.addingTimeInterval(60)
        
        let chunk = AudioChunk(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            startTime: start,
            endTime: end,
            format: .m4a,
            sampleRate: 16000
        )
        
        #expect(chunk.duration == 60)
    }
}

@Suite("Transcript Segment Tests")
struct TranscriptSegmentTests {
    @Test("Word count calculation")
    func testWordCount() {
        let segment = TranscriptSegment(
            audioChunkID: UUID(),
            startTime: 0,
            endTime: 5,
            text: "Hello world this is a test",
            confidence: 0.95
        )
        
        #expect(segment.wordCount == 6)
    }
    
    @Test("Duration calculation")
    func testDuration() {
        let segment = TranscriptSegment(
            audioChunkID: UUID(),
            startTime: 10.5,
            endTime: 15.7,
            text: "Test",
            confidence: 0.9
        )
        
        #expect(abs(segment.duration - 5.2) < 0.001)
    }
}

@Suite("Listening State Tests")
struct ListeningStateTests {
    @Test("Idle state can start")
    func testIdleCanStart() {
        let state = ListeningState.idle
        #expect(state.canStart == true)
        #expect(state.canStop == false)
    }
    
    @Test("Listening state can stop")
    func testListeningCanStop() {
        let state = ListeningState.listening(mode: .active)
        #expect(state.canStart == false)
        #expect(state.canStop == true)
        #expect(state.isListening == true)
    }
}

@Suite("Feature Flag Tests")
struct FeatureFlagTests {
    @Test("Default flag states")
    func testDefaultStates() {
        #expect(FeatureFlag.passiveListening.defaultEnabled == true)
        #expect(FeatureFlag.onDeviceSummarization.defaultEnabled == false)
        #expect(FeatureFlag.watchApp.defaultEnabled == true)
    }
}

@Suite("Watch Message Tests")
struct WatchMessageTests {
    @Test("Watch message serialization")
    func testMessageSerialization() throws {
        let message = WatchMessage.startListening(mode: .active)
        
        let dict = try message.toDictionary()
        let decoded = try WatchMessage.fromDictionary(dict)
        
        if case .startListening(let mode) = decoded {
            #expect(mode == .active)
        } else {
            Issue.record("Expected startListening message")
        }
    }
}
