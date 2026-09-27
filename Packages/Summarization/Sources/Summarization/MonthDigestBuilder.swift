//
//  MonthDigestBuilder.swift
//  Summarization
//
//  Builds a MonthDigest from one month of session summaries.
//
//  The model only extracts items from small batches of recordings. Batches are
//  merged in code: duplicates are combined, mention counts added up and source
//  recordings kept, so nothing is compressed into prose on the way to Year Wrap.
//  When there is no model (Basic) or a step fails, items come from the stored
//  key points and entities instead, so a digest is always produced.
//

import Foundation
import SharedModels

/// One recording's input to a month digest
public struct DigestSource: Sendable {
    public let sessionId: UUID
    public let start: Date
    public let duration: TimeInterval
    public let wordCount: Int
    public let summary: String
    /// Key points or topics stored with the session summary
    public let keyPoints: [String]
    public let entities: [Entity]
    public let category: SessionCategory?
    public let notes: String?

    public init(
        sessionId: UUID,
        start: Date,
        duration: TimeInterval,
        wordCount: Int,
        summary: String,
        keyPoints: [String] = [],
        entities: [Entity] = [],
        category: SessionCategory? = nil,
        notes: String? = nil
    ) {
        self.sessionId = sessionId
        self.start = start
        self.duration = duration
        self.wordCount = wordCount
        self.summary = summary
        self.keyPoints = keyPoints
        self.entities = entities
        self.category = category
        self.notes = notes
    }
}

public enum MonthDigestBuilder {

    // MARK: - Build

    public static func build(
        monthStart: Date,
        sources: [DigestSource],
        isFinal: Bool,
        generator: (any TextGenerating)?
    ) async -> MonthDigest {
        let sorted = sources.sorted { $0.start < $1.start }
        let categories = categoryMap(sorted)
        let stats = computeStats(sorted)

        var extracted: [DigestItem] = entityItems(sorted)
        var usedModel = false

        if let generator {
            for batch in batches(sorted, tokenBudget: batchTokenBudget(for: generator)) {
                do {
                    let prompt = extractionPrompt(batch: batch, monthStart: monthStart)
                    let output = try await generator.generateText(
                        system: prompt.system,
                        user: prompt.user,
                        maxTokens: generator.outputTokenBudget
                    )
                    let items = parseExtraction(output, batch: batch).compactMap { grounded($0, in: batch) }
                    if items.isEmpty {
                        extracted += basicItems(batch)
                    } else {
                        extracted += items
                        // A recording no item points to keeps its own key points, so nothing is dropped
                        let covered = Set(items.flatMap { $0.sessionIds })
                        extracted += basicItems(batch.filter { !covered.contains($0.sessionId) })
                        usedModel = true
                    }
                } catch {
                    #if DEBUG
                    print("⚠️ [MonthDigestBuilder] Extraction failed for a batch of \(batch.count), using key points: \(error)")
                    #endif
                    extracted += basicItems(batch)
                }
            }
        } else {
            extracted += basicItems(sorted)
        }

        let items = merge(extracted, categories: categories)

        let modelForStories = usedModel ? generator : nil
        let story = await writeStory(items: items, stats: stats, monthStart: monthStart, focus: nil, generator: modelForStories)
        var headline = story.headline
        let narrative = story.narrative
        // The plain "14 recordings · topics" headline is only for months without a written story
        if headline == nil && narrative == nil {
            headline = basicHeadline(items: items, stats: stats)
        }

        // Work and Personal each get their own numbers, and their own story when the month has both
        var sections: [CategorySection] = []
        let splits: [(SessionCategory, ItemCategory, ItemFilter)] = [(.work, .work, .workOnly), (.personal, .personal, .personalOnly)]
        let present = splits.filter { entry in sorted.contains { $0.category == entry.0 } }
        for (sessionCategory, itemCategory, filter) in present {
            let sectionStats = computeStats(sorted.filter { $0.category == sessionCategory })
            var story: (headline: String?, narrative: String?) = (nil, nil)
            if present.count > 1 {
                let sectionItems = items.filter { $0.matches(filter) }
                story = await writeStory(items: sectionItems, stats: sectionStats, monthStart: monthStart,
                                         focus: sessionCategory.displayName.lowercased(), generator: modelForStories)
                if story.headline == nil && story.narrative == nil {
                    story.headline = basicHeadline(items: sectionItems, stats: sectionStats)
                }
            }
            sections.append(CategorySection(category: itemCategory, stats: sectionStats, headline: story.headline, narrative: story.narrative))
        }

        return MonthDigest(
            monthStart: monthStart,
            isFinal: isFinal,
            stats: stats,
            headline: headline,
            narrative: narrative,
            items: items,
            engineTier: usedModel ? (generator?.tier.rawValue ?? EngineTier.basic.rawValue) : EngineTier.basic.rawValue,
            sections: sections
        )
    }

