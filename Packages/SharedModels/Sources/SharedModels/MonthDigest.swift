// =============================================================================
// MonthDigest.swift — Structured record of one month, the input for Year Wrap
// =============================================================================
//
// A digest is a list of atomic items (wins, decisions, projects, people...) that
// each point back to the recordings they came from, plus numbers computed in code.
// Items are merged and counted across recordings, never re-summarized into prose,
// so detail survives from session to month to year.
//
// Stored as JSON in the `text` column of a `summaries` row with period type
// `.monthDigest`. It is derived data and can be rebuilt from session summaries.

import Foundation

public enum DigestItemKind: String, Codable, Sendable, CaseIterable {
    case win
    case challenge
    case decision
    case project
    case idea
    case openLoop
    case person
    case place
    case topic
    /// A key point that wasn't classified (Basic engine, or a failed extraction)
    case note

    public var displayName: String {
        switch self {
        case .win: return "Wins"
        case .challenge: return "Challenges"
        case .decision: return "Decisions"
        case .project: return "Projects"
        case .idea: return "Ideas"
        case .openLoop: return "Open loops"
        case .person: return "People"
        case .place: return "Places"
        case .topic: return "Topics"
        case .note: return "Key points"
        }
    }

    /// The order items are shown and copied in: what happened first, then who and where
    public static let displayOrder: [DigestItemKind] = [
        .win, .project, .decision, .challenge, .idea, .openLoop, .person, .place, .topic, .note
    ]

    public var icon: String {
        switch self {
        case .win: return "trophy"
        case .challenge: return "exclamationmark.triangle"
        case .decision: return "checkmark.seal"
        case .project: return "hammer"
        case .idea: return "lightbulb"
        case .openLoop: return "circle.dashed"
        case .person: return "person.2"
        case .place: return "mappin.and.ellipse"
        case .topic: return "number"
        case .note: return "list.bullet"
        }
    }
}

public enum ProjectStatus: String, Codable, Sendable {
    case started
    case ongoing
    case done
    case dropped
}

public struct DigestItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(kind.rawValue):\(text)" }

    public let kind: DigestItemKind
    public let text: String
    /// Taken from the recordings' own work/personal category, never guessed by the model.
    /// `.both` when the source recordings disagree, nil when none were categorized.
    public let category: ItemCategory?
    /// How many recordings mentioned this item
    public let mentions: Int
    public let sessionIds: [UUID]
    /// Only for projects: the latest status seen
    public let status: ProjectStatus?

    public init(
        kind: DigestItemKind,
        text: String,
        category: ItemCategory? = nil,
        mentions: Int = 1,
        sessionIds: [UUID] = [],
        status: ProjectStatus? = nil
    ) {
        self.kind = kind
        self.text = text
        self.category = category
        self.mentions = mentions
        self.sessionIds = sessionIds
        self.status = status
    }
}

public struct DigestStats: Codable, Sendable, Hashable {
    public let sessionCount: Int
    public let totalMinutes: Int
    public let wordCount: Int
    public let activeDays: Int
    public let workCount: Int
    public let personalCount: Int
    /// Days of the month (1-31) with recordings, so two journals' days can be combined
    /// without counting a shared day twice. Nil in digests made before journals.
    public let days: [Int]?

    public init(sessionCount: Int, totalMinutes: Int, wordCount: Int, activeDays: Int, workCount: Int, personalCount: Int, days: [Int]? = nil) {
        self.sessionCount = sessionCount
        self.totalMinutes = totalMinutes
        self.wordCount = wordCount
        self.activeDays = activeDays
        self.workCount = workCount
        self.personalCount = personalCount
        self.days = days
    }

