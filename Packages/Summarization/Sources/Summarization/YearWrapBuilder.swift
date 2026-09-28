//
//  YearWrapBuilder.swift
//  Summarization
//
//  Builds Year Wrap from the year's month digests instead of from every session
//  summary. Twelve digests are small enough for one request to a cloud model, and
//  each section is small enough for the on-device models.
//
//  Numbers, people, places, topics and project status come from the digests in
//  code. The model only picks and phrases the most significant items from a list
//  of candidates and writes the title and summary. Every item it returns points
//  at candidates, so it keeps the recordings it came from and their real
//  work/personal category. Anything the model leaves out stays in the digests.
//

import Foundation
import SharedModels

public enum YearWrapBuilder {

    /// A digest item that can appear in the wrap, with a short id the model can refer to
    struct Candidate {
        let id: Int
        let item: DigestItem
        /// Months the item was mentioned in, e.g. "Feb, Mar"
        let months: [String]
        /// Projects only: status by month, e.g. "Mar started, Aug done"
        let timeline: String?

        var line: String {
            var parts = ["[\(id)] \(item.text)"]
            var details: [String] = []
            if item.mentions > 1 { details.append("×\(item.mentions)") }
            if !months.isEmpty { details.append(months.joined(separator: ", ")) }
            if let timeline { details.append(timeline) }
            if let category = item.category { details.append(category.rawValue) }
            if !details.isEmpty { parts.append("(\(details.joined(separator: "; ")))") }
            return parts.joined(separator: " ")
        }
    }

    /// The sections the model picks items for, with the candidate kinds each draws from
    enum Section: String, CaseIterable {
        case majorArcs = "major_arcs"
        case biggestWins = "biggest_wins"
        case biggestLosses = "biggest_losses"
        case biggestChallenges = "biggest_challenges"
        case valuableActionsTaken = "valuable_actions_taken"
        case opportunitiesMissed = "opportunities_missed"

        var instruction: String {
            switch self {
            case .majorArcs: return "the big storylines of my year, following projects and themes across months"
            case .biggestWins: return "my biggest wins and accomplishments"
            case .biggestLosses: return "real losses or setbacks (leave empty if there were none)"
            case .biggestChallenges: return "my biggest challenges and problems"
            case .valuableActionsTaken: return "the most valuable decisions and actions I took"
            case .opportunitiesMissed: return "things I dropped, kept putting off or left unresolved"
            }
        }

        var limit: Int {
            switch self {
            case .majorArcs: return 5
            case .biggestLosses: return 3
            default: return 6
            }
        }
    }

    // MARK: - Build

