// =============================================================================
// SharedModels — Month digest filtering and copied text
// =============================================================================

import Foundation
import Testing
@testable import SharedModels

@Suite("Month digest text")
struct MonthDigestTextTests {

    private func digest() -> MonthDigest {
        let september = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        return MonthDigest(
            monthStart: september, isFinal: false,
            stats: DigestStats(sessionCount: 3, totalMinutes: 20, wordCount: 300, activeDays: 2, workCount: 2, personalCount: 1),
            headline: "Launch and garden", narrative: "I planned the launch and planted tomatoes.",
            items: [
                DigestItem(kind: .win, text: "Planned the launch", category: .work, mentions: 2, sessionIds: [UUID(), UUID()]),
                DigestItem(kind: .project, text: "Garden bed", category: .personal, sessionIds: [UUID()], status: .ongoing),
                DigestItem(kind: .person, text: "Sarah", category: .both, sessionIds: [UUID()]),
            ],
            engineTier: "apple",
            sections: [
                CategorySection(category: .work, stats: DigestStats(sessionCount: 2, totalMinutes: 12, wordCount: 200, activeDays: 1, workCount: 2, personalCount: 0),
                                headline: "Launch", narrative: "I planned the launch."),
                CategorySection(category: .personal, stats: DigestStats(sessionCount: 1, totalMinutes: 8, wordCount: 100, activeDays: 1, workCount: 0, personalCount: 1),
                                headline: "Garden", narrative: "I planted tomatoes."),
            ])
    }

    @Test("Copying All includes the whole month")
    func copyAll() {
        let text = digest().plainText(filter: .all)
        #expect(text.hasPrefix("September 2026\n\nLaunch and garden"))
        #expect(text.contains("3 recordings · 2 days · 20 min"))
        #expect(text.contains("Wins\n- Planned the launch ×2"))
        #expect(text.contains("Projects\n- Garden bed (ongoing)"))
        #expect(text.contains("People\n- Sarah"))
    }

    @Test("Copying Work leaves out personal items and uses the work story")
    func copyWork() {
        let text = digest().plainText(filter: .workOnly)
        #expect(text.hasPrefix("September 2026 · Work\n\nLaunch\n\nI planned the launch."))
        #expect(text.contains("2 recordings · 1 day · 12 min"))
        #expect(!text.contains("Garden bed"))
        #expect(text.contains("Sarah")) // spans both
    }

    @Test("A category with no recordings says so")
    func emptyCategory() {
        let d = digest()
        let workOnly = MonthDigest(monthStart: d.monthStart, isFinal: true, stats: d.stats, headline: nil, narrative: nil,
                                   items: [], engineTier: "basic", sections: [d.sections![0]])
        #expect(workOnly.plainText(filter: .personalOnly).contains("No personal recordings this month."))
    }

    @Test func sliceKeepsOnlyThatCategory() throws {
        let month = digest()
        let work = try #require(month.slice(for: .workOnly))
        #expect(work.items.map(\.text) == ["Planned the launch", "Sarah"])
        #expect(work.stats == month.stats(for: .workOnly))
        #expect(work.headline == "Launch")
        #expect(month.slice(for: .all) == month)
    }

    private func journalDigest(_ journal: SessionCategory, days: [Int], headline: String) -> MonthDigest {
        let september = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let category: ItemCategory = journal == .work ? .work : .personal
        return MonthDigest(
            monthStart: september, isFinal: true,
            stats: DigestStats(sessionCount: days.count, totalMinutes: 10, wordCount: 100, activeDays: days.count,
                               workCount: journal == .work ? days.count : 0, personalCount: journal == .personal ? days.count : 0, days: days),
            headline: headline, narrative: nil,
            items: [DigestItem(kind: .person, text: "Sarah", category: category, sessionIds: [UUID()])],
            engineTier: "apple",
            sections: [CategorySection(category: category, stats: DigestStats(sessionCount: days.count, totalMinutes: 10, wordCount: 100, activeDays: days.count, workCount: 0, personalCount: 0), headline: nil, narrative: nil)],
            journal: journal)
    }

    @Test func combiningKeepsJournalsApart() throws {
        let work = journalDigest(.work, days: [2, 5], headline: "Launch")
        let personal = journalDigest(.personal, days: [5, 9, 12], headline: "Garden")
        let month = try #require(MonthDigest.combining([personal, work]))

        #expect(month.stats.sessionCount == 5)
        #expect(month.stats.activeDays == 4)  // day 5 counts once
        #expect(month.stats.workCount == 2 && month.stats.personalCount == 3)
        // "Sarah" stays two items, one per journal, never merged into "both"
        #expect(month.items.map(\.category) == [.work, .personal])
        #expect(month.story(for: .all).headline == nil)
        #expect(month.story(for: .workOnly).headline == "Launch")
        #expect(month.journalStories.map(\.title) == ["Work", "Personal"])
        #expect(month.plainText(filter: .all).contains("Personal: Garden"))
        #expect(month.slice(for: .personalOnly)?.items.count == 1)
    }

    @Test func combiningOneJournalReturnsIt() throws {
        let work = journalDigest(.work, days: [2], headline: "Launch")
        #expect(MonthDigest.combining([work]) == work)
        #expect(MonthDigest.combining([]) == nil)
    }
}
