// =============================================================================
// Summarization — month digest extraction, merging and batching
// =============================================================================

import Foundation
import Testing
import SharedModels
@testable import Summarization

/// Returns canned answers in order and records every prompt it was sent
actor FakeGenerator: TextGenerating {
    nonisolated let tier: EngineTier = .local
    nonisolated let inputTokenBudget: Int
    nonisolated let outputTokenBudget: Int
    private var answers: [String]
    private(set) var prompts: [String] = []

    init(answers: [String], inputTokenBudget: Int = 1_900, outputTokenBudget: Int = 700) {
        self.answers = answers
        self.inputTokenBudget = inputTokenBudget
        self.outputTokenBudget = outputTokenBudget
    }

    func generateText(system: String, user: String, maxTokens: Int) async throws -> String {
        prompts.append(user)
        guard !answers.isEmpty else { throw SummarizationError.summarizationFailed("No more answers") }
        return answers.removeFirst()
    }
}

private func source(_ day: Int, _ summary: String, category: SessionCategory? = nil, keyPoints: [String] = [], entities: [Entity] = []) -> DigestSource {
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 9))!
    return DigestSource(sessionId: UUID(), start: start, duration: 300, wordCount: 100, summary: summary,
                        keyPoints: keyPoints, entities: entities, category: category)
}

private let march = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!

@Suite("Month digest")
struct MonthDigestTests {

    @Test("A journal's digest is written about that journal and records its days")
    func journalDigest() async {
        let recordings = [source(3, "Planned the launch", category: .work, keyPoints: ["Launch plan"]),
                          source(3, "Pricing call", category: .work, keyPoints: ["Pricing"]),
                          source(17, "Retro", category: .work, keyPoints: ["Retro notes"])]
        let generator = ScriptedGenerator(tier: .apple) { prompt in
            if prompt.contains("headline") {
                // The story prompt must be about work
                return prompt.contains("my work notes") ? #"{"headline":"Shipping month","narrative":"I shipped."}"# : "{}"
            }
            return "not json"
        }
        let digest = await MonthDigestBuilder.build(monthStart: march, sources: recordings, isFinal: true,
                                                    generator: generator, journal: .work)
        #expect(digest.journal == .work)
        #expect(digest.stats.days == [3, 17])
        #expect(digest.stats.activeDays == 2)
        #expect(digest.sections?.count == 1)
        #expect(digest.items.allSatisfy { $0.category == .work })
    }

    @Test("Items from different batches merge, with mentions and sources added up")
    func mergeAcrossBatches() {
        let a = UUID(), b = UUID(), c = UUID()
        let items = [
            DigestItem(kind: .project, text: "The garden bed", sessionIds: [a], status: .started),
            DigestItem(kind: .project, text: "garden bed!", sessionIds: [b, a], status: .done),
            DigestItem(kind: .person, text: "Sarah", sessionIds: [c]),
            DigestItem(kind: .person, text: "sarah", sessionIds: [a]),
            DigestItem(kind: .win, text: "Garden bed", sessionIds: [c]),
        ]
        let merged = MonthDigestBuilder.merge(items, categories: [a: .personal, b: .personal, c: .work])

        let project = merged.first { $0.kind == .project }
        #expect(merged.filter { $0.kind == .project }.count == 1)
        #expect(project?.mentions == 2)
        #expect(project?.sessionIds == [a, b])
        #expect(project?.status == .done)
        #expect(project?.category == .personal)

        let person = merged.first { $0.kind == .person }
        #expect(person?.mentions == 2)
        #expect(person?.category == .both)

        // Same text but a different kind stays separate
        #expect(merged.contains { $0.kind == .win })
    }

    @Test("Category comes from the recordings, not the model")
    func categoryFromRecordings() async {
        let work = source(2, "Planned the launch with Sarah.", category: .work)
        let answer = #"{"items":[{"k":"win","t":"Planned the launch","s":[1]}]}"#
        let digest = await MonthDigestBuilder.build(monthStart: march, sources: [work], isFinal: true,
                                                    generator: FakeGenerator(answers: [answer, "{}"]))
        let win = digest.items.first { $0.kind == .win }
        #expect(win?.category == .work)
        #expect(win?.sessionIds == [work.sessionId])
        #expect(digest.stats.workCount == 1)
    }

