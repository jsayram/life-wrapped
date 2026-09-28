// =============================================================================
// Summarization — live Apple Intelligence test
// =============================================================================
//
// Sends real transcripts to Apple's on-device model and checks the app gets a
// proper structured summary back. In the Simulator this uses the host Mac's
// Apple Intelligence. Skips itself (and passes) when Apple Intelligence is not
// available, e.g. on Xcode Cloud or a Mac without it turned on.

import Foundation
import Testing
import SharedModels
import Storage
@testable import Summarization

#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("Apple Intelligence live")
struct AppleIntelligenceLiveTests {

    private let coffeeTranscript = """
    This morning I met Sarah at the coffee shop downtown to plan the product launch. \
    We agreed the beta goes out on the fifteenth and she will handle the press email. \
    I'm a bit stressed about the deadline but excited because the early feedback on the \
    new onboarding flow has been really positive. After that I went for a run by the river.
    """

    private let gardenTranscript = """
    Spent the afternoon in the garden planting tomatoes and basil with my dad. \
    He showed me how to prune the old rose bush. We talked about building a small \
    greenhouse next spring and made a list of supplies to buy at the hardware store.
    """

    @Test("On-device model returns a parsed summary, and each request starts fresh")
    func liveSessionSummaries() async throws {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { return }

        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else {
            print("⏭️ [AppleIntelligenceLive] Skipped: Apple Intelligence unavailable (\(availability))")
            return
        }

        let storage = try await DatabaseManager(containerIdentifier: "group.com.jsayram.lifewrapped.tests")
        let engine = AppleEngine(storage: storage)
        #expect(await engine.isAvailable())

        // First recording
        let first = try await engine.summarizeSession(
            sessionId: UUID(), transcriptText: coffeeTranscript, duration: 45, languageCodes: ["en-US"]
        )
        print("🍎 [AppleIntelligenceLive] Summary 1: \(first.summary)")
        print("🍎 [AppleIntelligenceLive] Topics 1: \(first.topics)")

        #expect(!first.summary.isEmpty)
        #expect(!first.summary.contains("{"), "Summary should be parsed text, not raw JSON")
        #expect(!first.summary.contains("```"), "Summary should not contain markdown fences")
        #expect(!first.topics.isEmpty, "JSON was parsed, so topics should be filled in")

        // Second, unrelated recording: must not carry over the first one's content
        let second = try await engine.summarizeSession(
            sessionId: UUID(), transcriptText: gardenTranscript, duration: 35, languageCodes: ["en-US"]
        )
        print("🍎 [AppleIntelligenceLive] Summary 2: \(second.summary)")
        print("🍎 [AppleIntelligenceLive] Topics 2: \(second.topics)")

        #expect(!second.summary.isEmpty)
        #expect(!second.summary.contains("Sarah"), "Second summary leaked content from the first recording")
        #endif
    }

    @Test("Choosing Smarter routes a recording to Apple Intelligence first")
    func routingPicksApple() {
        #expect(SummarizationCoordinator.fallbackChain(for: .apple).first == .apple)
    }
}
