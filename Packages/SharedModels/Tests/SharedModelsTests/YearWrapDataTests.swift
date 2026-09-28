// =============================================================================
// SharedModels — Year Wrap parsing and redaction
// =============================================================================

import Foundation
import Testing
@testable import SharedModels

@Suite("Year Wrap data")
struct YearWrapDataTests {

    private func wrap() -> YearWrapData {
        YearWrapData(
            yearTitle: "Maria and Lisbon",
            yearSummary: "I spent the year working with Maria and travelling to Lisbon.",
            majorArcs: [ClassifiedItem(text: "Shipped the app with Maria", category: .work)],
            biggestWins: [ClassifiedItem(text: "Moved to LISBON", category: .personal)],
            biggestLosses: [],
            biggestChallenges: [ClassifiedItem(text: "Mariana's schedule", category: .work)],
            finishedProjects: [],
            unfinishedProjects: [],
            topWorkedOnTopics: [],
            topTalkedAboutThings: [],
            valuableActionsTaken: [],
            opportunitiesMissed: [],
            peopleMentioned: [PersonMention(name: "Maria", relationship: "cofounder", impact: "Mentioned in 4 recordings")],
            placesVisited: [PlaceVisit(name: "Lisbon", frequency: "frequently")],
            stats: YearWrapStats(sessionCount: 40, totalMinutes: 300, wordCount: 20_000, activeDays: 30,
                                 workCount: 25, personalCount: 15, busiestMonth: 3)
        )
    }

    @Test func parsesCurrentFormatIncludingStats() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let text = String(decoding: try encoder.encode(wrap()), as: UTF8.self)

        let parsed = try #require(YearWrapData.parse(text))
        #expect(parsed.yearTitle == "Maria and Lisbon")
        #expect(parsed.majorArcs.first?.category == .work)
        #expect(parsed.peopleMentioned.first?.name == "Maria")
        #expect(parsed.stats?.busiestMonth == 3)
        #expect(parsed.stats?.workCount == 25)
    }

    @Test func parsesOlderStringSections() throws {
        let text = #"{"year_summary": "A year.", "biggest_wins": ["Ran a marathon"]}"#
        let parsed = try #require(YearWrapData.parse(text))
        #expect(parsed.yearTitle == "Year in Review")
        #expect(parsed.biggestWins == [ClassifiedItem(text: "Ran a marathon", category: .both)])
        #expect(parsed.stats == nil)
    }

    @Test func rejectsTextThatIsNotAWrap() {
        #expect(YearWrapData.parse("Just some notes") == nil)
        #expect(YearWrapData.parse(#"{"headline": "A month"}"#) == nil)
    }

    @Test func redactsPeopleEverywhere() {
        let redacted = wrap().redacted(people: true, places: false)
        #expect(redacted.yearTitle == "[Person] and Lisbon")
        #expect(redacted.majorArcs.first?.text == "Shipped the app with [Person]")
        #expect(redacted.peopleMentioned.first?.name == "[Person]")
        #expect(redacted.peopleMentioned.first?.relationship == nil)
        // Whole names only: "Mariana" is a different word
        #expect(redacted.biggestChallenges.first?.text == "Mariana's schedule")
        #expect(redacted.placesVisited.first?.name == "Lisbon")
    }

    @Test func redactsPlacesIgnoringCase() {
        let redacted = wrap().redacted(people: false, places: true)
        #expect(redacted.biggestWins.first?.text == "Moved to [Location]")
        #expect(redacted.yearSummary == "I spent the year working with Maria and travelling to [Location].")
        #expect(redacted.placesVisited.first?.name == "[Location]")
    }

    @Test func noRedactionLeavesTextAlone() {
        #expect(wrap().redacted(people: false, places: false).yearTitle == "Maria and Lisbon")
    }

    private func journalWrap(_ title: String, item: String, category: ItemCategory, person: String) -> YearWrapData {
        YearWrapData(
            yearTitle: title, yearSummary: "\(title) summary.",
            majorArcs: [], biggestWins: [ClassifiedItem(text: item, category: category)], biggestLosses: [],
            biggestChallenges: [], finishedProjects: [], unfinishedProjects: [], topWorkedOnTopics: [],
            topTalkedAboutThings: [], valuableActionsTaken: [], opportunitiesMissed: [],
            peopleMentioned: [PersonMention(name: person)], placesVisited: [])
    }

    @Test func allKeepsEachJournalsStory() throws {
        let work = journalWrap("Shipping year", item: "Launched the app", category: .work, person: "Sarah")
        let personal = journalWrap("Garden year", item: "Ran a 10k", category: .personal, person: "Sarah")
        let stats = YearWrapStats(sessionCount: 9, totalMinutes: 60, wordCount: 900, activeDays: 7, workCount: 5, personalCount: 4, busiestMonth: 3)
        let all = try #require(YearWrapData.combining([.personal: personal, .work: work], year: 2026, stats: stats))

        #expect(all.yearTitle == "Your 2026")
        #expect(all.journals?.map(\.title) == ["Shipping year", "Garden year"])
        #expect(all.biggestWins.map(\.text) == ["Launched the app", "Ran a 10k"])
        // Sarah appears once per journal, each tagged, never merged
        #expect(all.peopleMentioned.map(\.category) == [.work, .personal])
        #expect(all.stats?.sessionCount == 9)
        #expect(all.storyText.hasPrefix("WORK\nShipping year"))
    }

    @Test func allWithOneJournalUsesItsTitle() throws {
        let work = journalWrap("Shipping year", item: "Launched the app", category: .work, person: "Sarah")
        let all = try #require(YearWrapData.combining([.work: work], year: 2026, stats: nil))
        #expect(all.yearTitle == "Shipping year")
        #expect(all.journals?.count == 1)
        #expect(YearWrapData.combining([:], year: 2026, stats: nil) == nil)
    }

    @Test func journalsSurviveSavingAndRedaction() throws {
        let work = journalWrap("Work with Maria", item: "Launched the app", category: .work, person: "Maria")
        let all = try #require(YearWrapData.combining([.work: work], year: 2026, stats: nil))
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let parsed = try #require(YearWrapData.parse(String(decoding: try encoder.encode(all), as: UTF8.self)))
        #expect(parsed.journals?.first?.category == .work)
        #expect(parsed.peopleMentioned.first?.category == .work)
        #expect(parsed.redacted(people: true, places: false).journals?.first?.title == "Work with [Person]")
    }
}
