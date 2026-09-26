// =============================================================================
// Summarization — engine routing and model JSON parsing
// =============================================================================

import Foundation
import Testing
@testable import Summarization

@Suite("Session summary engine routing")
struct EngineRoutingTests {

    @Test("The engine the user picked is always tried first", arguments: [EngineTier.basic, .local, .apple, .external])
    func preferredFirst(tier: EngineTier) {
        #expect(SummarizationCoordinator.fallbackChain(for: tier).first == tier)
    }

    @Test("Apple Intelligence is used when selected")
    func appleIncluded() {
        #expect(SummarizationCoordinator.fallbackChain(for: .apple) == [.apple, .local, .basic])
    }

    @Test("On-device choices never fall back to the cloud", arguments: [EngineTier.basic, .local, .apple])
    func neverEscalatesToCloud(tier: EngineTier) {
        #expect(!SummarizationCoordinator.fallbackChain(for: tier).contains(.external))
    }

    @Test("Every chain ends with Basic so a summary is always produced", arguments: [EngineTier.basic, .local, .apple, .external])
    func endsWithBasic(tier: EngineTier) {
        #expect(SummarizationCoordinator.fallbackChain(for: tier).last == .basic)
    }
}

@Suite("Model JSON extraction")
struct ModelJSONTests {

    @Test("Plain JSON")
    func plain() {
        #expect(ModelJSON.object(from: #"{"summary":"hi"}"#)?["summary"] as? String == "hi")
    }

    @Test("JSON inside a markdown fence")
    func fenced() {
        let text = "```json\n{\"summary\": \"fenced\"}\n```"
        #expect(ModelJSON.object(from: text)?["summary"] as? String == "fenced")
    }

    @Test("JSON after a lead-in sentence")
    func leadIn() {
        let text = "Here is the summary:\n{\"summary\": \"after text\", \"topics\": [\"a\"]}\nHope this helps."
        #expect(ModelJSON.object(from: text)?["summary"] as? String == "after text")
    }

    @Test("No JSON returns nil")
    func none() {
        #expect(ModelJSON.object(from: "Just a sentence.") == nil)
    }
}