    /// Build one wrap. `scope` is Work or Personal when the digests were sliced to that category
    /// (see `MonthDigest.slice(for:)`); the model is then told to write about that part of life only.
    public static func build(year: Int, digests: [MonthDigest], generator: (any TextGenerating)?, scope: ItemFilter = .all) async -> YearWrapData {
        let digests = digests.sorted { $0.monthStart < $1.monthStart }
        let stats = computeStats(digests)
        let yearItems = mergeYear(digests)
        let candidates = makeCandidates(yearItems, digests: digests)
        let pools = sectionPools(candidates)

        var picks: [Section: [ClassifiedItem]] = [:]
        var title: String?
        var summary: String?

        if let generator {
            if generator.fitsWholeYear {
                if let result = try? await generateWhole(year: year, digests: digests, stats: stats, pools: pools, generator: generator, scope: scope) {
                    picks = result.picks
                    title = result.title
                    summary = result.summary
                }
            } else if generator.tier == .local {
                // The offline model is slow, so it gets one compact request for everything and,
                // only if that answer can't be read, one more for the title and summary
                if let result = try? await generateCompact(year: year, digests: digests, stats: stats, pools: pools, generator: generator, scope: scope) {
                    picks = result.picks
                    title = result.title
                    summary = result.summary
                } else if let result = try? await generateTitleSummary(year: year, digests: digests, stats: stats, candidates: candidates, generator: generator, scope: scope) {
                    title = result.title
                    summary = result.summary
                }
            } else {
                for section in Section.allCases {
                    guard let pool = pools[section], !pool.isEmpty else { continue }
                    if let items = try? await generateSection(section, pool: pool, year: year, generator: generator, scope: scope) {
                        picks[section] = items
                    }
                }
                if let result = try? await generateTitleSummary(year: year, digests: digests, stats: stats, candidates: candidates, generator: generator, scope: scope) {
                    title = result.title
                    summary = result.summary
                }
            }
        }

        // Anything the model didn't produce, or answered with nothing usable, falls back to the
        // most-mentioned candidates. An empty Losses list is a real answer, so it stays empty.
        for section in Section.allCases {
            let usable = section == .biggestLosses ? picks[section] != nil : !(picks[section] ?? []).isEmpty
            if !usable {
                picks[section] = fallbackPicks(section, pool: pools[section] ?? [])
            }
        }

        let projects = yearItems.filter { $0.kind == .project }
        return YearWrapData(
            yearTitle: usableTitle(title, year: year) ?? defaultTitle(year: year, scope: scope),
            yearSummary: summary ?? basicSummary(stats: stats, items: yearItems),
            majorArcs: picks[.majorArcs] ?? [],
            biggestWins: picks[.biggestWins] ?? [],
            biggestLosses: picks[.biggestLosses] ?? [],
            biggestChallenges: picks[.biggestChallenges] ?? [],
            finishedProjects: projects.filter { $0.status == .done }.prefix(8).map(classified),
            unfinishedProjects: projects.filter { $0.status != .done }.prefix(8).map(classified),
            topWorkedOnTopics: topByMentions(yearItems, kinds: [.project, .topic], limit: 8),
            topTalkedAboutThings: topByMentions(yearItems, kinds: [.topic, .idea, .note], limit: 8),
            valuableActionsTaken: picks[.valuableActionsTaken] ?? [],
            opportunitiesMissed: picks[.opportunitiesMissed] ?? [],
            peopleMentioned: yearItems.filter { $0.kind == .person }.prefix(10).map {
                PersonMention(name: $0.text, relationship: nil, impact: mentionPhrase($0.mentions), sessionIds: $0.sessionIds)
            },
            placesVisited: yearItems.filter { $0.kind == .place }.prefix(10).map {
                PlaceVisit(name: $0.text, frequency: frequency($0.mentions), context: nil, sessionIds: $0.sessionIds)
            },
            stats: stats
        )
    }