    /// Headline and narrative from the given items, or nils without a model or on failure.
    /// `focus` ("work" or "personal") narrows the story to that side of my life.
    static func writeStory(items: [DigestItem], stats: DigestStats, monthStart: Date, focus: String?,
                           generator: (any TextGenerating)?) async -> (headline: String?, narrative: String?) {
        guard let generator, !items.isEmpty else { return (nil, nil) }
        do {
            let prompt = narrativePrompt(items: items, stats: stats, monthStart: monthStart, tokenBudget: generator.inputTokenBudget, focus: focus)
            let output = try await generator.generateText(system: prompt.system, user: prompt.user, maxTokens: 300)
            guard let json = ModelJSON.object(from: output) else { return (nil, nil) }
            var headline = (json["headline"] as? String)?.trimmedNonEmpty
            let narrative = (json["narrative"] as? String)?.trimmedNonEmpty
            // The card already shows the month name; a headline that only repeats it adds nothing
            let monthName = monthStart.formatted(.dateTime.month(.wide).year())
            if let current = headline, normalize(current) == normalize(monthName) {
                headline = nil
            }
            return (headline, narrative)
        } catch {
            #if DEBUG
            print("⚠️ [MonthDigestBuilder] Narrative failed: \(error)")
            #endif
            return (nil, nil)
        }
    }

    // MARK: - Stats

    static func computeStats(_ sources: [DigestSource]) -> DigestStats {
        let calendar = Calendar.current
        let days = Set(sources.map { calendar.startOfDay(for: $0.start) })
        return DigestStats(
            sessionCount: sources.count,
            totalMinutes: Int((sources.reduce(0) { $0 + $1.duration } / 60).rounded()),
            wordCount: sources.reduce(0) { $0 + $1.wordCount },
            activeDays: days.count,
            workCount: sources.filter { $0.category == .work }.count,
            personalCount: sources.filter { $0.category == .personal }.count
        )
    }

    static func categoryMap(_ sources: [DigestSource]) -> [UUID: SessionCategory] {
        var map: [UUID: SessionCategory] = [:]
        for source in sources {
            if let category = source.category { map[source.sessionId] = category }
        }
        return map
    }

    // MARK: - Batching

    /// Keep batches small enough that the extracted items fit in the answer, not just the prompt
    static func batchTokenBudget(for generator: any TextGenerating) -> Int {
        min(generator.inputTokenBudget, generator.outputTokenBudget * 2)
    }

    static func sourceLine(_ source: DigestSource, index: Int, maxCharacters: Int? = nil) -> String {
        let date = source.start.formatted(.dateTime.month(.abbreviated).day())
        let category = source.category.map { ", \($0.rawValue)" } ?? ""
        var summary = source.summary
        if let maxCharacters, summary.count > maxCharacters {
            summary = String(summary.prefix(maxCharacters))
        }
        var line = "[S\(index)] (\(date)\(category)) \(summary)"
        if let notes = source.notes?.trimmedNonEmpty {
            line += "\n  My notes: \(notes)"
        }
        return line
    }

