import Foundation
import Testing
import Storage
@testable import Summarization

/// Key Sentences must always produce a summary when there is a transcript. It once
/// returned "" for short recordings because every sentence was judged a fragment.
@Suite("Basic Engine Short Transcript Tests", .serialized)
struct BasicEngineShortTranscriptTests {

    private func makeEngine() async throws -> BasicEngine {
        let storage = try await DatabaseManager(containerIdentifier: "group.com.jsayram.lifewrapped.tests")
        return BasicEngine(storage: storage)
    }

    @Test("Short recordings get a summary", arguments: [
        "This is my test on recording a new personal recording after I have successfully updated my app. I'm doing a test flight right now.",
        "I'm doing a test flight right now.",
        "This is my test on recording a new personal recording. I want to see if the key sentences engine works. Then I stop and save it.",
        "Okay so I'm just testing this thing to see if it works and whether it makes a summary",
        "Testing one two three",
    ])
    func shortRecordingsGetASummary(transcript: String) async throws {
        let engine = try await makeEngine()
        let result = try await engine.summarizeSession(
            sessionId: UUID(), transcriptText: transcript, duration: 11, languageCodes: ["en-US"]
        )
        let summary = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!summary.isEmpty, "Empty summary for: \(transcript)")
        #expect(!summary.contains(".."), "Doubled period in: \(summary)")
    }

    @Test("Topics are nouns, not whatever scored highest")
    func topicsAreNouns() async throws {
        let engine = try await makeEngine()
        let transcript = "Took a long walk at lunch instead of eating at my desk. The weather finally turned and the park was full of people. I want to walk at lunch three times a week."
        let result = try await engine.summarizeSession(
            sessionId: UUID(), transcriptText: transcript, duration: 40, languageCodes: ["en-US"]
        )
        #expect(!result.topics.isEmpty)
        for word in ["finally", "turned", "full"] {
            #expect(!result.topics.contains(word), "\(word) is not a topic")
        }
        #expect(result.topics.contains { ["walk", "lunch", "weather", "park", "desk", "people"].contains($0) })
    }

    @Test("Sentences that already end in a period are not given another one")
    func noDoubledPeriods() async throws {
        let engine = try await makeEngine()
        let transcript = "Met Sarah downtown to plan the launch. The beta ships on the fifteenth and Sarah sends the press email. A little stressed about the deadline."
        let result = try await engine.summarizeSession(
            sessionId: UUID(), transcriptText: transcript, duration: 60, languageCodes: ["en-US"]
        )
        #expect(!result.summary.contains(".."), "Doubled period in: \(result.summary)")
        #expect(result.summary.hasSuffix("."))
    }
}