    /// Two journals' numbers added up. Shared days count once when both know their days.
    public static func combining(_ stats: [DigestStats]) -> DigestStats {
        let dayLists = stats.compactMap(\.days)
        let days = dayLists.count == stats.count ? Array(Set(dayLists.flatMap { $0 })).sorted() : nil
        return DigestStats(
            sessionCount: stats.reduce(0) { $0 + $1.sessionCount },
            totalMinutes: stats.reduce(0) { $0 + $1.totalMinutes },
            wordCount: stats.reduce(0) { $0 + $1.wordCount },
            activeDays: days?.count ?? stats.map(\.activeDays).max() ?? 0,
            workCount: stats.reduce(0) { $0 + $1.workCount },
            personalCount: stats.reduce(0) { $0 + $1.personalCount },
            days: days
        )
    }
}

/// Work or Personal slice of a month: its own numbers and, when a model was used, its own
/// headline and narrative written only from that category's items
public struct CategorySection: Codable, Sendable, Hashable {
    public let category: ItemCategory
    public let stats: DigestStats
    public let headline: String?
    public let narrative: String?

    public init(category: ItemCategory, stats: DigestStats, headline: String?, narrative: String?) {
        self.category = category
        self.stats = stats
        self.headline = headline
        self.narrative = narrative
    }
}

extension DigestItem {
    /// Work shows work items, Personal shows personal ones; items whose recordings span both show under each.
    /// Items from uncategorized recordings only show under All.
    public func matches(_ filter: ItemFilter) -> Bool {
        switch filter {
        case .all: return true
        case .workOnly: return category == .work || category == .both
        case .personalOnly: return category == .personal || category == .both
        }
    }
}

public struct MonthDigest: Codable, Sendable, Hashable {
    /// First instant of the month
    public let monthStart: Date
    /// True once the month has ended. The current month keeps a draft that is rebuilt as recordings come in.
    public let isFinal: Bool
    public let stats: DigestStats
    public let headline: String?
    public let narrative: String?
    public let items: [DigestItem]
    /// Engine that extracted the items ("basic", "local", "apple", "external")
    public let engineTier: String
    /// One per category that had recordings this month. Nil in digests made before the split.
    public let sections: [CategorySection]?
    /// The journal this digest was built from. Nil for older digests that mixed both.
    public let journal: SessionCategory?

    public init(
        monthStart: Date,
        isFinal: Bool,
        stats: DigestStats,
        headline: String?,
        narrative: String?,
        items: [DigestItem],
        engineTier: String,
        sections: [CategorySection]? = nil,
        journal: SessionCategory? = nil
    ) {
        self.monthStart = monthStart
        self.isFinal = isFinal
        self.stats = stats
        self.headline = headline
        self.narrative = narrative
        self.items = items
        self.engineTier = engineTier
        self.sections = sections
        self.journal = journal
    }

    public func items(of kind: DigestItemKind, filter: ItemFilter = .all) -> [DigestItem] {
        items.filter { $0.kind == kind && $0.matches(filter) }
    }

    public func section(for category: ItemCategory) -> CategorySection? {
        sections?.first { $0.category == category }
    }

    /// Numbers for the chosen filter; nil when that category had no recordings this month
    public func stats(for filter: ItemFilter) -> DigestStats? {
        switch filter {
        case .all: return stats
        case .workOnly: return section(for: .work)?.stats
        case .personalOnly: return section(for: .personal)?.stats
        }
    }

    /// Headline and narrative for the chosen filter. A month with only one category uses the
    /// combined text for it; otherwise a category shows only text written from its own items.
    public func story(for filter: ItemFilter) -> (headline: String?, narrative: String?) {
        let category: ItemCategory
        switch filter {
        case .all: return (headline, narrative)
        case .workOnly: category = .work
        case .personalOnly: category = .personal
        }
        guard let section = section(for: category) else { return (nil, nil) }
        if sections?.count == 1 { return (headline, narrative) }
        return (section.headline, section.narrative)
    }

    /// Each journal's headline and narrative as one piece of text, for a month combined from both
    public var journalStories: [(title: String, story: String)] {
        (sections ?? []).compactMap { section in
            let story = [section.headline, section.narrative].compactMap { $0 }.joined(separator: ". ")
            guard !story.isEmpty else { return nil }
            return (section.category == .work ? "Work" : "Personal", story)
        }
    }