    /// Split recordings into groups whose text fits the budget. A recording that is too long
    /// on its own goes in a batch by itself and is shortened in the prompt.
    static func batches(_ sources: [DigestSource], tokenBudget: Int) -> [[DigestSource]] {
        var result: [[DigestSource]] = []
        var current: [DigestSource] = []
        var currentTokens = 0
        for source in sources {
            let tokens = estimatedTokens(sourceLine(source, index: 99))
            if !current.isEmpty && currentTokens + tokens > tokenBudget {
                result.append(current)
                current = []
                currentTokens = 0
            }
            current.append(source)
            currentTokens += tokens
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Extraction prompt

    static let systemInstruction = """
    You turn summaries of my voice journal into a structured list of notes.
    Use only what is written. Do not invent anything.
    Write each item in first person, short (under 15 words) and specific.
    Return only valid JSON, with no markdown and no commentary.
    """

    static func extractionPrompt(batch: [DigestSource], monthStart: Date) -> (system: String, user: String) {
        let month = monthStart.formatted(.dateTime.month(.wide).year())
        let maxCharacters = batch.count == 1 ? 6_000 : nil
        let recordings = batch.enumerated()
            .map { sourceLine($1, index: $0 + 1, maxCharacters: maxCharacters) }
            .joined(separator: "\n")
        let user = """
        Below are summaries of my recordings from \(month). Each has an id like [S1].

        List every distinct item, using these kinds:
        - win: something I got done or that went well
        - challenge: a problem, setback, worry or loss
        - decision: something I decided
        - project: something I'm working on over time. Add "status": started, ongoing, done or dropped
        - idea: something I'm considering or might do
        - openLoop: a task or question I left unresolved
        - person: someone I mentioned by name (text is just the name)
        - place: a place I mentioned (text is just the place)
        - topic: a subject I talked about (1 to 3 words)

        Rules:
        - One item per distinct thing. Don't merge different tasks into one item.
        - "s" lists the number of every recording that mentions the item.
        - Leave out anything that isn't in the summaries.

        Return JSON in this shape, with your own items in place of the <...> placeholders:
        {"items":[{"k":"<kind>","t":"<item>","s":[<recording numbers>]},{"k":"project","t":"<item>","s":[<recording numbers>],"status":"<status>"}]}

        RECORDINGS:
        \(recordings)
        """
        return (systemInstruction, user)
    }

    // MARK: - Parsing

    /// Parse the model's items. If the answer was cut off, every complete item before the cut is kept.
    static func parseExtraction(_ output: String, batch: [DigestSource]) -> [DigestItem] {
        var objects: [[String: Any]] = []
        if let json = ModelJSON.object(from: output), let items = json["items"] as? [[String: Any]] {
            objects = items
        } else {
            objects = flatObjects(in: output)
        }
        return objects.compactMap { item(from: $0, batch: batch) }
    }

    /// Every `{...}` without nested braces, parsed on its own
    static func flatObjects(in text: String) -> [[String: Any]] {
        guard let regex = try? NSRegularExpression(pattern: "\\{[^{}]*\\}") else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text),
                  let data = String(text[r]).data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
    }

    static func item(from object: [String: Any], batch: [DigestSource]) -> DigestItem? {
        guard let kindString = (object["k"] ?? object["kind"]) as? String,
              let kind = kind(from: kindString),
              let text = ((object["t"] ?? object["text"]) as? String)?.trimmedNonEmpty else { return nil }

        let rawRefs = (object["s"] ?? object["sessions"]) as? [Any] ?? []
        var sessionIds: [UUID] = []
        for ref in rawRefs {
            guard let index = sessionIndex(from: ref), batch.indices.contains(index - 1) else { continue }
            let id = batch[index - 1].sessionId
            if !sessionIds.contains(id) { sessionIds.append(id) }
        }

        let status = (object["status"] as? String).flatMap { ProjectStatus(rawValue: $0.lowercased()) }
        return DigestItem(
            kind: kind,
            text: text,
            mentions: max(sessionIds.count, 1),
            sessionIds: sessionIds,
            status: kind == .project ? (status ?? .ongoing) : nil
        )
    }

    /// Small models sometimes copy the prompt's example, invent items, or cite recordings that
    /// have nothing to do with an item. Keep an item only if its words appear in what it cites,
    /// and narrow its recordings to the ones that actually mention it. Returns nil to drop it.
    /// Names, places and topics must appear whole; other items need at least half their key words.
    static func grounded(_ item: DigestItem, in batch: [DigestSource]) -> DigestItem? {
        let cited = batch.filter { item.sessionIds.contains($0.sessionId) }
        guard !cited.isEmpty else { return nil }

        let text: (DigestSource) -> String = {
            normalize([$0.summary, $0.notes ?? "", $0.keyPoints.joined(separator: " ")].joined(separator: " "))
        }
        let keyWords = normalize(item.text).split(separator: " ").map(String.init).filter { $0.count >= 4 }
        func found(in sourceText: String) -> Int {
            let words = Set(sourceText.split(separator: " ").map(String.init))
            return keyWords.filter { word in words.contains(word) || words.contains { $0.hasPrefix(String(word.prefix(5))) } }.count
        }

        var supporting: [DigestSource]
        switch item.kind {
        case .person, .place, .topic:
            let name = normalize(item.text)
            guard !name.isEmpty else { return nil }
            supporting = cited.filter { " \(text($0)) ".contains(" \(name) ") }
        default:
            guard !keyWords.isEmpty else { return item }
            let needed = Double(keyWords.count) * 0.5
            supporting = cited.filter { Double(found(in: text($0))) >= needed }
            if supporting.isEmpty {
                // A merged item can draw its words from several recordings together
                let all = cited.map(text).joined(separator: " ")
                guard Double(found(in: all)) >= needed else { return nil }
                supporting = cited.filter { found(in: text($0)) > 0 }
            }
        }
        guard !supporting.isEmpty else { return nil }
        let ids = supporting.map(\.sessionId)
        return DigestItem(kind: item.kind, text: item.text, category: item.category, mentions: ids.count, sessionIds: ids, status: item.status)
    }

    static func kind(from string: String) -> DigestItemKind? {
        switch string.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "") {
        case "win", "wins": return .win
        case "challenge", "challenges", "loss": return .challenge
        case "decision", "decisions": return .decision
        case "project", "projects": return .project
        case "idea", "ideas": return .idea
        case "openloop", "openloops", "todo": return .openLoop
        case "person", "people": return .person
        case "place", "places": return .place
        case "topic", "topics": return .topic
        case "note", "notes": return .note
        default: return nil
        }
    }

