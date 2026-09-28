// =============================================================================
// Summarization — Year Wrap built from month digests
// =============================================================================

import Foundation
import Testing
import SharedModels
@testable import Summarization

/// Answers each prompt with a closure and counts the calls
actor ScriptedGenerator: TextGenerating {
    nonisolated let tier: EngineTier
    nonisolated let inputTokenBudget: Int
    nonisolated let outputTokenBudget: Int
    private let respond: @Sendable (String) -> String
    private(set) var calls = 0

    init(tier: EngineTier = .local, inputTokenBudget: Int = 1_900, outputTokenBudget: Int = 700, respond: @escaping @Sendable (String) -> String) {
        self.tier = tier
        self.inputTokenBudget = inputTokenBudget
        self.outputTokenBudget = outputTokenBudget
        self.respond = respond
    }

    func generateText(system: String, user: String, maxTokens: Int) async throws -> String {
        calls += 1
        return respond(user)
    }
}

private func month(_ number: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: number, day: 1))!
}

private let runA = UUID(), runB = UUID(), garden1 = UUID(), garden2 = UUID(), launch = UUID(), pricing = UUID()

/// March: garden started, a run, the launch plan. August: garden done, another run, a pricing decision.
private func sampleDigests() -> [MonthDigest] {
    [
        MonthDigest(
            monthStart: month(3), isFinal: true,
            stats: DigestStats(sessionCount: 3, totalMinutes: 20, wordCount: 900, activeDays: 3, workCount: 1, personalCount: 2),
            headline: "Getting started", narrative: "I started the garden and planned the launch.",
            items: [
                DigestItem(kind: .project, text: "Garden bed", category: .personal, sessionIds: [garden1], status: .started),
                DigestItem(kind: .win, text: "Ran my first 5k", category: .personal, sessionIds: [runA]),
                DigestItem(kind: .challenge, text: "Launch deadline stress", category: .work, sessionIds: [launch]),
                DigestItem(kind: .person, text: "Sarah", category: .work, sessionIds: [launch]),
            ],
            engineTier: "local"),
        MonthDigest(
            monthStart: month(8), isFinal: true,
            stats: DigestStats(sessionCount: 5, totalMinutes: 40, wordCount: 1500, activeDays: 4, workCount: 1, personalCount: 4),
            headline: "Harvest", narrative: nil,
            items: [
                DigestItem(kind: .project, text: "garden bed", category: .personal, sessionIds: [garden2], status: .done),
                DigestItem(kind: .win, text: "Ran a 10k", category: .personal, sessionIds: [runB]),
                DigestItem(kind: .decision, text: "Free core app with a one-time upgrade", category: .work, sessionIds: [pricing]),
                DigestItem(kind: .person, text: "Sarah", category: .personal, sessionIds: [runB]),
            ],
            engineTier: "local"),
    ]
}

@Suite("Year Wrap from digests")
struct YearWrapBuilderTests {

    @Test("A Work wrap is built from work slices only and told to write about work")
    func workScope() async throws {
        let march = MonthDigest(
            monthStart: month(3), isFinal: true,
            stats: DigestStats(sessionCount: 3, totalMinutes: 20, wordCount: 900, activeDays: 3, workCount: 1, personalCount: 2),
            headline: "Getting started", narrative: nil,
            items: sampleDigests()[0].items, engineTier: "apple",
            sections: [
                CategorySection(category: .work, stats: DigestStats(sessionCount: 1, totalMinutes: 5, wordCount: 300, activeDays: 1, workCount: 1, personalCount: 0), headline: "Launch", narrative: nil),
                CategorySection(category: .personal, stats: DigestStats(sessionCount: 2, totalMinutes: 15, wordCount: 600, activeDays: 2, workCount: 0, personalCount: 2), headline: "Garden", narrative: nil),
            ])
        let slice = try #require(march.slice(for: .workOnly))
        let wrap = await YearWrapBuilder.build(year: 2026, digests: [slice], generator: nil, scope: .workOnly)

        #expect(wrap.yearTitle == "My 2026 at work")
        #expect(wrap.stats?.sessionCount == 1)
        #expect(wrap.biggestWins.isEmpty)
        #expect(wrap.biggestChallenges.map(\.text) == ["Launch deadline stress"])
        #expect(YearWrapBuilder.systemInstruction(.workOnly).contains("write about work only"))
        #expect(YearWrapBuilder.systemInstruction(.all) == YearWrapBuilder.systemInstruction)
    }

