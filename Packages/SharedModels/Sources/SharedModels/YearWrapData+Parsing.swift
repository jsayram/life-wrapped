//
//  YearWrapData+Parsing.swift
//  SharedModels
//
//  Reads a stored Year Wrap back into YearWrapData, and hides people and place
//  names for sharing. Used by both the Year Wrap screen and the PDF export.
//

import Foundation

extension YearWrapData {

    /// Parse a stored Year Wrap. Handles the current format, older wraps whose sections
    /// are plain strings, and the old simplified local-model format. Nil when the text
    /// isn't a Year Wrap at all.
    public static func parse(_ text: String) -> YearWrapData? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let yearSummary = json["year_summary"] as? String else {
            return nil
        }
        let yearTitle = json["year_title"] as? String ?? "Year in Review"

        // Current format: {"text": "...", "category": "work|personal|both", "session_ids": [...]}
        // Older wraps: plain strings, which apply to both work and personal
        func items(_ key: String) -> [ClassifiedItem] {
            guard let array = json[key] as? [Any] else { return [] }
            return array.compactMap { item in
                if let dict = item as? [String: Any],
                   let text = dict["text"] as? String,
                   let categoryString = dict["category"] as? String,
                   let category = ItemCategory(rawValue: categoryString) {
                    return ClassifiedItem(text: text, category: category, sessionIds: uuids(dict["session_ids"]))
                }
                if let text = item as? String {
                    return ClassifiedItem(text: text, category: .both)
                }
                return nil
            }
        }

        if json["top_highlights"] != nil {
            return YearWrapData(
                yearTitle: yearTitle,
                yearSummary: yearSummary,
                majorArcs: [],
                biggestWins: items("top_highlights"),
                biggestLosses: [],
                biggestChallenges: items("biggest_challenges"),
                finishedProjects: [],
                unfinishedProjects: [],
                topWorkedOnTopics: items("top_topics"),
                topTalkedAboutThings: [],
                valuableActionsTaken: [],
                opportunitiesMissed: [],
                peopleMentioned: [],
                placesVisited: []
            )
        }

        return YearWrapData(
            yearTitle: yearTitle,
            yearSummary: yearSummary,
            majorArcs: items("major_arcs"),
            biggestWins: items("biggest_wins"),
            biggestLosses: items("biggest_losses"),
            biggestChallenges: items("biggest_challenges"),
            finishedProjects: items("finished_projects"),
            unfinishedProjects: items("unfinished_projects"),
            topWorkedOnTopics: items("top_worked_on_topics"),
            topTalkedAboutThings: items("top_talked_about_things"),
            valuableActionsTaken: items("valuable_actions_taken"),
            opportunitiesMissed: items("opportunities_missed"),
            peopleMentioned: (json["people_mentioned"] as? [[String: Any]] ?? []).compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                return PersonMention(name: name, relationship: dict["relationship"] as? String,
                                     impact: dict["impact"] as? String, sessionIds: uuids(dict["session_ids"]),
                                     category: (dict["category"] as? String).flatMap(ItemCategory.init(rawValue:)))
            },
            placesVisited: (json["places_visited"] as? [[String: Any]] ?? []).compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                return PlaceVisit(name: name, frequency: dict["frequency"] as? String,
                                  context: dict["context"] as? String, sessionIds: uuids(dict["session_ids"]),
                                  category: (dict["category"] as? String).flatMap(ItemCategory.init(rawValue:)))
            },
            stats: stats(json["stats"]),
            journals: (json["journals"] as? [[String: Any]])?.compactMap { dict in
                guard let category = (dict["category"] as? String).flatMap(SessionCategory.init(rawValue:)),
                      let title = dict["title"] as? String,
                      let summary = dict["summary"] as? String else { return nil }
                return JournalStory(category: category, title: title, summary: summary)
            }
        )
    }

    private static func uuids(_ value: Any?) -> [UUID]? {
        (value as? [String]).map { $0.compactMap(UUID.init(uuidString:)) }
    }

    private static func stats(_ value: Any?) -> YearWrapStats? {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(YearWrapStats.self, from: data)
    }

    // MARK: - Redaction

    /// A copy with the listed people and/or place names replaced everywhere they appear:
    /// the title, the summary, every section and the people and places lists themselves.
    /// Only names in those two lists are known, so other names in the text stay.
    public func redacted(people: Bool, places: Bool) -> YearWrapData {
        guard people || places else { return self }
        var replacements: [(name: String, placeholder: String)] = []
        if people { replacements += peopleMentioned.map { ($0.name, "[Person]") } }
        if places { replacements += placesVisited.map { ($0.name, "[Location]") } }
        // Longest first, so "Mary Jane" is replaced before "Mary"
        let patterns = replacements
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.name.count > $1.name.count }
            .compactMap { replacement -> (NSRegularExpression, String)? in
                let escaped = NSRegularExpression.escapedPattern(for: replacement.name)
                guard let regex = try? NSRegularExpression(
                    pattern: "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])",
                    options: [.caseInsensitive]
                ) else { return nil }
                return (regex, NSRegularExpression.escapedTemplate(for: replacement.placeholder))
            }

        func hide(_ text: String) -> String {
            patterns.reduce(text) { text, pattern in
                pattern.0.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: pattern.1)
            }
        }
        func hide(_ items: [ClassifiedItem]) -> [ClassifiedItem] {
            items.map { ClassifiedItem(text: hide($0.text), category: $0.category, sessionIds: $0.sessionIds) }
        }

        return YearWrapData(
            yearTitle: hide(yearTitle),
            yearSummary: hide(yearSummary),
            majorArcs: hide(majorArcs),
            biggestWins: hide(biggestWins),
            biggestLosses: hide(biggestLosses),
            biggestChallenges: hide(biggestChallenges),
            finishedProjects: hide(finishedProjects),
            unfinishedProjects: hide(unfinishedProjects),
            topWorkedOnTopics: hide(topWorkedOnTopics),
            topTalkedAboutThings: hide(topTalkedAboutThings),
            valuableActionsTaken: hide(valuableActionsTaken),
            opportunitiesMissed: hide(opportunitiesMissed),
            peopleMentioned: peopleMentioned.map {
                people
                    ? PersonMention(name: "[Person]", relationship: nil, impact: $0.impact.map(hide), sessionIds: $0.sessionIds, category: $0.category)
                    : PersonMention(name: hide($0.name), relationship: $0.relationship.map(hide), impact: $0.impact.map(hide), sessionIds: $0.sessionIds, category: $0.category)
            },
            placesVisited: placesVisited.map {
                places
                    ? PlaceVisit(name: "[Location]", frequency: $0.frequency, context: $0.context.map(hide), sessionIds: $0.sessionIds, category: $0.category)
                    : PlaceVisit(name: hide($0.name), frequency: $0.frequency, context: $0.context.map(hide), sessionIds: $0.sessionIds, category: $0.category)
            },
            stats: stats,
            journals: journals?.map { JournalStory(category: $0.category, title: hide($0.title), summary: hide($0.summary)) }
        )
    }
}

