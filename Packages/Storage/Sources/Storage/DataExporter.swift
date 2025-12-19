// =============================================================================
// Storage — Data Exporter
// =============================================================================
// Export user data to various formats (JSON, Markdown, CSV)
// =============================================================================

import Foundation
import SharedModels

public actor DataExporter {
    private let databaseManager: DatabaseManager
    
    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    // MARK: - JSON Export
    
    /// Export all data to JSON format
    public func exportToJSON() async throws -> Data {
        let chunks = try await databaseManager.fetchAllAudioChunks()
        let summaries = try await databaseManager.fetchAllSummaries()
        
        // Fetch all transcript segments
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
    public func exportToMarkdown() async throws -> String {
        let summaries = try await databaseManager.fetchAllSummaries()
        
        var markdown = "# Life Wrapped Export\n\n"
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
        case .year:
            formatter.dateFormat = "yyyy"
            return "Year \(formatter.string(from: start))"
    }

    
    // MARK: - Storage Info
    
    /// Get storage usage statistics
    public func getStorageInfo() async throws -> StorageInfo {
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
            databaseSize: try await getDatabaseSize()
        )
    }
    
    private func getDatabaseSize() async throws -> Int64 {
        // Get database file size from container
        let chunks = try await databaseManager.fetchAllAudioChunks()
        if let firstChunk = chunks.first {
            // Navigate up from audio file to database directory
            let dbDirectory = firstChunk.fileURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Database")
            let dbPath = dbDirectory.appendingPathComponent("lifewrapped.db").path
            if FileManager.default.fileExists(atPath: dbPath) {
                let attrs = try FileManager.default.attributesOfItem(atPath: dbPath)
                if let size = attrs[FileAttributeKey.size] as? Int64 {
                    return size
                }
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
    
    public var totalSize: Int64 {
        totalAudioSize + databaseSize
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
}
