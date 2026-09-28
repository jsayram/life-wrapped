// =============================================================================
// Storage — Data Exporter
// =============================================================================
// Export user data to various formats (JSON, Markdown, CSV)
// =============================================================================

import Foundation
import SharedModels
import PDFKit

#if canImport(UIKit)
import UIKit
#endif

public actor DataExporter {
    private let databaseManager: DatabaseManager
    
    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    // MARK: - JSON Export
    
    /// Export all data to JSON format
    public func exportToJSON(year: Int? = nil) async throws -> Data {
        let allChunks = try await databaseManager.fetchAllAudioChunks()
        let allSummaries = try await databaseManager.fetchAllSummaries()
        
        // Filter by year if specified
        let chunks: [AudioChunk]
        let summaries: [Summary]
        
        if let year = year {
            let calendar = Calendar.current
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let endOfYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
            
            chunks = allChunks.filter { $0.createdAt >= startOfYear && $0.createdAt < endOfYear }
            summaries = allSummaries.filter { $0.periodStart >= startOfYear && $0.periodStart < endOfYear }
        } else {
            chunks = allChunks
            summaries = allSummaries
        }
        
        // Fetch all transcript segments for filtered chunks
        var allSegments: [TranscriptSegment] = []
        for chunk in chunks {
            let segments = try await databaseManager.fetchTranscriptSegments(audioChunkID: chunk.id)
            allSegments.append(contentsOf: segments)
        }
        
        // Earlier versions travel with the summaries they belong to
        let keys = Set(summaries.map(\.versionKey))
        let versions = try await databaseManager.fetchAllSummaryVersions().filter { keys.contains($0.summaryKey) }

        let export = JSONExport(
            exportDate: Date(),
            version: "1.1",
            audioChunks: chunks.map { JSONAudioChunk(from: $0) },
            transcriptSegments: allSegments.map { JSONTranscriptSegment(from: $0) },
            summaries: summaries.map { JSONSummary(from: $0) },
            summaryVersions: versions.map { JSONSummaryVersion(from: $0) }
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        return try encoder.encode(export)
    }
    
    // MARK: - Markdown Export
    
    /// Export to Markdown: each year's wrap, then month by month the month's digest (both
    /// journals) and its recordings, newest first. Deleted recordings are left out.
    public func exportToMarkdown(year: Int? = nil) async throws -> String {
        let calendar = Calendar.current
        let range: (start: Date, end: Date) = {
            guard let year,
                  let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
                return (.distantPast, .distantFuture)
            }
            return (start, end)
        }()

        let sessionSummaries = try await databaseManager.fetchSummaries(periodType: .session, from: range.start, to: range.end)
            .filter { $0.sessionId != nil }
        let ids = sessionSummaries.compactMap { $0.sessionId }
        let existing = try await databaseManager.existingSessionIds(among: ids)
        let recordings = sessionSummaries.filter { $0.sessionId.map(existing.contains) ?? false }
        let metadata = try await databaseManager.fetchSessionMetadataBatch(sessionIds: ids)

        var markdown = "# Life Wrapped Export\n\n"
        if let year {
            markdown += "**Year:** \(year)\n\n"
        }
        markdown += "**Export Date:** \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))\n\n"
        markdown += "---\n\n"

        let monthStart: (Date) -> Date = { calendar.date(from: calendar.dateComponents([.year, .month], from: $0)) ?? $0 }
        let byMonth = Dictionary(grouping: recordings) { monthStart($0.periodStart) }
        let byYear = Dictionary(grouping: byMonth.keys) { calendar.component(.year, from: $0) }

        for wrapYear in byYear.keys.sorted(by: >) {
            if let yearStart = calendar.date(from: DateComponents(year: wrapYear, month: 1, day: 1)),
               let row = try? await databaseManager.fetchPeriodSummary(type: .yearWrap, date: yearStart),
               let wrap = YearWrapData.parse(row.text) {
                markdown += "## Year Wrap \(wrapYear)\n\n\(wrap.storyText)\n\n---\n\n"
            }

            for month in (byYear[wrapYear] ?? []).sorted(by: >) {
                markdown += "## \(month.formatted(.dateTime.month(.wide).year()))\n\n"
                if let digest = await monthDigest(for: month) {
                    // The digest's text starts with the month name, already the heading
                    let body = digest.plainText(filter: .all).components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
                    if !body.isEmpty { markdown += "\(body)\n\n" }
                }
                markdown += "### Recordings\n\n"
                for summary in (byMonth[month] ?? []).sorted(by: { $0.periodStart > $1.periodStart }) {
                    let meta = summary.sessionId.flatMap { metadata[$0] }
                    let journal = (meta?.category ?? .personal).displayName
                    var heading = "\(summary.periodStart.formatted(date: .abbreviated, time: .shortened)) · \(journal)"
                    if let title = meta?.title, !title.isEmpty { heading += " · \(title)" }
                    markdown += "**\(heading)**\n\n\(summary.text)\n\n"
                }
                markdown += "---\n\n"
            }
        }
        return markdown
    }

    /// A month's digest across both journals, as the app shows it
    private func monthDigest(for month: Date) async -> MonthDigest? {
        var journals: [SessionCategory: MonthDigest] = [:]
        for journal in SessionCategory.allCases {
            if let row = try? await databaseManager.fetchPeriodSummary(type: .monthDigest, date: month, category: journal),
               let digest = MonthDigest.fromJSON(row.text) {
                journals[journal] = digest
            }
        }
        let legacy = (try? await databaseManager.fetchPeriodSummary(type: .monthDigest, date: month)).flatMap { MonthDigest.fromJSON($0.text) }
        return JournalDigests.combined(stored: journals, legacy: legacy)?.digest
    }
    
    #if canImport(UIKit)
    // MARK: - PDF Export
    
    /// Export summaries to PDF format (summaries only, not full transcripts)
    public func exportToPDF(year: Int? = nil, redactPeople: Bool = false, redactPlaces: Bool = false, filter: ItemFilter = .all) async throws -> Data {
        let summaries = try await databaseManager.fetchAllSummaries()
        
        // Filter by year if specified
        let filteredSummaries: [Summary]
        if let year = year {
            let calendar = Calendar.current
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let endOfYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
            
            filteredSummaries = summaries.filter {
                $0.periodStart >= startOfYear && $0.periodStart < endOfYear
            }
        } else {
            filteredSummaries = summaries
        }
        
        // Check if this is a Year Wrap export
        // Work and Personal each have their own journal wrap; wraps from before journals were
        // separate types, and older years may only have the combined one
        let journal: SessionCategory? = filter == .workOnly ? .work : (filter == .personalOnly ? .personal : nil)
        let combined = filteredSummaries.first(where: { $0.periodType == .yearWrap && $0.category == nil })
        let yearWrap = journal.flatMap { journal in filteredSummaries.first(where: { $0.periodType == .yearWrap && $0.category == journal }) }
            ?? (filter == .all ? nil : filteredSummaries.first(where: { $0.periodType == filter.yearWrapType }))
            ?? combined
        
        if let yearWrap = yearWrap, let year = year {
            // Render enhanced Year Wrap PDF
            return try await renderYearWrapPDF(yearWrap: yearWrap, year: year, redactPeople: redactPeople, redactPlaces: redactPlaces, filter: filter)
        } else {
            // Render standard summary PDF
            return renderStandardPDF(summaries: filteredSummaries, year: year)
        }
    }
    
    // MARK: - Standard PDF Rendering

    private func renderStandardPDF(summaries: [Summary], year: Int?) -> Data {
        let title = year != nil ? "Life Wrapped Export \(year!)" : "Life Wrapped Export All"
        let writer = GraphitePDFWriter(title: title)

        return writer.render { page in
            page.beginPage()

            // Header
            page.drawOverline("LIFE WRAPPED")
            page.drawSerif(year != nil ? "Summaries \(year!)" : "All summaries", size: 34)
            page.y += 6
            let exported = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)
            page.drawBody("Exported \(exported). This PDF contains summaries only, not full transcripts.", size: 11, color: GraphitePDFWriter.ink2)
            page.y += 24

            if summaries.isEmpty {
                page.drawBody("No summaries yet.", size: 12, color: GraphitePDFWriter.ink2)
                return
            }

            // Group summaries by period type
            // Largest periods first: Year Wraps, then years down to single sessions
            let order: [PeriodType] = [.yearWrap, .yearWrapWork, .yearWrapPersonal, .year, .quarter, .month, .week, .day, .hour, .session]
            // Month digests are structured JSON used to build Year Wrap, not readable text
            let groupedSummaries = Dictionary(grouping: summaries.filter { $0.periodType != .monthDigest }) { $0.periodType }
            let sortedGroups = groupedSummaries.sorted {
                (order.firstIndex(of: $0.key) ?? order.count) < (order.firstIndex(of: $1.key) ?? order.count)
            }

            for (periodType, group) in sortedGroups {
                page.ensureSpace(80)
                page.drawSectionHeader("\(periodType.displayName) summaries", icon: nil, trailing: group.count == 1 ? "1 summary" : "\(group.count) summaries")

                for summary in group.sorted(by: { $0.periodStart > $1.periodStart }) {
                    let heading = formatPeriod(summary.periodType, start: summary.periodStart, end: summary.periodEnd)
                    // Year Wraps are stored as JSON; show their written summary instead
                    let isWrap = [.yearWrap, .yearWrapWork, .yearWrapPersonal].contains(summary.periodType)
                    let body = isWrap ? (parseYearWrapJSON(from: summary.text)?.yearSummary ?? summary.text) : summary.text
                    page.drawCard(heading: heading, body: body)
                }
                page.y += 12
            }
        }
    }

    // MARK: - Year Wrap PDF Rendering

    private func renderYearWrapPDF(yearWrap: Summary, year: Int, redactPeople: Bool, redactPlaces: Bool, filter: ItemFilter) async throws -> Data {
        guard let parsed = parseYearWrapJSON(from: yearWrap.text) else {
            // Fallback to standard PDF if parsing fails
            return renderStandardPDF(summaries: [yearWrap], year: year)
        }
        let parsedData = parsed.redacted(people: redactPeople, places: redactPlaces)
        // A journal's own wrap has stats for just that journal, so it shows them like All
        let isOwnWrap = yearWrap.category != nil || (filter != .all && yearWrap.periodType == filter.yearWrapType)
        let statsFilter: ItemFilter = isOwnWrap ? .all : filter
        let tiles = try await yearStatTiles(stats: parsedData.stats, year: year, filter: statsFilter)
        let writer = GraphitePDFWriter(title: "Year Wrap \(year)")

        return writer.render { page in
            // Page 1: black cover, like the Year Wrapped card in the app
            page.beginCoverPage()
            // All keeps each journal's own story; the plain-text form labels them
            let coverSummary = parsedData.journals.map { journals in
                journals.map { "\($0.category.displayName): \($0.title). \($0.summary)" }.joined(separator: "\n\n")
            } ?? parsedData.yearSummary
            page.drawCover(year: year, title: parsedData.yearTitle, summary: coverSummary, filterLabel: filter == .workOnly ? "Work" : (filter == .personalOnly ? "Personal" : nil))

            // Page 2: numbers, then the insight sections flowing across pages
            page.beginPage()
            page.drawOverline("YEAR WRAPPED \(year)")
            page.drawSerif("Your year in numbers", size: 28)
            page.y += 16
            page.drawStatTiles(tiles)
            page.y += 28

            let sections: [(String, String, [ClassifiedItem])] = [
                ("Major arcs", "book", parsedData.majorArcs),
                ("Biggest wins", "trophy", parsedData.biggestWins),
                ("Biggest losses", "heart.slash", parsedData.biggestLosses),
                ("Biggest challenges", "bolt", parsedData.biggestChallenges),
                ("Finished projects", "checkmark.circle", parsedData.finishedProjects),
                ("Unfinished projects", "pause.circle", parsedData.unfinishedProjects),
                ("Top worked-on topics", "hammer", parsedData.topWorkedOnTopics),
                ("Top talked-about things", "bubble.left", parsedData.topTalkedAboutThings),
                ("Valuable actions taken", "diamond", parsedData.valuableActionsTaken),
                ("Opportunities missed", "scope", parsedData.opportunitiesMissed)
            ]

            for (title, icon, items) in sections {
                let filtered = filterItems(items, by: filter)
                guard !filtered.isEmpty else { continue }
                let lines = filtered.map { item -> (text: String, detail: String?) in
                    (item.text, filter == .all ? categoryLabel(item.category) : nil)
                }
                page.drawListSection(title: title, icon: icon, items: lines)
            }

            // People & Places
            // Names are already redacted in parsedData
            if !parsedData.peopleMentioned.isEmpty {
                let lines = parsedData.peopleMentioned.map { person -> (text: String, detail: String?) in
                    (person.name, person.relationship)
                }
                page.drawListSection(title: "People mentioned", icon: "person.2", items: lines)
            }
            if !parsedData.placesVisited.isEmpty {
                let lines = parsedData.placesVisited.map { place -> (text: String, detail: String?) in
                    (place.name, place.frequency)
                }
                page.drawListSection(title: "Places visited", icon: "mappin.and.ellipse", items: lines)
            }

            // Redaction note
            if redactPeople || redactPlaces {
                let details: String
                if redactPeople && redactPlaces {
                    details = "The most-mentioned people and places are hidden throughout this export. Other names may still appear."
                } else if redactPeople {
                    details = "The most-mentioned people are hidden throughout this export. Other names may still appear."
                } else {
                    details = "The most-mentioned places are hidden throughout this export. Other place names may still appear."
                }
                page.ensureSpace(40)
                page.drawBody("Privacy note: \(details)", size: 10, color: GraphitePDFWriter.ink2)
            }
        }
    }

    private func filterItems(_ items: [ClassifiedItem], by filter: ItemFilter) -> [ClassifiedItem] {
        switch filter {
        case .all:
            return items
        case .workOnly:
            return items.filter { $0.category == .work || $0.category == .both }
        case .personalOnly:
            return items.filter { $0.category == .personal || $0.category == .both }
        }
    }

    private func categoryLabel(_ category: ItemCategory) -> String {
        switch category {
        case .work: return "Work"
        case .personal: return "Personal"
        case .both: return "Work and personal"
        }
    }

    // MARK: - Helpers
    
    func parseYearWrapJSON(from text: String) -> YearWrapData? {
        YearWrapData.parse(text)
    }
    
    /// The numbers row. Wraps built from month digests carry their own stats, which also
    /// give work/personal counts; older wraps count every recording in the year.
    private func yearStatTiles(stats: YearWrapStats?, year: Int, filter: ItemFilter) async throws -> [(icon: String, value: String, label: String)] {
        guard let stats else {
            let counted = try await fetchYearStats(year: year)
            return [
                ("mic", "\(counted.sessions)", "entries"),
                ("clock", String(format: "%.1fh", counted.duration / 3600), "recorded"),
                ("text.alignleft", counted.words.formatted(), "words")
            ]
        }
        switch filter {
        case .all:
            return [
                ("mic", "\(stats.sessionCount)", "entries"),
                ("clock", String(format: "%.1fh", Double(stats.totalMinutes) / 60), "recorded"),
                ("text.alignleft", stats.wordCount.formatted(), "words")
            ]
        case .workOnly, .personalOnly:
            let count = filter == .workOnly ? stats.workCount : stats.personalCount
            let share = stats.sessionCount > 0 ? Int((Double(count) / Double(stats.sessionCount) * 100).rounded()) : 0
            return [
                ("mic", "\(count)", filter == .workOnly ? "work entries" : "personal entries"),
                ("chart.pie", "\(share)%", "of all entries")
            ]
        }
    }
    
    private func fetchYearStats(year: Int) async throws -> (sessions: Int, duration: TimeInterval, words: Int) {
        let calendar = Calendar.current
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let endOfYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        
        let chunks = try await databaseManager.fetchAllAudioChunks()
        let yearChunks = chunks.filter { $0.createdAt >= startOfYear && $0.createdAt < endOfYear }
        
        var totalDuration: TimeInterval = 0
        var totalWords: Int = 0
        var sessionIds: Set<UUID> = []
        
        for chunk in yearChunks {
            sessionIds.insert(chunk.sessionId)
            totalDuration += chunk.duration
            
            let segments = try await databaseManager.fetchTranscriptSegments(audioChunkID: chunk.id)
            for segment in segments {
                totalWords += segment.text.split(separator: " ").count
            }
        }
        
        return (sessionIds.count, totalDuration, totalWords)
    }
    #endif // canImport(UIKit)
    
    // MARK: - Helper Methods
    
    private func formatPeriod(_ type: PeriodType, start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        switch type {
        case .session:
            formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
            return "Session on \(formatter.string(from: start))"
        case .hour:
            formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
            return formatter.string(from: start)
        case .day:
            formatter.dateFormat = "EEEE, MMMM d, yyyy"
            return formatter.string(from: start)
        case .week:
            formatter.dateFormat = "MMM d"
            return "Week of \(formatter.string(from: start))"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: start)
        case .quarter:
            let quarter = PeriodType.quarterNumber(from: start)
            formatter.dateFormat = "yyyy"
            return "Q\(quarter) \(formatter.string(from: start))"
        case .year:
            formatter.dateFormat = "yyyy"
            return "Year \(formatter.string(from: start))"
        case .yearWrap:
            formatter.dateFormat = "yyyy"
            return "Year Wrap \(formatter.string(from: start))"
        case .yearWrapWork:
            formatter.dateFormat = "yyyy"
            return "Work Year Wrap \(formatter.string(from: start))"
        case .yearWrapPersonal:
            formatter.dateFormat = "yyyy"
            return "Personal Year Wrap \(formatter.string(from: start))"
        case .monthDigest:
            formatter.dateFormat = "MMMM yyyy"
            return "\(formatter.string(from: start)) digest"
        }
    }

    
    // MARK: - Storage Info
    
    /// Get storage usage statistics
    public func getStorageInfo(localModelSize: Int64? = nil) async throws -> StorageInfo {
        let chunks = try await databaseManager.fetchAllAudioChunks()
        let summaries = try await databaseManager.fetchAllSummaries()
        
        var totalAudioSize: Int64 = 0
        for chunk in chunks {
            if FileManager.default.fileExists(atPath: chunk.fileURL.path) {
                let attrs = try FileManager.default.attributesOfItem(atPath: chunk.fileURL.path)
                totalAudioSize += attrs[.size] as? Int64 ?? 0
            }
        }
        
        return StorageInfo(
            audioChunkCount: chunks.count,
            summaryCount: summaries.count,
            totalAudioSize: totalAudioSize,
            databaseSize: try await getDatabaseSize(),
            localModelSize: localModelSize
        )
    }
    
    private func getDatabaseSize() async throws -> Int64 {
        // Get database path from DatabaseManager
        let dbPath = await databaseManager.getDatabasePath()
        
        if FileManager.default.fileExists(atPath: dbPath) {
            let attrs = try FileManager.default.attributesOfItem(atPath: dbPath)
            if let size = attrs[FileAttributeKey.size] as? Int64 {
                return size
            }
        }
        
        return 0
    }
}