    @Test("Without a model: numbers, projects, people and picks all come from the digests")
    func noModel() async {
        let wrap = await YearWrapBuilder.build(year: 2026, digests: sampleDigests(), generator: nil)

        #expect(wrap.stats?.sessionCount == 8)
        #expect(wrap.stats?.totalMinutes == 60)
        #expect(wrap.stats?.busiestMonth == 8)

        // The garden project was followed across months and ended done
        #expect(wrap.finishedProjects.map(\.text) == ["Garden bed"])
        #expect(wrap.finishedProjects.first?.sessionIds == [garden1, garden2])
        #expect(wrap.unfinishedProjects.isEmpty)

        let sarah = wrap.peopleMentioned.first { $0.name == "Sarah" }
        #expect(sarah?.sessionIds?.count == 2)

        #expect(wrap.biggestWins.count == 3) // two runs and the finished garden
        #expect(wrap.biggestLosses.isEmpty)
        #expect(wrap.valuableActionsTaken.first?.category == .work)
        #expect(wrap.yearTitle == "My 2026")
        #expect(wrap.yearSummary.contains("8 recordings"))
    }

    @Test("Small models get one short request per section, and picks keep their sources and category")
    func perSection() async {
        let generator = ScriptedGenerator { prompt in
            if prompt.contains("year_title") {
                return #"{"year_title":"Growing things","year_summary":"I grew a garden and ran more."}"#
            }
            if prompt.contains("biggest wins") {
                // Find the ids of the two runs in the prompt and merge them into one pick; 999 isn't a candidate
                let ids = prompt.split(separator: "\n").filter { $0.contains("Ran") }.compactMap { line -> Int? in
                    guard let open = line.firstIndex(of: "["), let close = line.firstIndex(of: "]") else { return nil }
                    return Int(line[line.index(after: open)..<close])
                }
                return #"{"items":[{"t":"I got faster all year","ids":[\#(ids.map(String.init).joined(separator: ","))]},{"t":"Made up","ids":[999]}]}"#
            }
            return "not json"
        }
        let wrap = await YearWrapBuilder.build(year: 2026, digests: sampleDigests(), generator: generator)

        #expect(wrap.yearTitle == "Growing things")
        #expect(wrap.biggestWins.count == 1)
        #expect(wrap.biggestWins.first?.text == "I got faster all year")
        #expect(Set(wrap.biggestWins.first?.sessionIds ?? []) == [runA, runB])
        #expect(wrap.biggestWins.first?.category == .personal)
        // A section whose answer wasn't JSON falls back to the digest items
        #expect(wrap.biggestChallenges.first?.text == "Launch deadline stress")
        #expect(await generator.calls > 1)
    }

    @Test("Unrelated ids on a pick are dropped, so it keeps only its own recordings and category")
    func unrelatedIdsDropped() {
        let items = [
            DigestItem(kind: .win, text: "Morning run", category: .personal, sessionIds: [runA, runB]),
            DigestItem(kind: .win, text: "Testing onboarding interviews", category: .work, sessionIds: [launch]),
        ]
        let candidates = YearWrapBuilder.makeCandidates(items, digests: [])
        let picks = YearWrapBuilder.parsePicks([["t": "Morning run.", "ids": [1, 2]]], candidates: candidates, limit: 5)
        #expect(picks.first?.sessionIds == [runA, runB])
        #expect(picks.first?.category == .personal)
    }

    @Test("A pick without usable ids is matched to candidates by its words")
    func pickWithoutIds() {
        let items = [
            DigestItem(kind: .win, text: "Morning run", category: .personal, sessionIds: [runA]),
            DigestItem(kind: .win, text: "Met Sarah downtown", category: .work, sessionIds: [launch]),
        ]
        let candidates = YearWrapBuilder.makeCandidates(items, digests: [])
        let picks = YearWrapBuilder.parsePicks([["t": "Morning runs by the river", "id": "c9"], ["text": "Something else"]], candidates: candidates, limit: 5)
        #expect(picks.count == 1)
        #expect(picks.first?.sessionIds == [runA])
    }