    @Test("Items that aren't in the recordings are dropped, and uncovered recordings keep their key points")
    func groundingAndCoverage() async {
        let run = source(1, "Went for an early run by the river before work.", category: .personal)
        let pricing = source(2, "Spent the afternoon on pricing tiers for the release.", category: .work,
                             keyPoints: ["Draft three pricing tiers"])
        // The model copies an example item that isn't in either recording, and only covers the first
        let answer = #"{"items":[{"k":"win","t":"Shipped the beta","s":[1,2]},{"k":"project","t":"Garden bed","s":[2],"status":"ongoing"},{"k":"win","t":"Early run by the river","s":[1]},{"k":"person","t":"Sarah","s":[1]}]}"#
        let digest = await MonthDigestBuilder.build(monthStart: march, sources: [run, pricing], isFinal: true,
                                                    generator: FakeGenerator(answers: [answer, #"{"headline":"March 2026","narrative":"I ran."}"#]))
        #expect(!digest.items.contains { $0.text == "Shipped the beta" })
        #expect(!digest.items.contains { $0.text == "Garden bed" })
        #expect(!digest.items.contains { $0.text == "Sarah" })
        #expect(digest.items.contains { $0.text == "Early run by the river" && $0.category == .personal })
        #expect(digest.items.contains { $0.text == "Draft three pricing tiers" && $0.sessionIds == [pricing.sessionId] })
        // A headline that only repeats the month is replaced
        #expect(digest.headline != "March 2026")
        #expect(digest.narrative == "I ran.")
    }

    @Test("An item keeps only the recordings that actually mention it")
    func itemNarrowedToMentioningRecordings() async {
        let weekend = source(1, "Weekend plans: a hike if the weather holds and dinner with Sam.", category: .personal)
        let pricing = source(2, "Team leaned toward a free core app with one upgrade.", category: .work)
        let inbox = source(3, "A calm weekly reset: cleaning and clearing the inbox.", category: .personal)
        // The model cites all three recordings for an item only the first one is about
        let answer = #"{"items":[{"k":"win","t":"Weekend plans","s":[1,2,3]}]}"#
        let digest = await MonthDigestBuilder.build(monthStart: march, sources: [weekend, pricing, inbox], isFinal: true,
                                                    generator: FakeGenerator(answers: [answer]))
        let item = digest.items.first { $0.text == "Weekend plans" }
        #expect(item?.sessionIds == [weekend.sessionId])
        #expect(item?.mentions == 1)
        #expect(item?.category == .personal)
    }

    @Test("The prompt's example has no realistic content a model could copy")
    func promptExampleIsPlaceholder() {
        let prompt = MonthDigestBuilder.extractionPrompt(batch: [source(1, "x")], monthStart: march)
        #expect(prompt.user.contains("<item>"))
        #expect(!prompt.user.contains("beta"))
    }

    @Test("A cut-off answer still keeps every complete item")
    func truncatedAnswer() {
        let batch = [source(1, "one"), source(2, "two")]
        let output = #"{"items":[{"k":"win","t":"Ran 5k","s":[1]},{"k":"idea","t":"Try a half marathon","s":["S2"]},{"k":"deci"#
        let items = MonthDigestBuilder.parseExtraction(output, batch: batch)
        #expect(items.count == 2)
        #expect(items[1].kind == .idea)
        #expect(items[1].sessionIds == [batch[1].sessionId])
    }

    @Test("Out-of-range recording numbers are ignored")
    func badReferences() {
        let batch = [source(1, "one")]
        let items = MonthDigestBuilder.parseExtraction(#"{"items":[{"k":"win","t":"Ran","s":[1,7,"x"]}]}"#, batch: batch)
        #expect(items.first?.sessionIds == [batch[0].sessionId])
    }

    @Test("A failed batch falls back to key points instead of dropping the recording")
    func failedBatchFallsBack() async {
        let s = source(3, "Talked about pricing.", keyPoints: ["Decide on the pricing tiers", "pricing"])
        // First call is not JSON, so the batch uses key points; narrative isn't asked for
        let digest = await MonthDigestBuilder.build(monthStart: march, sources: [s], isFinal: false,
                                                    generator: FakeGenerator(answers: ["Sorry, I can't."]))
        #expect(digest.items.contains { $0.kind == .note && $0.text == "Decide on the pricing tiers" })
        #expect(digest.items.contains { $0.kind == .topic && $0.text == "pricing" })
        #expect(digest.engineTier == EngineTier.basic.rawValue)
        #expect(digest.headline != nil)
    }

    @Test("Basic engine: every recording is represented, people and places come from entities")
    func basicDigest() async {
        let withPoints = source(1, "Long day.", keyPoints: ["Fixed the login bug"],
                                entities: [Entity(name: "Maya", type: .person, confidence: 0.9),
                                           Entity(name: "Lisbon", type: .location, confidence: 0.8),
                                           Entity(name: "Maybe", type: .person, confidence: 0.2)])
        let without = source(5, "Walked by the river and thought about the move.")
        let digest = await MonthDigestBuilder.build(monthStart: march, sources: [withPoints, without], isFinal: true, generator: nil)

        #expect(digest.items.contains { $0.text == "Fixed the login bug" })
        #expect(digest.items.contains { $0.text.hasPrefix("Walked by the river") })
        #expect(digest.items.contains { $0.kind == .person && $0.text == "Maya" })
        #expect(digest.items.contains { $0.kind == .place && $0.text == "Lisbon" })
        #expect(!digest.items.contains { $0.text == "Maybe" })
        #expect(digest.narrative == nil)
        #expect(digest.stats.sessionCount == 2)
        #expect(digest.stats.activeDays == 2)
        #expect(digest.stats.totalMinutes == 10)
    }

    @Test("Batches never go over the token budget")
    func batching() {
        let sources = (1...40).map { source(($0 % 28) + 1, String(repeating: "word ", count: 60 + $0)) }
        let budget = 1_400
        let batches = MonthDigestBuilder.batches(sources, tokenBudget: budget)
        #expect(batches.flatMap { $0 }.count == 40)
        for batch in batches where batch.count > 1 {
            let tokens = batch.reduce(0) { $0 + estimatedTokens(MonthDigestBuilder.sourceLine($1, index: 99)) }
            #expect(tokens <= budget)
        }
    }

    @Test("Local-sized prompts stay inside the model's window")
    func promptSizeForLocal() async {
        let sources = (1...30).map { source(($0 % 28) + 1, String(repeating: "I worked on the release checklist. ", count: 8)) }
        let generator = FakeGenerator(answers: [], inputTokenBudget: 1_900, outputTokenBudget: 700)
        for batch in MonthDigestBuilder.batches(sources, tokenBudget: MonthDigestBuilder.batchTokenBudget(for: generator)) {
            let prompt = MonthDigestBuilder.extractionPrompt(batch: batch, monthStart: march)
            // LlamaContext shortens anything over 12,000 characters; stay under it
            #expect(prompt.system.count + prompt.user.count < 12_000)
        }
    }

    @Test("A month with both kinds gets separate Work and Personal stories and numbers")
    func categorySections() async {
        let work = source(2, "Planned the launch with Sarah.", category: .work)
        let run = source(3, "Went for an early run by the river.", category: .personal)
        let generator = ScriptedGenerator { prompt in
            if prompt.contains("RECORDINGS:") {
                return #"{"items":[{"k":"win","t":"Planned the launch","s":[1]},{"k":"win","t":"Early run by the river","s":[2]}]}"#
            }
            if prompt.contains("my work notes") {
                #expect(prompt.contains("Planned the launch"))
                #expect(!prompt.contains("river"))
                return #"{"headline":"Launch planning","narrative":"I planned the launch."}"#
            }
            if prompt.contains("my personal notes") {
                #expect(!prompt.contains("launch"))
                return #"{"headline":"Running","narrative":"I ran by the river."}"#
            }
            return #"{"headline":"Both","narrative":"I planned and ran."}"#
        }
        let digest = await MonthDigestBuilder.build(monthStart: march, sources: [work, run], isFinal: true, generator: generator)

        #expect(digest.story(for: .all).narrative == "I planned and ran.")
        #expect(digest.story(for: .workOnly).narrative == "I planned the launch.")
        #expect(digest.story(for: .personalOnly).headline == "Running")
        #expect(digest.stats(for: .workOnly)?.sessionCount == 1)
        #expect(digest.stats(for: .personalOnly)?.sessionCount == 1)
        #expect(digest.items(of: .win, filter: .workOnly).map(\.text) == ["Planned the launch"])
        #expect(digest.items(of: .win, filter: .personalOnly).map(\.text) == ["Early run by the river"])
        #expect(await generator.calls == 4)
    }

    @Test("A single-category month reuses the combined story and makes no extra calls")
    func singleCategoryMonth() async {
        let work = source(2, "Planned the launch with Sarah.", category: .work)
        let generator = ScriptedGenerator { prompt in
            prompt.contains("RECORDINGS:")
                ? #"{"items":[{"k":"win","t":"Planned the launch","s":[1]}]}"#
                : #"{"headline":"Launch","narrative":"I planned the launch."}"#
        }
        let digest = await MonthDigestBuilder.build(monthStart: march, sources: [work], isFinal: true, generator: generator)
        #expect(digest.story(for: .workOnly).narrative == "I planned the launch.")
        #expect(digest.stats(for: .personalOnly) == nil)
        #expect(digest.items(of: .win, filter: .personalOnly).isEmpty)
        #expect(await generator.calls == 2)
    }

    @Test("Digest JSON round-trips")
    func roundTrip() throws {
        let digest = MonthDigest(monthStart: march, isFinal: true,
                                 stats: DigestStats(sessionCount: 1, totalMinutes: 5, wordCount: 100, activeDays: 1, workCount: 0, personalCount: 1),
                                 headline: "A quiet month", narrative: nil,
                                 items: [DigestItem(kind: .project, text: "Garden", category: .personal, sessionIds: [UUID()], status: .ongoing)],
                                 engineTier: "local")
        let decoded = MonthDigest.fromJSON(try digest.jsonString())
        #expect(decoded == digest)
    }
}