// MARK: - Export Models

public struct JSONExport: Codable {
    let exportDate: Date
    let version: String
    let audioChunks: [JSONAudioChunk]
    let transcriptSegments: [JSONTranscriptSegment]?
    let summaries: [JSONSummary]
    /// Earlier versions of the summaries. Missing in exports made before 1.3.
    let summaryVersions: [JSONSummaryVersion]?

    init(exportDate: Date, version: String, audioChunks: [JSONAudioChunk], transcriptSegments: [JSONTranscriptSegment]?,
         summaries: [JSONSummary], summaryVersions: [JSONSummaryVersion]? = nil) {
        self.exportDate = exportDate
        self.version = version
        self.audioChunks = audioChunks
        self.transcriptSegments = transcriptSegments
        self.summaries = summaries
        self.summaryVersions = summaryVersions
    }
}

public struct JSONSummaryVersion: Codable {
    let id: UUID
    let summaryKey: String
    let text: String
    let createdAt: Date
    let replacedAt: Date
    let engineTier: String?
    let topicsJSON: String?
    let entitiesJSON: String?
    let sourceIds: String?
    let inputHash: String?

    init(from version: SummaryVersion) {
        self.id = version.id
        self.summaryKey = version.summaryKey
        self.text = version.text
        self.createdAt = version.createdAt
        self.replacedAt = version.replacedAt
        self.engineTier = version.engineTier
        self.topicsJSON = version.topicsJSON
        self.entitiesJSON = version.entitiesJSON
        self.sourceIds = version.sourceIds
        self.inputHash = version.inputHash
    }

