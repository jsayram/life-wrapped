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
}