    /// Accepts 3, "3" or "S3"
    static func sessionIndex(from ref: Any) -> Int? {
        if let number = ref as? Int { return number }
        if let number = ref as? Double { return Int(number) }
        if let string = ref as? String {
            return Int(string.trimmingCharacters(in: CharacterSet(charactersIn: "Ss[] ")))
        }
        return nil
    }

    // MARK: - Items without a model

    /// Key points become notes (short ones become topics). A recording without key points
    /// keeps its summary as a note, so every recording is represented.
    static func basicItems(_ sources: [DigestSource]) -> [DigestItem] {
        var items: [DigestItem] = []
        for source in sources {
            let points = source.keyPoints.compactMap { $0.trimmedNonEmpty }
            if points.isEmpty {
                items.append(DigestItem(kind: .note, text: String(source.summary.prefix(200)), sessionIds: [source.sessionId]))
                continue
            }
            for point in points {
                let kind: DigestItemKind = point.split(separator: " ").count <= 3 ? .topic : .note
                items.append(DigestItem(kind: kind, text: point, sessionIds: [source.sessionId]))
            }
        }
        return items
    }

    /// People and places already found on device when each recording was summarized
    static func entityItems(_ sources: [DigestSource]) -> [DigestItem] {
        var items: [DigestItem] = []
        for source in sources {
            for entity in source.entities where entity.confidence >= 0.5 {
                switch entity.type {
                case .person:
                    items.append(DigestItem(kind: .person, text: entity.name, sessionIds: [source.sessionId]))
                case .location:
                    items.append(DigestItem(kind: .place, text: entity.name, sessionIds: [source.sessionId]))
                default:
                    break
                }
            }
        }
        return items
    }

    // MARK: - Merging

