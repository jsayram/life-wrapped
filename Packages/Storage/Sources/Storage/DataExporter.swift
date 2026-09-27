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
        
        let export = JSONExport(
            exportDate: Date(),
            version: "1.0",
            audioChunks: chunks.map { JSONAudioChunk(from: $0) },
            transcriptSegments: allSegments.map { JSONTranscriptSegment(from: $0) },
            summaries: summaries.map { JSONSummary(from: $0) }
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        return try encoder.encode(export)
    }
    
    // MARK: - Markdown Export
    
    /// Export all data to Markdown format
    public func exportToMarkdown(year: Int? = nil) async throws -> String {
        let allSummaries = try await databaseManager.fetchAllSummaries()
        
        // Filter by year if specified
        let summaries: [Summary]
        if let year = year {
            let calendar = Calendar.current
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let endOfYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
            
            summaries = allSummaries.filter {
                $0.periodStart >= startOfYear && $0.periodStart < endOfYear
            }
        } else {
            summaries = allSummaries
        }
        
        var markdown = "# Life Wrapped Export\n\n"
        if let year = year {
            markdown += "**Year:** \(year)\n\n"
        }
        markdown += "**Export Date:** \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))\n\n"
        markdown += "---\n\n"
        
        // Group by period type
        let dailySummaries = summaries.filter { $0.periodType == .day }.sorted { $0.periodStart > $1.periodStart }
        let weeklySummaries = summaries.filter { $0.periodType == .week }.sorted { $0.periodStart > $1.periodStart }
        let monthlySummaries = summaries.filter { $0.periodType == .month }.sorted { $0.periodStart > $1.periodStart }
        
        if !dailySummaries.isEmpty {
            markdown += "## Daily Summaries\n\n"
            for summary in dailySummaries {
                markdown += formatSummaryMarkdown(summary)
            }
        }
        
        if !weeklySummaries.isEmpty {
            markdown += "## Weekly Summaries\n\n"
            for summary in weeklySummaries {
                markdown += formatSummaryMarkdown(summary)
            }
        }
        
        if !monthlySummaries.isEmpty {
            markdown += "## Monthly Summaries\n\n"
            for summary in monthlySummaries {
                markdown += formatSummaryMarkdown(summary)
            }
        }
        
        return markdown
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
        let yearWrap = filteredSummaries.first(where: { $0.periodType == .yearWrap })
        
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
        guard let parsedData = parseYearWrapJSON(from: yearWrap.text) else {
            // Fallback to standard PDF if parsing fails
            return renderStandardPDF(summaries: [yearWrap], year: year)
        }

        // Fetch session stats for the year
        let stats = try await fetchYearStats(year: year)
        let writer = GraphitePDFWriter(title: "Year Wrap \(year)")

        return writer.render { page in
            // Page 1: black cover, like the Year Wrapped card in the app
            page.beginCoverPage()
            page.drawCover(year: year, title: parsedData.yearTitle, summary: parsedData.yearSummary, filterLabel: filter == .workOnly ? "Work" : (filter == .personalOnly ? "Personal" : nil))

            // Page 2: numbers, then the insight sections flowing across pages
            page.beginPage()
            page.drawOverline("YEAR WRAPPED \(year)")
            page.drawSerif("Your year in numbers", size: 28)
            page.y += 16
            page.drawStatTiles([
                ("mic", "\(stats.sessions)", "entries"),
                ("clock", String(format: "%.1fh", stats.duration / 3600), "recorded"),
                ("text.alignleft", stats.words.formatted(), "words")
            ])
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
            if !parsedData.peopleMentioned.isEmpty {
                let lines = parsedData.peopleMentioned.map { person -> (text: String, detail: String?) in
                    let name = redactPeople ? "[Person]" : person.name
                    return (name, redactPeople ? nil : person.relationship)
                }
                page.drawListSection(title: "People mentioned", icon: "person.2", items: lines)
            }
            if !parsedData.placesVisited.isEmpty {
                let lines = parsedData.placesVisited.map { place -> (text: String, detail: String?) in
                    let name = redactPlaces ? "[Location]" : place.name
                    return (name, redactPlaces ? nil : place.frequency)
                }
                page.drawListSection(title: "Places visited", icon: "mappin.and.ellipse", items: lines)
            }

            // Redaction note
            if redactPeople || redactPlaces {
                let details: String
                if redactPeople && redactPlaces {
                    details = "All people and location names have been redacted in this export."
                } else if redactPeople {
                    details = "All people names have been redacted in this export."
                } else {
                    details = "All location names have been redacted in this export."
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
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Check for year_summary - required field for all formats
        guard let yearSummary = json["year_summary"] as? String else {
            return nil
        }
        
        let yearTitle = json["year_title"] as? String ?? "Year in Review"
        
        // Helper to parse classified items (supports both old string format and new object format)
        func parseClassifiedItems(_ key: String) -> [ClassifiedItem] {
            guard let array = json[key] as? [Any] else { return [] }
            
            return array.compactMap { item in
                // New format: {"text": "...", "category": "work|personal|both", "session_ids": [...]}
                if let dict = item as? [String: Any],
                   let text = dict["text"] as? String,
                   let categoryStr = dict["category"] as? String,
                   let category = ItemCategory(rawValue: categoryStr) {
                    return ClassifiedItem(text: text, category: category, sessionIds: Self.uuids(dict["session_ids"]))
                }
                // Old format: just strings - default to "both"
                else if let text = item as? String {
                    return ClassifiedItem(text: text, category: .both)
                }
                return nil
            }
        }
        
        // Check if this is simplified Local AI format (has top_highlights instead of detailed fields)
        let isSimplifiedFormat = json["top_highlights"] != nil
        
        if isSimplifiedFormat {
            // Parse Local AI simplified format
            let topHighlights = parseClassifiedItems("top_highlights")
            let challenges = parseClassifiedItems("biggest_challenges")
            let topics = parseClassifiedItems("top_topics")
            
            return YearWrapData(
                yearTitle: yearTitle,
                yearSummary: yearSummary,
                majorArcs: [],
                biggestWins: topHighlights,
                biggestLosses: [],
                biggestChallenges: challenges,
                finishedProjects: [],
                unfinishedProjects: [],
                topWorkedOnTopics: topics,
                topTalkedAboutThings: [],
                valuableActionsTaken: [],
                opportunitiesMissed: [],
                peopleMentioned: [],
                placesVisited: []
            )
        }
        
        // Standard format with detailed fields
        return YearWrapData(
            yearTitle: yearTitle,
            yearSummary: yearSummary,
            majorArcs: parseClassifiedItems("major_arcs"),
            biggestWins: parseClassifiedItems("biggest_wins"),
            biggestLosses: parseClassifiedItems("biggest_losses"),
            biggestChallenges: parseClassifiedItems("biggest_challenges"),
            finishedProjects: parseClassifiedItems("finished_projects"),
            unfinishedProjects: parseClassifiedItems("unfinished_projects"),
            topWorkedOnTopics: parseClassifiedItems("top_worked_on_topics"),
            topTalkedAboutThings: parseClassifiedItems("top_talked_about_things"),
            valuableActionsTaken: parseClassifiedItems("valuable_actions_taken"),
            opportunitiesMissed: parseClassifiedItems("opportunities_missed"),
            peopleMentioned: (json["people_mentioned"] as? [[String: Any]] ?? []).compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                return PersonMention(name: name, relationship: dict["relationship"] as? String, impact: dict["impact"] as? String,
                                     sessionIds: Self.uuids(dict["session_ids"]))
            },
            placesVisited: (json["places_visited"] as? [[String: Any]] ?? []).compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                return PlaceVisit(name: name, frequency: dict["frequency"] as? String, context: dict["context"] as? String,
                                  sessionIds: Self.uuids(dict["session_ids"]))
            }
        )
    }
    
    private static func uuids(_ value: Any?) -> [UUID]? {
        (value as? [String]).map { $0.compactMap(UUID.init(uuidString:)) }
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
    
    private func formatSummaryMarkdown(_ summary: Summary) -> String {
        var md = "### \(formatPeriod(summary.periodType, start: summary.periodStart, end: summary.periodEnd))\n\n"
        
        md += "\(summary.text)\n\n"
        
        md += "**Date:** \(DateFormatter.localizedString(from: summary.periodStart, dateStyle: .medium, timeStyle: .none))\n\n"
        
        md += "---\n\n"
        
        return md
    }
    
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
    
    init(from summary: Summary) {
        self.id = summary.id
        self.periodType = summary.periodType.rawValue
        self.periodStart = summary.periodStart
        self.periodEnd = summary.periodEnd
        self.text = summary.text
        self.createdAt = summary.createdAt
        self.sessionId = summary.sessionId
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