    /// The month as readable text for copying: title, story, numbers and every item, for one filter
    public func plainText(filter: ItemFilter) -> String {
        var title = monthStart.formatted(.dateTime.month(.wide).year())
        switch filter {
        case .all: break
        case .workOnly: title += " · Work"
        case .personalOnly: title += " · Personal"
        }
        var blocks = [title]
        guard let stats = stats(for: filter) else {
            blocks.append("No \(filter == .workOnly ? "work" : "personal") recordings this month.")
            return blocks.joined(separator: "\n\n")
        }
        let story = story(for: filter)
        if let headline = story.headline { blocks.append(headline) }
        if let narrative = story.narrative { blocks.append(narrative) }
        if filter == .all, story.headline == nil, story.narrative == nil {
            blocks += journalStories.map { "\($0.title): \($0.story)" }
        }
        let recordings = stats.sessionCount == 1 ? "1 recording" : "\(stats.sessionCount) recordings"
        let days = stats.activeDays == 1 ? "1 day" : "\(stats.activeDays) days"
        blocks.append("\(recordings) · \(days) · \(stats.totalMinutes) min")
        for kind in DigestItemKind.displayOrder {
            let kindItems = items(of: kind, filter: filter)
            guard !kindItems.isEmpty else { continue }
            let lines = kindItems.map { item -> String in
                var line = "- \(item.text)"
                if let status = item.status { line += " (\(status.rawValue))" }
                if item.mentions > 1 { line += " ×\(item.mentions)" }
                return line
            }
            blocks.append(([kind.displayName] + lines).joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }

    /// The month as seen by one filter: that category's numbers, story and items.
    /// Nil when the category had no recordings this month. All returns the digest unchanged.
    public func slice(for filter: ItemFilter) -> MonthDigest? {
        guard filter != .all else { return self }
        guard let stats = stats(for: filter) else { return nil }
        let story = story(for: filter)
        let category: ItemCategory = filter == .workOnly ? .work : .personal
        return MonthDigest(monthStart: monthStart, isFinal: isFinal, stats: stats, headline: story.headline,
                           narrative: story.narrative, items: items.filter { $0.matches(filter) }, engineTier: engineTier,
                           sections: sections?.filter { $0.category == category },
                           journal: filter == .workOnly ? .work : .personal)
    }

    public func withFinal(_ isFinal: Bool) -> MonthDigest {
        MonthDigest(monthStart: monthStart, isFinal: isFinal, stats: stats, headline: headline,
                    narrative: narrative, items: items, engineTier: engineTier, sections: sections, journal: journal)
    }

    /// The month across both journals, put together in code: numbers added up, each journal's
    /// items and story kept as its own section. Nothing is merged across journals, so an item
    /// stays Work or Personal. With one journal, that journal's digest is returned as is.
    public static func combining(_ digests: [MonthDigest]) -> MonthDigest? {
        guard let first = digests.first else { return nil }
        guard digests.count > 1 else { return first }
        let ordered = digests.sorted { ($0.journal == .work ? 0 : 1) < ($1.journal == .work ? 0 : 1) }
        let sections = ordered.compactMap { digest -> CategorySection? in
            guard let journal = digest.journal else { return nil }
            return CategorySection(category: journal == .work ? .work : .personal, stats: digest.stats,
                                   headline: digest.headline, narrative: digest.narrative)
        }
        let tiers = Set(ordered.map(\.engineTier))
        return MonthDigest(
            monthStart: first.monthStart,
            isFinal: ordered.allSatisfy(\.isFinal),
            stats: DigestStats.combining(ordered.map(\.stats)),
            headline: nil,
            narrative: nil,
            items: ordered.flatMap(\.items),
            engineTier: tiers.count == 1 ? first.engineTier : ordered.map(\.engineTier).joined(separator: "+"),
            sections: sections
        )
    }

    // MARK: - JSON

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func fromJSON(_ text: String) -> MonthDigest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(MonthDigest.self, from: Data(text.utf8))
    }
}