    @Test("A section the model answered with nothing usable falls back to the digest items")
    func unusableSectionFallsBack() async {
        let generator = ScriptedGenerator { prompt in
            prompt.contains("year_title") ? #"{"year_title":"T","year_summary":"S"}"# : #"{"items":[{"t":"Nothing matches here","ids":[]}]}"#
        }
        let wrap = await YearWrapBuilder.build(year: 2026, digests: sampleDigests(), generator: generator)
        #expect(!wrap.biggestWins.isEmpty)
        #expect(!wrap.biggestChallenges.isEmpty)
    }

    @Test("A bare list with the placeholder copied still yields the candidates' own text")
    func bareListWithPlaceholder() async {
        let generator = ScriptedGenerator { prompt in
            if prompt.contains("year_title") { return #"{"year_title":"T","year_summary":"S"}"# }
            guard prompt.contains("biggest wins"),
                  let line = prompt.split(separator: "\n").first(where: { $0.contains("Ran a 10k") }),
                  let open = line.firstIndex(of: "["), let close = line.firstIndex(of: "]") else { return "{}" }
            return "```json\n[{\"t\":\"<sentence>\",\"ids\":[\(line[line.index(after: open)..<close])]}]\n```"
        }
        let wrap = await YearWrapBuilder.build(year: 2026, digests: sampleDigests(), generator: generator)
        #expect(wrap.biggestWins.map(\.text) == ["Ran a 10k"])
        #expect(wrap.biggestWins.first?.sessionIds == [runB])
    }

    @Test("A title that only repeats the year is replaced")
    func yearOnlyTitle() {
        #expect(YearWrapBuilder.usableTitle("2026", year: 2026) == nil)
        #expect(YearWrapBuilder.usableTitle("Growing things", year: 2026) == "Growing things")
    }

    @Test("Models with room for the whole year get a single request")
    func wholeYear() async {
        let generator = ScriptedGenerator(tier: .external, inputTokenBudget: 60_000, outputTokenBudget: 4_000) { _ in
            #"{"year_title":"A full year","year_summary":"Summary.","biggest_wins":[{"t":"Ran a 10k","ids":[2]}],"biggest_losses":[]}"#
        }
        let wrap = await YearWrapBuilder.build(year: 2026, digests: sampleDigests(), generator: generator)
        #expect(await generator.calls == 1)
        #expect(wrap.yearTitle == "A full year")
        #expect(wrap.biggestLosses.isEmpty)
        // Sections the model skipped still get the digest items
        #expect(!wrap.valuableActionsTaken.isEmpty)
    }

    @Test("Saved JSON is what the Year Wrap screen and PDF export read")
    func jsonMatchesReaders() async throws {
        let wrap = await YearWrapBuilder.build(year: 2026, digests: sampleDigests(), generator: nil)
        let json = try YearWrapBuilder.jsonString(wrap)
        #expect(json.contains("\"year_summary\""))
        #expect(json.contains("\"session_ids\""))

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(YearWrapData.self, from: Data(json.utf8))
        #expect(decoded.finishedProjects.first?.sessionIds == [garden1, garden2])
        #expect(decoded.stats?.busiestMonth == 8)
    }

    @Test("Older wraps without sources or stats still decode")
    func oldFormat() throws {
        let old = #"{"year_title":"Old","year_summary":"S","major_arcs":[{"text":"A","category":"work"}],"biggest_wins":[],"biggest_losses":[],"biggest_challenges":[],"finished_projects":[],"unfinished_projects":[],"top_worked_on_topics":[],"top_talked_about_things":[],"valuable_actions_taken":[],"opportunities_missed":[],"people_mentioned":[{"name":"Sam"}],"places_visited":[]}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(YearWrapData.self, from: Data(old.utf8))
        #expect(decoded.majorArcs.first?.sessionIds == nil)
        #expect(decoded.stats == nil)
    }

    @Test("Per-section prompts stay inside a 4k window")
    func sectionPromptSize() {
        // A heavy year: 400 wins
        let items = (1...400).map { DigestItem(kind: .win, text: "Win number \($0) with some extra detail about it", sessionIds: [UUID()]) }
        let candidates = YearWrapBuilder.makeCandidates(items, digests: [])
        let shown = YearWrapBuilder.capped(candidates, tokenBudget: 1_900)
        let characters = shown.map(\.line).joined(separator: "\n").count
        #expect(characters < 12_000 - 2_000)
        #expect(!shown.isEmpty)
    }
}
