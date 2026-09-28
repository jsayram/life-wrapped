// =============================================================================
// SharedModels — Choosing and refreshing a month's journal digests
// =============================================================================

import Foundation
import Testing
@testable import SharedModels

@Suite("Journal digests")
struct JournalDigestsTests {

    private let september = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1))!

    private func digest(_ journal: SessionCategory?, item: String, category: ItemCategory, sections: [CategorySection]? = nil) -> MonthDigest {
        MonthDigest(
            monthStart: september, isFinal: true,
            stats: DigestStats(sessionCount: 1, totalMinutes: 5, wordCount: 50, activeDays: 1, workCount: 0, personalCount: 0),
            headline: nil, narrative: nil,
            items: [DigestItem(kind: .win, text: item, category: category, sessionIds: [UUID()])],
            engineTier: "apple", sections: sections, journal: journal)
    }

    /// An older digest that mixed both journals
    private func legacy() -> MonthDigest {
        let stats = DigestStats(sessionCount: 1, totalMinutes: 5, wordCount: 50, activeDays: 1, workCount: 0, personalCount: 0)
        return MonthDigest(
            monthStart: september, isFinal: true,
            stats: DigestStats(sessionCount: 2, totalMinutes: 10, wordCount: 100, activeDays: 2, workCount: 1, personalCount: 1),
            headline: "Mixed", narrative: nil,
            items: [DigestItem(kind: .win, text: "Old work win", category: .work, sessionIds: [UUID()]),
                    DigestItem(kind: .win, text: "Old personal win", category: .personal, sessionIds: [UUID()])],
            engineTier: "local",
            sections: [CategorySection(category: .work, stats: stats, headline: "W", narrative: nil),
                       CategorySection(category: .personal, stats: stats, headline: "P", narrative: nil)])
    }

    // MARK: - Plan

    @Test func currentDigestsAreReused() {
        let plan = JournalDigests.plan(
            currentHashes: [.work: "w1", .personal: "p1"],
            stored: [.work: .init(inputHash: "w1", isFinal: true), .personal: .init(inputHash: "p1", isFinal: true)],
            hasLegacy: false, monthEnded: true)
        #expect(plan.reuse == [.work, .personal])
        #expect(!plan.needsWork)
    }

    @Test func changedOrMissingJournalIsRebuilt() {
        let plan = JournalDigests.plan(
            currentHashes: [.work: "w2", .personal: "p1"],
            stored: [.personal: .init(inputHash: "p1", isFinal: false)],
            hasLegacy: false, monthEnded: true)
        #expect(plan.rebuild == [.work])
        #expect(plan.markFinal == [.personal])
    }

    @Test func journalWithoutRecordingsIsRemoved() {
        // Every personal recording was moved to Work
        let plan = JournalDigests.plan(
            currentHashes: [.work: "w1"],
            stored: [.work: .init(inputHash: "w1", isFinal: true), .personal: .init(inputHash: "p1", isFinal: true)],
            hasLegacy: false, monthEnded: true)
        #expect(plan.remove == [.personal])
        #expect(plan.reuse == [.work])
    }

    @Test func emptiedMonthRemovesEverything() {
        let plan = JournalDigests.plan(
            currentHashes: [:],
            stored: [.work: .init(inputHash: "w1", isFinal: true)],
            hasLegacy: true, monthEnded: true)
        #expect(plan.remove == [.work])
        #expect(plan.removeLegacy)
    }

    @Test func legacyIsRemovedEvenWhenJournalsAreAlreadyCurrent() {
        let plan = JournalDigests.plan(
            currentHashes: [.work: "w1"],
            stored: [.work: .init(inputHash: "w1", isFinal: true)],
            hasLegacy: true, monthEnded: true)
        #expect(plan.reuse == [.work])
        #expect(plan.removeLegacy)
        #expect(plan.needsWork)
    }

    @Test func forceRebuildsEveryJournalWithRecordings() {
        let plan = JournalDigests.plan(
            currentHashes: [.work: "w1"],
            stored: [.work: .init(inputHash: "w1", isFinal: true)],
            hasLegacy: false, monthEnded: true, force: true)
        #expect(plan.rebuild == [.work])
    }

    // MARK: - What the app shows

    @Test func journalDigestsWinOverLegacy() throws {
        let work = digest(.work, item: "New work win", category: .work)
        let personal = digest(.personal, item: "New personal win", category: .personal)
        let result = try #require(JournalDigests.combined(stored: [.work: work, .personal: personal], legacy: legacy()))
        #expect(result.digest.items.map(\.text) == ["New work win", "New personal win"])
        #expect(!result.usesLegacy)
    }

    @Test func missingJournalFallsBackToItsPartOfLegacy() throws {
        let work = digest(.work, item: "New work win", category: .work)
        let result = try #require(JournalDigests.combined(stored: [.work: work], legacy: legacy()))
        #expect(result.digest.items.map(\.text) == ["New work win", "Old personal win"])
        #expect(result.usesLegacy)
    }

    @Test func afterRebuildTheRemovedJournalDoesNotComeBack() throws {
        // The rebuild found no personal recordings and deleted the mixed digest,
        // so nothing personal can reappear from it
        let work = digest(.work, item: "New work win", category: .work)
        let result = try #require(JournalDigests.combined(stored: [.work: work], legacy: nil))
        #expect(result.digest.items.map(\.text) == ["New work win"])
        #expect(!result.usesLegacy)
    }

    @Test func onlyLegacyIsShownUntilRebuilt() throws {
        let result = try #require(JournalDigests.combined(stored: [:], legacy: legacy()))
        #expect(result.digest.items.count == 2)
        #expect(result.usesLegacy)
        #expect(JournalDigests.combined(stored: [:], legacy: nil) == nil)
    }
}