    var model: SummaryVersion {
        SummaryVersion(id: id, summaryKey: summaryKey, text: text, createdAt: createdAt, replacedAt: replacedAt,
                       engineTier: engineTier, topicsJSON: topicsJSON, entitiesJSON: entitiesJSON,
                       sourceIds: sourceIds, inputHash: inputHash)
    }
}

public struct JSONAudioChunk: Codable {
    let id: UUID
    let fileURL: URL
    let startTime: Date
    let endTime: Date
    let format: String
    let sampleRate: Int
    let createdAt: Date
    let sessionId: UUID
    let chunkIndex: Int
    
    init(from chunk: AudioChunk) {
        self.id = chunk.id
        self.fileURL = chunk.fileURL
        self.startTime = chunk.startTime
        self.endTime = chunk.endTime
        self.format = chunk.format.rawValue
        self.sampleRate = chunk.sampleRate
        self.createdAt = chunk.createdAt
        self.sessionId = chunk.sessionId
        self.chunkIndex = chunk.chunkIndex
    }
}

public struct JSONTranscriptSegment: Codable {
    let id: UUID
    let audioChunkID: UUID
    let startTime: Double
    let endTime: Double
    let text: String
    let confidence: Float
    let languageCode: String
    let createdAt: Date
    let sentimentScore: Double?
    
