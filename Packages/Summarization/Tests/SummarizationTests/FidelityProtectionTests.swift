// =============================================================================
// Summarization — nothing written by a better engine is replaced by a weaker one
// =============================================================================

import Foundation
import Testing
import SharedModels
@testable import Summarization

@Suite("Fidelity protection")
struct FidelityProtectionTests {

    private let march = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!

    private func source(_ day: Int, _ summary: String, keyPoints: [String]) -> DigestSource {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 9))!
        return DigestSource(sessionId: UUID(), start: start, duration: 300, wordCount: 100, summary: summary,
                            keyPoints: keyPoints, entities: [], category: .work)
    }

    @Test("Engines rank Cloud AI, Apple Intelligence, Offline AI, Key Sentences")
    func ranks() {
        #expect(EngineTier.external.fidelityRank > EngineTier.apple.fidelityRank)
        #expect(EngineTier.apple.fidelityRank > EngineTier.local.fidelityRank)
        #expect(EngineTier.local.fidelityRank > EngineTier.basic.fidelityRank)
        #expect(EngineTier.basic.isWeaker(than: "external"))
        #expect(!EngineTier.external.isWeaker(than: "external"))
        #expect(!EngineTier.external.isWeaker(than: nil))
        #expect(!EngineTier.basic.isWeaker(than: "garbage"))
        // A month combined from two journals counts as its weakest part
        #expect(EngineTier.fidelityRank(of: "external+basic") == EngineTier.basic.fidelityRank)
        #expect(EngineTier.local.isWeaker(than: "external+apple"))
    }

    @Test("A month rebuilt without a model keeps the story a better engine wrote")
    func keepsStory() async {
        let previous = MonthDigest(
            monthStart: march, isFinal: true,
            stats: DigestStats(sessionCount: 2, totalMinutes: 10, wordCount: 200, activeDays: 2, workCount: 2, personalCount: 0),
            headline: "A month of shipping", narrative: "I shipped the beta and planned the launch.",
            items: [], engineTier: "external",
            sections: [CategorySection(category: .work, stats: DigestStats(sessionCount: 2, totalMinutes: 10, wordCount: 200, activeDays: 2, workCount: 2, personalCount: 0), headline: nil, narrative: nil)],
            journal: .work
        )
        let recordings = [source(3, "Planned the launch", keyPoints: ["Launch plan"]),
                          source(5, "Shipped the beta", keyPoints: ["Beta shipped"]),
                          source(9, "Wrote the press email", keyPoints: ["Press email"])]

        let kept = await MonthDigestBuilder.build(monthStart: march, sources: recordings, isFinal: true,
                                                  generator: nil, journal: .work, keepingStoryFrom: previous)
        #expect(kept.headline == "A month of shipping")
        #expect(kept.narrative == "I shipped the beta and planned the launch.")
        #expect(kept.storyEngineTier == "external")
        #expect(kept.storyPredatesItems)
        #expect(kept.displayedEngineTier == "external")
        #expect(kept.engineTier == "basic")
        // The items and numbers are the new ones
        #expect(kept.stats.sessionCount == 3)
        #expect(kept.items.contains { $0.text == "Press email" })

        let fresh = await MonthDigestBuilder.build(monthStart: march, sources: recordings, isFinal: true,
                                                   generator: nil, journal: .work)
        #expect(fresh.narrative == nil)
        #expect(fresh.storyEngineTier == nil)
        #expect(!fresh.storyPredatesItems)
        #expect(fresh.displayedEngineTier == "basic")
    }

    @Test("Digests saved before the story fields existed still decode, and the fields round-trip")
    func decoding() throws {
        let old = """
        {"engineTier":"external","headline":"H","isFinal":true,"items":[],"monthStart":1772323200,\
        "narrative":"N","stats":{"activeDays":1,"personalCount":0,"sessionCount":1,"totalMinutes":5,"wordCount":50,"workCount":1}}
        """
        let decoded = try #require(MonthDigest.fromJSON(old))
        #expect(decoded.storyEngineTier == nil)
        #expect(!decoded.storyPredatesItems)
        #expect(decoded.hasWrittenStory)

        let kept = MonthDigest(monthStart: march, isFinal: true, stats: decoded.stats, headline: "H", narrative: "N",
                               items: [], engineTier: "basic",
                               sections: [CategorySection(category: .work, stats: decoded.stats, headline: nil, narrative: nil)],
                               journal: .work, storyEngineTier: "external", storyPredatesItems: true)
        let again = try #require(MonthDigest.fromJSON(try kept.jsonString()))
        #expect(again.storyEngineTier == "external")
        #expect(again.storyPredatesItems)
        #expect(again.withFinal(false).storyEngineTier == "external")
        #expect(again.slice(for: .workOnly)?.storyPredatesItems == true)
    }

    @Test("Combining journals reports the story engines and whether any story is old")
    func combining() throws {
        let stats = DigestStats(sessionCount: 1, totalMinutes: 5, wordCount: 50, activeDays: 1, workCount: 1, personalCount: 0)
        let work = MonthDigest(monthStart: march, isFinal: true, stats: stats, headline: "W", narrative: "w",
                               items: [], engineTier: "basic", journal: .work, storyEngineTier: "external", storyPredatesItems: true)
        let personal = MonthDigest(monthStart: march, isFinal: true, stats: stats, headline: "P", narrative: "p",
                                   items: [], engineTier: "basic", journal: .personal)
        let combined = try #require(MonthDigest.combining([work, personal]))
        #expect(combined.engineTier == "basic")
        #expect(combined.displayedEngineTier == "external+basic")
        #expect(combined.storyPredatesItems)
        #expect(combined.hasWrittenStory)
    }
}