// MARK: - All, from the two journals

extension YearWrapData {

    /// The All wrap, put together in code from each journal's own wrap; no model is involved.
    /// Each journal keeps its title and summary, sections list the work items then the personal
    /// ones, and people and places are tagged with the journal they came from.
    /// `stats` are the year's numbers across both journals, computed from the month digests.
    /// With one journal, its wrap is returned with that journal's story attached.
    public static func combining(_ wraps: [SessionCategory: YearWrapData], year: Int, stats: YearWrapStats?) -> YearWrapData? {
        let ordered = SessionCategory.allCases.compactMap { journal in wraps[journal].map { (journal, $0) } }
        guard !ordered.isEmpty else { return nil }

        let stories = ordered.map { JournalStory(category: $0.0, title: $0.1.yearTitle, summary: $0.1.yearSummary) }
        func all(_ section: (YearWrapData) -> [ClassifiedItem]) -> [ClassifiedItem] {
            ordered.flatMap { section($0.1) }
        }
        let itemCategory: (SessionCategory) -> ItemCategory = { $0 == .work ? .work : .personal }

        return YearWrapData(
            yearTitle: ordered.count == 1 ? ordered[0].1.yearTitle : "Your \(year)",
            // For anything that reads only the summary text (copying, older screens)
            yearSummary: stories.map { "\($0.category.displayName): \($0.title). \($0.summary)" }.joined(separator: "\n\n"),
            majorArcs: all(\.majorArcs),
            biggestWins: all(\.biggestWins),
            biggestLosses: all(\.biggestLosses),
            biggestChallenges: all(\.biggestChallenges),
            finishedProjects: all(\.finishedProjects),
            unfinishedProjects: all(\.unfinishedProjects),
            topWorkedOnTopics: all(\.topWorkedOnTopics),
            topTalkedAboutThings: all(\.topTalkedAboutThings),
            valuableActionsTaken: all(\.valuableActionsTaken),
            opportunitiesMissed: all(\.opportunitiesMissed),
            peopleMentioned: ordered.flatMap { journal, wrap in
                wrap.peopleMentioned.map { PersonMention(name: $0.name, relationship: $0.relationship, impact: $0.impact,
                                                          sessionIds: $0.sessionIds, category: itemCategory(journal)) }
            },
            placesVisited: ordered.flatMap { journal, wrap in
                wrap.placesVisited.map { PlaceVisit(name: $0.name, frequency: $0.frequency, context: $0.context,
                                                     sessionIds: $0.sessionIds, category: itemCategory(journal)) }
            },
            stats: stats,
            journals: stories
        )
    }

    /// Plain text of the wrap's story for copying: each journal's title and summary under All
    public var storyText: String {
        guard let journals, !journals.isEmpty else { return yearSummary }
        return journals.map { "\($0.category.displayName.uppercased())\n\($0.title)\n\($0.summary)" }.joined(separator: "\n\n")
    }
}