    init(from segment: TranscriptSegment) {
        self.id = segment.id
        self.audioChunkID = segment.audioChunkID
        self.startTime = segment.startTime
        self.endTime = segment.endTime
        self.text = segment.text
        self.confidence = segment.confidence
        self.languageCode = segment.languageCode
        self.createdAt = segment.createdAt
        self.sentimentScore = segment.sentimentScore
    }
}

public struct JSONSummary: Codable {
    let id: UUID
    let periodType: String
    let periodStart: Date
    let periodEnd: Date
    let text: String
    let createdAt: Date
    let sessionId: UUID?
    /// The journal a period summary belongs to. Missing in exports made before journals.
    let category: String?
    /// Which engine wrote it and what it was built from. Missing in exports made before 1.3;
    /// without them a restored summary ranks as Key Sentences and its months rebuild once.
    let engineTier: String?
    let topicsJSON: String?
    let entitiesJSON: String?
    let sourceIds: String?
    let inputHash: String?
    
    init(from summary: Summary) {
        self.id = summary.id
        self.periodType = summary.periodType.rawValue
        self.periodStart = summary.periodStart
        self.periodEnd = summary.periodEnd
        self.text = summary.text
        self.createdAt = summary.createdAt
        self.sessionId = summary.sessionId
        self.category = summary.category?.rawValue
        self.engineTier = summary.engineTier
        self.topicsJSON = summary.topicsJSON
        self.entitiesJSON = summary.entitiesJSON
        self.sourceIds = summary.sourceIds
        self.inputHash = summary.inputHash
    }
}