    /// Combine items that say the same thing. Mentions become the number of distinct
    /// recordings, sources are unioned, and a project keeps its latest status.
    /// Categories come from the recordings when known.
    public static func merge(_ items: [DigestItem], categories: [UUID: SessionCategory] = [:]) -> [DigestItem] {
        var order: [String] = []
        var groups: [String: [DigestItem]] = [:]
        for item in items {
            let key = "\(item.kind.rawValue)|\(normalize(item.text))"
            guard !normalize(item.text).isEmpty else { continue }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }

        let merged: [DigestItem] = order.compactMap { key in
            guard let group = groups[key], let first = group.first else { return nil }
            var sessionIds: [UUID] = []
            var unlinkedMentions = 0
            for item in group {
                if item.sessionIds.isEmpty { unlinkedMentions += item.mentions }
                for id in item.sessionIds where !sessionIds.contains(id) { sessionIds.append(id) }
            }
            let mentions = max(sessionIds.count + unlinkedMentions, 1)
            let category = combinedCategory(sessionIds: sessionIds, categories: categories, itemCategories: group.compactMap { $0.category })
            let status = group.compactMap { $0.status }.last
            return DigestItem(kind: first.kind, text: first.text, category: category, mentions: mentions, sessionIds: sessionIds, status: status)
        }

        let kindOrder = DigestItemKind.allCases
        return merged.enumerated().sorted { lhs, rhs in
            let l = kindOrder.firstIndex(of: lhs.element.kind) ?? 0
            let r = kindOrder.firstIndex(of: rhs.element.kind) ?? 0
            if l != r { return l < r }
            if lhs.element.mentions != rhs.element.mentions { return lhs.element.mentions > rhs.element.mentions }
            return lhs.offset < rhs.offset
        }.map { $0.element }
    }

    static func combinedCategory(sessionIds: [UUID], categories: [UUID: SessionCategory], itemCategories: [ItemCategory]) -> ItemCategory? {
        let fromSessions = Set(sessionIds.compactMap { categories[$0] })
        if !fromSessions.isEmpty {
            if fromSessions.count > 1 { return .both }
            return fromSessions.first == .work ? .work : .personal
        }
        let fromItems = Set(itemCategories)
        if fromItems.isEmpty { return nil }
        return fromItems.count == 1 ? fromItems.first : .both
    }

    /// Lowercase, no accents, no punctuation, single spaces, no leading article
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        var words = String(cleaned).split(separator: " ").map(String.init)
        if let first = words.first, ["the", "a", "an", "my"].contains(first), words.count > 1 {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    // MARK: - Headline and narrative

    static func narrativePrompt(items: [DigestItem], stats: DigestStats, monthStart: Date, tokenBudget: Int, focus: String? = nil) -> (system: String, user: String) {
        let month = monthStart.formatted(.dateTime.month(.wide).year())
        var lines: [String] = []
        var used = 0
        // Most-mentioned items of each kind first, so a small budget still covers every kind
        for rank in 0..<20 {
            for kind in DigestItemKind.allCases {
                let ofKind = items.filter { $0.kind == kind }
                guard rank < ofKind.count else { continue }
                let line = "- \(kind.displayName): \(ofKind[rank].text)"
                let tokens = estimatedTokens(line)
                guard used + tokens <= tokenBudget else { continue }
                lines.append(line)
                used += tokens
            }
        }
        let user = """
        These are my \(focus.map { "\($0) " } ?? "")notes from \(month): \(stats.sessionCount) recordings over \(stats.activeDays) days.

        \(lines.joined(separator: "\n"))

        Write a headline for my \(focus.map { "\($0) " } ?? "")month (under 10 words) and a narrative of 2 to 4 sentences, in first person, using only these notes.
        Return: {"headline":"...","narrative":"..."}
        """
        return (systemInstruction, user)
    }

    static func basicHeadline(items: [DigestItem], stats: DigestStats) -> String {
        let recordings = stats.sessionCount == 1 ? "1 recording" : "\(stats.sessionCount) recordings"
        let topics = items.filter { $0.kind == .topic }.prefix(2).map { $0.text }
        guard !topics.isEmpty else { return recordings }
        return "\(recordings) · \(topics.joined(separator: ", "))"
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