    public static func jsonString(_ wrap: YearWrapData) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(wrap), as: UTF8.self)
    }

    // MARK: - Stats and merging

    /// The year's numbers from its month digests, without a model. For All, pass each month's
    /// two journals combined (MonthDigest.combining) so a shared day counts once.
    public static func stats(for digests: [MonthDigest]) -> YearWrapStats {
        computeStats(digests.sorted { $0.monthStart < $1.monthStart })
    }

    static func computeStats(_ digests: [MonthDigest]) -> YearWrapStats {
        let busiest = digests.max { $0.stats.sessionCount < $1.stats.sessionCount }
        return YearWrapStats(
            sessionCount: digests.reduce(0) { $0 + $1.stats.sessionCount },
            totalMinutes: digests.reduce(0) { $0 + $1.stats.totalMinutes },
            wordCount: digests.reduce(0) { $0 + $1.stats.wordCount },
            activeDays: digests.reduce(0) { $0 + $1.stats.activeDays },
            workCount: digests.reduce(0) { $0 + $1.stats.workCount },
            personalCount: digests.reduce(0) { $0 + $1.stats.personalCount },
            busiestMonth: busiest.map { Calendar.current.component(.month, from: $0.monthStart) }
        )
    }

    /// All months' items merged. Months are merged in order, so a project ends with its latest status.
    static func mergeYear(_ digests: [MonthDigest]) -> [DigestItem] {
        MonthDigestBuilder.merge(digests.flatMap { $0.items })
    }

    static func makeCandidates(_ items: [DigestItem], digests: [MonthDigest]) -> [Candidate] {
        let monthName: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated)) }
        return items.enumerated().map { index, item in
            let key = MonthDigestBuilder.normalize(item.text)
            var months: [String] = []
            var timeline: [String] = []
            for digest in digests {
                guard let match = digest.items.first(where: { $0.kind == item.kind && MonthDigestBuilder.normalize($0.text) == key }) else { continue }
                months.append(monthName(digest.monthStart))
                if let status = match.status { timeline.append("\(monthName(digest.monthStart)) \(status.rawValue)") }
            }
            return Candidate(id: index + 1, item: item, months: months, timeline: timeline.isEmpty ? nil : timeline.joined(separator: ", "))
        }
    }

    /// Which candidates each section chooses from, most-mentioned first
    static func sectionPools(_ candidates: [Candidate]) -> [Section: [Candidate]] {
        func pool(_ include: (DigestItem) -> Bool) -> [Candidate] {
            candidates.filter { include($0.item) }.sorted { $0.item.mentions > $1.item.mentions }
        }
        return [
            .majorArcs: pool { $0.kind == .project || ($0.kind == .topic && $0.mentions > 1) },
            .biggestWins: pool { $0.kind == .win || ($0.kind == .project && $0.status == .done) },
            .biggestLosses: pool { $0.kind == .challenge || ($0.kind == .project && $0.status == .dropped) },
            .biggestChallenges: pool { $0.kind == .challenge },
            .valuableActionsTaken: pool { $0.kind == .decision },
            .opportunitiesMissed: pool { $0.kind == .openLoop || $0.kind == .idea || ($0.kind == .project && $0.status == .dropped) },
        ]
    }

    // MARK: - Model steps

    static let systemInstruction = """
    You are writing my personal Year Wrap from my own voice-journal notes.
    Write in first person ("I", "my"). Use only the notes given. Do not invent anything.
    Return only valid JSON, with no markdown and no commentary.
    """

    /// The system instruction, narrowed to work or personal life for those wraps
    static func systemInstruction(_ scope: ItemFilter) -> String {
        switch scope {
        case .all: return systemInstruction
        case .workOnly: return systemInstruction + "\nThese notes come only from my work recordings. This is my work year: write about work only."
        case .personalOnly: return systemInstruction + "\nThese notes come only from my personal recordings. This is my personal year: write about my personal life only."
        }
    }

    static func defaultTitle(year: Int, scope: ItemFilter) -> String {
        switch scope {
        case .all: return "My \(year)"
        case .workOnly: return "My \(year) at work"
        case .personalOnly: return "My personal \(year)"
        }
    }

    /// Candidates that fit the budget, most-mentioned first
    static func capped(_ pool: [Candidate], tokenBudget: Int) -> [Candidate] {
        var result: [Candidate] = []
        var used = 0
        for candidate in pool {
            let tokens = estimatedTokens(candidate.line)
            guard used + tokens <= tokenBudget else { break }
            result.append(candidate)
            used += tokens
        }
        return result
    }

    static func generateSection(_ section: Section, pool: [Candidate], year: Int, generator: any TextGenerating, scope: ItemFilter = .all) async throws -> [ClassifiedItem] {
        let shown = capped(pool, tokenBudget: generator.inputTokenBudget)
        let user = """
        These are notes from my \(year). Each has an id in brackets, how often I mentioned it and when.

        \(shown.map(\.line).joined(separator: "\n"))

        Pick up to \(section.limit) items for: \(section.instruction).
        Merge notes about the same thing into one item and list all their ids.
        Rewrite each as a short, specific sentence in first person.

        Return: {"items":[{"t":"<sentence>","ids":[<ids>]}]}
        """
        let output = try await generator.generateText(system: systemInstruction(scope), user: user, maxTokens: 500)
        #if DEBUG
        print("🎁 [YearWrapBuilder] \(section.rawValue) answer: \(output.prefix(300))")
        #endif
        if let json = ModelJSON.object(from: output), let items = json["items"] {
            return parsePicks(items, candidates: shown, limit: section.limit)
        }
        // Some models answer with the bare list
        if let list = jsonArray(from: output) {
            return parsePicks(list, candidates: shown, limit: section.limit)
        }
        throw SummarizationError.decodingFailed("No JSON for \(section.rawValue)")
    }

    static func generateTitleSummary(year: Int, digests: [MonthDigest], stats: YearWrapStats, candidates: [Candidate], generator: any TextGenerating, scope: ItemFilter = .all) async throws -> (title: String?, summary: String?) {
        let months = monthLines(digests)
        let top = capped(candidates.sorted { $0.item.mentions > $1.item.mentions }, tokenBudget: max(generator.inputTokenBudget - estimatedTokens(months), 300))
        let user = """
        My \(year): \(stats.sessionCount) recordings on \(stats.activeDays) days.

        Month by month:
        \(months)

        Things I mentioned most:
        \(top.map(\.line).joined(separator: "\n"))

        Write a title for my year (under 8 words) and a summary of 4 to 6 sentences in first person, using only these notes.
        Return: {"year_title":"<title>","year_summary":"<summary>"}
        """
        let output = try await generator.generateText(system: systemInstruction(scope), user: user, maxTokens: 400)
        guard let json = ModelJSON.object(from: output) else { throw SummarizationError.decodingFailed("No JSON for title") }
        return ((json["year_title"] as? String)?.trimmedNonEmpty, (json["year_summary"] as? String)?.trimmedNonEmpty)
    }

    /// One request for everything, for models with room for the whole year
    static func generateWhole(year: Int, digests: [MonthDigest], stats: YearWrapStats, pools: [Section: [Candidate]], generator: any TextGenerating, scope: ItemFilter = .all) async throws -> (title: String?, summary: String?, picks: [Section: [ClassifiedItem]]) {
        let perSectionBudget = max(generator.inputTokenBudget / (Section.allCases.count + 1), 500)
        var shown: [Section: [Candidate]] = [:]
        var blocks: [String] = []
        for section in Section.allCases {
            let pool = capped(pools[section] ?? [], tokenBudget: perSectionBudget)
            shown[section] = pool
            guard !pool.isEmpty else { continue }
            blocks.append("\(section.rawValue): up to \(section.limit) items for \(section.instruction)\n" + pool.map(\.line).joined(separator: "\n"))
        }

        let user = """
        My \(year): \(stats.sessionCount) recordings on \(stats.activeDays) days.

        Month by month:
        \(monthLines(digests))

        For each section below, pick the most significant items from its candidates. Each candidate has an id in brackets,
        how often I mentioned it and when. Merge candidates about the same thing into one item and list all their ids.
        Rewrite each item as a short, specific sentence in first person. Leave a section empty if nothing fits.

        \(blocks.joined(separator: "\n\n"))

        Also write a title for my year (under 8 words) and a summary of 4 to 6 sentences in first person.

        Return: {"year_title":"<title>","year_summary":"<summary>",\(Section.allCases.map { "\"\($0.rawValue)\":[{\"t\":\"<sentence>\",\"ids\":[<ids>]}]" }.joined(separator: ","))}
        """
        let output = try await generator.generateText(system: systemInstruction(scope), user: user, maxTokens: generator.outputTokenBudget)
        guard let json = ModelJSON.object(from: output) else { throw SummarizationError.decodingFailed("No JSON for Year Wrap") }

        var picks: [Section: [ClassifiedItem]] = [:]
        for section in Section.allCases where json[section.rawValue] != nil {
            picks[section] = parsePicks(json[section.rawValue], candidates: shown[section] ?? [], limit: section.limit)
        }
        return ((json["year_title"] as? String)?.trimmedNonEmpty, (json["year_summary"] as? String)?.trimmedNonEmpty, picks)
    }

    /// One short request for everything, for a small, slow model: fewer candidates per section,
    /// fewer picks, and each month reduced to its headline, so the prompt and the answer both fit
    /// the model's budgets. Sections it leaves empty are filled from the digests by the caller.
    static func generateCompact(year: Int, digests: [MonthDigest], stats: YearWrapStats, pools: [Section: [Candidate]], generator: any TextGenerating, scope: ItemFilter = .all) async throws -> (title: String?, summary: String?, picks: [Section: [ClassifiedItem]]) {
        let months = monthLines(digests, maxCharacters: 140)
        let instructionTokens = 320
        let perSectionBudget = max((generator.inputTokenBudget - estimatedTokens(months) - instructionTokens) / Section.allCases.count, 120)
        var shown: [Section: [Candidate]] = [:]
        var blocks: [String] = []
        for section in Section.allCases {
            let pool = capped(pools[section] ?? [], tokenBudget: perSectionBudget)
            shown[section] = pool
            guard !pool.isEmpty else { continue }
            blocks.append("\(section.rawValue) (up to \(compactLimit(section)), \(section.instruction)):\n" + pool.map(\.line).joined(separator: "\n"))
        }

        let user = """
        My \(year): \(stats.sessionCount) recordings on \(stats.activeDays) days.

        Months:
        \(months)

        Candidates have an id in brackets. For each section pick the most significant ones, merge duplicates and list their ids,
        and rewrite each as one short first-person sentence. Leave a section empty if nothing fits.

        \(blocks.joined(separator: "\n\n"))

        Also a title for my year (under 8 words) and a 3-sentence first-person summary.
        Return only JSON: {"year_title":"","year_summary":"",\(Section.allCases.map { "\"\($0.rawValue)\":[{\"t\":\"\",\"ids\":[]}]" }.joined(separator: ","))}
        """
        let output = try await generator.generateText(system: systemInstruction(scope), user: user, maxTokens: generator.outputTokenBudget)
        #if DEBUG
        print("🎁 [YearWrapBuilder] compact answer: \(output.prefix(300))")
        #endif
        guard let json = ModelJSON.object(from: output) else { throw SummarizationError.decodingFailed("No JSON for Year Wrap") }

        var picks: [Section: [ClassifiedItem]] = [:]
        for section in Section.allCases where json[section.rawValue] != nil {
            picks[section] = parsePicks(json[section.rawValue], candidates: shown[section] ?? [], limit: compactLimit(section))
        }
        return ((json["year_title"] as? String)?.trimmedNonEmpty, (json["year_summary"] as? String)?.trimmedNonEmpty, picks)
    }

    /// Fewer picks per section for the compact request, so the answer fits the output budget
    static func compactLimit(_ section: Section) -> Int {
        section == .biggestLosses ? 2 : 3
    }

    /// Turn the model's picks into wrap items. A pick must name at least one candidate it was shown;
    /// it takes their recordings and category, so neither is guessed.
    static func parsePicks(_ value: Any?, candidates: [Candidate], limit: Int) -> [ClassifiedItem] {
        guard let objects = value as? [[String: Any]] else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        var result: [ClassifiedItem] = []
        for object in objects {
            let rawIds = object["ids"] ?? object["id"] ?? object["s"]
            let ids = ((rawIds as? [Any]) ?? rawIds.map { [$0] } ?? []).compactMap { MonthDigestBuilder.sessionIndex(from: $0) }
            // A model that copies the "<sentence>" placeholder gets the candidate's own wording
            let pickText = ((object["t"] ?? object["text"]) as? String)?.trimmedNonEmpty
                .flatMap { $0.contains("<") && $0.contains(">") ? nil : $0 }
            var named = ids.compactMap { byId[$0] }
            // No usable ids: match the pick to candidates by its words instead
            if named.isEmpty, let pickText {
                named = candidates.filter { sharesWords($0.item.text, pickText) }
            }
            guard !named.isEmpty else { continue }
            let text = pickText ?? named[0].item.text
            // Small models sometimes list unrelated ids. Keep the ones that share words with the pick;
            // if none do, the pick was a rewrite and all its ids stand.
            let related = named.filter { sharesWords($0.item.text, text) }
            let chosen = related.isEmpty ? named : related
            var sessionIds: [UUID] = []
            for id in chosen.flatMap({ $0.item.sessionIds }) where !sessionIds.contains(id) { sessionIds.append(id) }
            let category = MonthDigestBuilder.combinedCategory(sessionIds: [], categories: [:], itemCategories: chosen.compactMap { $0.item.category })
            result.append(ClassifiedItem(text: text, category: category ?? .both, sessionIds: sessionIds))
            if result.count == limit { break }
        }
        return result
    }

    /// The outermost [...] in a model answer, parsed
    static func jsonArray(from text: String) -> [[String: Any]]? {
        guard let open = text.firstIndex(of: "["), let close = text.lastIndex(of: "]"), open < close,
              let data = String(text[open...close]).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    /// True when the two texts share a word of 4+ letters (or its first 5 letters)
    static func sharesWords(_ a: String, _ b: String) -> Bool {
        let words: (String) -> [String] = { MonthDigestBuilder.normalize($0).split(separator: " ").map(String.init).filter { $0.count >= 4 } }
        let left = words(a), right = words(b)
        return left.contains { l in right.contains { r in l == r || l.prefix(5) == r.prefix(5) } }
    }

    /// A title that only repeats the year adds nothing to the screen that already shows it
    static func usableTitle(_ title: String?, year: Int) -> String? {
        guard let title, MonthDigestBuilder.normalize(title) != String(year) else { return nil }
        return title
    }

    static func monthLines(_ digests: [MonthDigest], maxCharacters: Int? = nil) -> String {
        digests.map { digest in
            let month = digest.monthStart.formatted(.dateTime.month(.abbreviated))
            var text = [digest.headline, digest.narrative].compactMap { $0 }.joined(separator: " ")
            // A month combined from two journals keeps each journal's story in its section
            if text.isEmpty, let sections = digest.sections {
                text = sections.compactMap { section -> String? in
                    let story = [section.headline, section.narrative].compactMap { $0 }.joined(separator: " ")
                    return story.isEmpty ? nil : "\(section.category.rawValue.capitalized): \(story)"
                }.joined(separator: " ")
            }
            if let maxCharacters, text.count > maxCharacters {
                text = String(text.prefix(maxCharacters)).trimmingCharacters(in: .whitespaces) + "…"
            }
            return "- \(month) (\(digest.stats.sessionCount) recordings): \(text)"
        }.joined(separator: "\n")
    }

    // MARK: - Without a model

    static func fallbackPicks(_ section: Section, pool: [Candidate]) -> [ClassifiedItem] {
        // Losses can't be told apart from challenges without a model; leave them to Challenges
        guard section != .biggestLosses else { return [] }
        return pool.prefix(section.limit).map { classified($0.item) }
    }

    static func classified(_ item: DigestItem) -> ClassifiedItem {
        ClassifiedItem(text: item.text, category: item.category ?? .both, sessionIds: item.sessionIds)
    }

    static func topByMentions(_ items: [DigestItem], kinds: Set<DigestItemKind>, limit: Int) -> [ClassifiedItem] {
        items.filter { kinds.contains($0.kind) }
            .sorted { $0.mentions > $1.mentions }
            .prefix(limit)
            .map(classified)
    }

    static func basicSummary(stats: YearWrapStats, items: [DigestItem]) -> String {
        let recordings = stats.sessionCount == 1 ? "1 recording" : "\(stats.sessionCount) recordings"
        var summary = "I made \(recordings) on \(stats.activeDays) days this year, about \(stats.totalMinutes) minutes in all."
        let top = items.filter { [.project, .topic].contains($0.kind) }.sorted { $0.mentions > $1.mentions }.prefix(3).map { $0.text }
        if !top.isEmpty {
            summary += " What I talked about most: \(top.joined(separator: ", "))."
        }
        return summary
    }

    static func mentionPhrase(_ mentions: Int) -> String {
        mentions == 1 ? "Mentioned in 1 recording" : "Mentioned in \(mentions) recordings"
    }

    static func frequency(_ mentions: Int) -> String {
        switch mentions {
        case ..<2: return "once"
        case 2..<5: return "occasionally"
        default: return "frequently"
        }
    }
}