public struct StorageInfo: Sendable {
    public let audioChunkCount: Int
    public let summaryCount: Int
    public let totalAudioSize: Int64
    public let databaseSize: Int64
    public let localModelSize: Int64?
    
    public var totalSize: Int64 {
        totalAudioSize + databaseSize + (localModelSize ?? 0)
    }
    
    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    public var formattedAudioSize: String {
        ByteCountFormatter.string(fromByteCount: totalAudioSize, countStyle: .file)
    }
    
    public var formattedDatabaseSize: String {
        ByteCountFormatter.string(fromByteCount: databaseSize, countStyle: .file)
    }
    
    public var formattedLocalModelSize: String {
        guard let localModelSize = localModelSize else {
            return "Not Downloaded"
        }
        return ByteCountFormatter.string(fromByteCount: localModelSize, countStyle: .file)
    }
}

// MARK: - Graphite PDF Writer

#if canImport(UIKit)
/// Draws PDFs in the app's graphite design language: warm paper background,
/// ink text, serif headings, outline SF Symbols, white cards with hairline borders.
private final class GraphitePDFWriter {
    // Palette (matches AppTheme light mode)
    static let paper = UIColor(red: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF5 / 255, alpha: 1)
    static let card = UIColor.white
    static let ink = UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
    static let ink2 = UIColor(red: 0x55 / 255, green: 0x55 / 255, blue: 0x4F / 255, alpha: 1)
    static let hairline = UIColor(red: 0xE4 / 255, green: 0xE4 / 255, blue: 0xE0 / 255, alpha: 1)
    static let onInk = UIColor(red: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF5 / 255, alpha: 1)

    let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
    let margin: CGFloat = 54
    let footerHeight: CGFloat = 40
    private let title: String

    private var context: UIGraphicsPDFRendererContext?
    private var pageNumber = 0
    var y: CGFloat = 0

    var contentWidth: CGFloat { pageRect.width - margin * 2 }
    var bottom: CGFloat { pageRect.height - margin - footerHeight }

    init(title: String) {
        self.title = title
    }

    func render(_ draw: (GraphitePDFWriter) -> Void) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Life Wrapped",
            kCGPDFContextTitle as String: title
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { ctx in
            self.context = ctx
            draw(self)
            self.context = nil
        }
    }

    // MARK: Pages

    func beginPage() {
        context?.beginPage()
        pageNumber += 1
        Self.paper.setFill()
        UIRectFill(pageRect)
        drawFooter()
        y = margin
    }

    func beginCoverPage() {
        context?.beginPage()
        pageNumber += 1
        Self.ink.setFill()
        UIRectFill(pageRect)
        y = margin
    }

    func ensureSpace(_ height: CGFloat) {
        if y + height > bottom { beginPage() }
    }

    private func drawFooter() {
        let lineY = pageRect.height - margin - 18
        Self.hairline.setFill()
        UIRectFill(CGRect(x: margin, y: lineY, width: contentWidth, height: 0.75))
        let attrs = Self.attributes(font: .systemFont(ofSize: 9), color: Self.ink2)
        ("Life Wrapped" as NSString).draw(at: CGPoint(x: margin, y: lineY + 8), withAttributes: attrs)
        let number = "\(pageNumber)" as NSString
        let size = number.size(withAttributes: attrs)
        number.draw(at: CGPoint(x: pageRect.width - margin - size.width, y: lineY + 8), withAttributes: attrs)
    }

    // MARK: Fonts

    static func serif(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func attributes(font: UIFont, color: UIColor, lineSpacing: CGFloat = 0, kern: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        if kern != 0 { attrs[.kern] = kern }
        return attrs
    }

    // MARK: Text

    private func height(of text: String, attrs: [NSAttributedString.Key: Any], width: CGFloat) -> CGFloat {
        ceil((text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        ).height)
    }

    private func draw(_ text: String, attrs: [NSAttributedString.Key: Any], x: CGFloat, width: CGFloat) {
        let h = height(of: text, attrs: attrs, width: width)
        (text as NSString).draw(
            with: CGRect(x: x, y: y, width: width, height: h),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        y += h
    }

    func drawOverline(_ text: String, color: UIColor = ink2) {
        draw(text, attrs: Self.attributes(font: .systemFont(ofSize: 10, weight: .medium), color: color, kern: 1.2), x: margin, width: contentWidth)
        y += 6
    }

    func drawSerif(_ text: String, size: CGFloat, color: UIColor = ink) {
        draw(text, attrs: Self.attributes(font: Self.serif(size), color: color), x: margin, width: contentWidth)
    }

    /// Body text that flows across pages when it is taller than the space left.
    func drawBody(_ text: String, size: CGFloat, color: UIColor = ink, x: CGFloat? = nil, width: CGFloat? = nil) {
        let attrs = Self.attributes(font: .systemFont(ofSize: size), color: color, lineSpacing: size * 0.35)
        drawFlowing(NSAttributedString(string: text, attributes: attrs), x: x ?? margin, width: width ?? contentWidth)
    }

    private func drawFlowing(_ text: NSAttributedString, x: CGFloat, width: CGFloat) {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var drawnGlyphs = 0

        while drawnGlyphs < layout.numberOfGlyphs || layout.textContainers.isEmpty {
            let available = bottom - y
            if available < 24 { beginPage(); continue }

            let container = NSTextContainer(size: CGSize(width: width, height: available))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            let range = layout.glyphRange(for: container)
            if range.length == 0 {
                if layout.numberOfGlyphs == 0 { break }
                beginPage()
                continue
            }
            layout.drawGlyphs(forGlyphRange: range, at: CGPoint(x: x, y: y))
            y += ceil(layout.usedRect(for: container).height)
            drawnGlyphs = NSMaxRange(range)
            if drawnGlyphs < layout.numberOfGlyphs { beginPage() }
        }
    }

    // MARK: Icons

    private func drawIcon(_ name: String, at point: CGPoint, size: CGFloat, color: UIColor) {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
        guard let image = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        let scale = size / max(image.size.width, image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        // Flatten the symbol to a plain bitmap first; symbol images drawn straight into a
        // PDF context are stored as masks that some PDF viewers fill as solid squares.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 4
        format.opaque = false
        let bitmap = UIGraphicsImageRenderer(size: drawSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: drawSize))
        }
        bitmap.draw(in: CGRect(
            x: point.x + (size - drawSize.width) / 2,
            y: point.y + (size - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        ))
    }

    // MARK: Components

    private func strokeCard(_ rect: CGRect, radius: CGFloat = 14) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        Self.card.setFill()
        path.fill()
        Self.hairline.setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }

    func drawSectionHeader(_ title: String, icon: String?, trailing: String? = nil) {
        let font = Self.serif(20)
        let attrs = Self.attributes(font: font, color: Self.ink)
        var x = margin
        if let icon {
            drawIcon(icon, at: CGPoint(x: x, y: y + 3), size: 16, color: Self.ink2)
            x += 26
        }
        if let trailing {
            let tAttrs = Self.attributes(font: .systemFont(ofSize: 10), color: Self.ink2)
            let size = (trailing as NSString).size(withAttributes: tAttrs)
            (trailing as NSString).draw(at: CGPoint(x: pageRect.width - margin - size.width, y: y + 8), withAttributes: tAttrs)
        }
        draw(title, attrs: attrs, x: x, width: contentWidth - (x - margin) - 60)
        y += 12
    }

    /// A white card with a small heading and body. Long bodies that cannot fit on a
    /// single page are drawn without the card so the text can flow across pages.
    func drawCard(heading: String, body: String) {
        let padding: CGFloat = 16
        let innerWidth = contentWidth - padding * 2
        let headingAttrs = Self.attributes(font: .systemFont(ofSize: 10, weight: .semibold), color: Self.ink2)
        let bodyAttrs = Self.attributes(font: .systemFont(ofSize: 11.5), color: Self.ink, lineSpacing: 4)
        let headingHeight = height(of: heading, attrs: headingAttrs, width: innerWidth)
        let bodyHeight = height(of: body, attrs: bodyAttrs, width: innerWidth)
        let cardHeight = padding * 2 + headingHeight + 8 + bodyHeight
        let fullPage = bottom - margin

        if cardHeight <= fullPage {
            ensureSpace(cardHeight)
            strokeCard(CGRect(x: margin, y: y, width: contentWidth, height: cardHeight))
            let top = y
            y += padding
            draw(heading, attrs: headingAttrs, x: margin + padding, width: innerWidth)
            y += 8
            draw(body, attrs: bodyAttrs, x: margin + padding, width: innerWidth)
            y = top + cardHeight + 10
        } else {
            ensureSpace(60)
            draw(heading, attrs: headingAttrs, x: margin, width: contentWidth)
            y += 8
            drawFlowing(NSAttributedString(string: body, attributes: bodyAttrs), x: margin, width: contentWidth)
            y += 18
        }
    }

    /// Three tiles in a row: icon, big value, small label.
    func drawStatTiles(_ tiles: [(icon: String, value: String, label: String)]) {
        let spacing: CGFloat = 12
        let width = (contentWidth - spacing * CGFloat(tiles.count - 1)) / CGFloat(tiles.count)
        let height: CGFloat = 96
        ensureSpace(height)
        for (index, tile) in tiles.enumerated() {
            let rect = CGRect(x: margin + CGFloat(index) * (width + spacing), y: y, width: width, height: height)
            strokeCard(rect)
            drawIcon(tile.icon, at: CGPoint(x: rect.minX + 14, y: rect.minY + 14), size: 14, color: Self.ink2)
            let valueAttrs = Self.attributes(font: .systemFont(ofSize: 24, weight: .semibold), color: Self.ink)
            (tile.value as NSString).draw(at: CGPoint(x: rect.minX + 14, y: rect.minY + 38), withAttributes: valueAttrs)
            let labelAttrs = Self.attributes(font: .systemFont(ofSize: 10), color: Self.ink2)
            (tile.label as NSString).draw(at: CGPoint(x: rect.minX + 14, y: rect.minY + 70), withAttributes: labelAttrs)
        }
        y += height
    }

    /// Section with an outline icon, serif title and a numbered list with optional grey detail.
    func drawListSection(title: String, icon: String, items: [(text: String, detail: String?)]) {
        ensureSpace(90)
        // Hairline divider between sections
        Self.hairline.setFill()
        UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 0.75))
        y += 20
        drawSectionHeader(title, icon: icon)

        let numberAttrs = Self.attributes(font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular), color: Self.ink2)
        let textAttrs = Self.attributes(font: .systemFont(ofSize: 12), color: Self.ink, lineSpacing: 4)
        let detailAttrs = Self.attributes(font: .systemFont(ofSize: 10), color: Self.ink2)
        let indent: CGFloat = 24
        let width = contentWidth - indent

        for (index, item) in items.enumerated() {
            let textHeight = height(of: item.text, attrs: textAttrs, width: width)
            let detailHeight = item.detail.map { height(of: $0, attrs: detailAttrs, width: width) + 3 } ?? 0
            ensureSpace(min(textHeight + detailHeight, bottom - margin))
            ("\(index + 1)." as NSString).draw(at: CGPoint(x: margin, y: y + 1), withAttributes: numberAttrs)
            drawFlowing(NSAttributedString(string: item.text, attributes: textAttrs), x: margin + indent, width: width)
            if let detail = item.detail {
                y += 3
                draw(detail, attrs: detailAttrs, x: margin + indent, width: width)
            }
            y += 10
        }
        y += 16
    }

    /// Black cover page: overline, very large serif year, title and summary in paper color.
    func drawCover(year: Int, title: String, summary: String, filterLabel: String?) {
        y = margin + 40
        drawOverline(filterLabel.map { "YEAR WRAPPED · \($0.uppercased())" } ?? "YEAR WRAPPED", color: Self.onInk.withAlphaComponent(0.65))
        y += 8
        draw("\(year)", attrs: Self.attributes(font: Self.serif(120), color: Self.onInk), x: margin, width: contentWidth)
        y += 24
        draw(title, attrs: Self.attributes(font: Self.serif(28), color: Self.onInk), x: margin, width: contentWidth)
        y += 18
        let summaryAttrs = Self.attributes(font: .systemFont(ofSize: 13), color: Self.onInk.withAlphaComponent(0.85), lineSpacing: 5)
        let maxHeight = pageRect.height - margin - 60 - y
        let summaryHeight = min(height(of: summary, attrs: summaryAttrs, width: contentWidth), maxHeight)
        (summary as NSString).draw(
            with: CGRect(x: margin, y: y, width: contentWidth, height: summaryHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: summaryAttrs,
            context: nil
        )
        let footerAttrs = Self.attributes(font: .systemFont(ofSize: 10, weight: .medium), color: Self.onInk.withAlphaComponent(0.65))
        ("Life Wrapped" as NSString).draw(at: CGPoint(x: margin, y: pageRect.height - margin - 12), withAttributes: footerAttrs)
    }
}
#endif // canImport(UIKit)
