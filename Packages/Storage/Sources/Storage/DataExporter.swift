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
        
        let export = JSONExport(
            exportDate: Date(),
            version: "1.0",
            audioChunks: chunks.map { JSONAudioChunk(from: $0) },
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
        let dailySummaries = summaries.filter { $0.periodType == .daily }.sorted { $0.startDate > $1.startDate }
        let weeklySummaries = summaries.filter { $0.periodType == .weekly }.sorted { $0.startDate > $1.startDate }
        let monthlySummaries = summaries.filter { $0.periodType == .monthly }.sorted { $0.startDate > $1.startDate }
        
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
        var md = "### \(formatPeriod(summary.periodType, start: summary.startDate, end: summary.endDate))\n\n"
        
        if let content = summary.content {
            md += "\(content)\n\n"
        }
        
        md += "**Stats:**\n"
        md += "- Segments: \(summary.segmentCount)\n"
        md += "- Words: \(summary.wordCount)\n"
        md += "- Duration: \(formatDuration(summary.totalDuration))\n\n"
        
        md += "---\n\n"
        
        return md
    }
    
    private func formatPeriod(_ type: PeriodType, start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        switch type {
        case .daily:
            formatter.dateFormat = "EEEE, MMMM d, yyyy"
            return formatter.string(from: start)
        case .weekly:
            formatter.dateFormat = "MMM d"
            return "Week of \(formatter.string(from: start))"
        case .monthly:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: start)
        case .yearly:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: start)
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
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
            databaseSize: try getDatabaseSize()
        )
    }
    
    private func getDatabaseSize() throws -> Int64 {
        // Get database file size
        let dbPath = databaseManager.databaseURL.path
        if FileManager.default.fileExists(atPath: dbPath) {
            let attrs = try FileManager.default.attributesOfItem(atPath: dbPath)
            return attrs[.size] as? Int64 ?? 0
        }
        return 0
    }
}

// MARK: - Export Models

public struct JSONExport: Codable {
    let exportDate: Date
    let version: String
    let audioChunks: [JSONAudioChunk]
    let summaries: [JSONSummary]
}

public struct JSONAudioChunk: Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let format: String
    let sampleRate: Int
    let createdAt: Date
    
    init(from chunk: AudioChunk) {
        self.id = chunk.id
        self.startTime = chunk.startTime
        self.endTime = chunk.endTime
        self.format = chunk.format.rawValue
        self.sampleRate = chunk.sampleRate
        self.createdAt = chunk.createdAt
    }
}

public struct JSONSummary: Codable {
    let id: UUID
    let periodType: String
    let startDate: Date
    let endDate: Date
    let content: String?
    let segmentCount: Int
    let wordCount: Int
    let totalDuration: TimeInterval
    let createdAt: Date
    
    init(from summary: Summary) {
        self.id = summary.id
        self.periodType = summary.periodType.rawValue
        self.startDate = summary.startDate
        self.endDate = summary.endDate
        self.content = summary.content
        self.segmentCount = summary.segmentCount
        self.wordCount = summary.wordCount
        self.totalDuration = summary.totalDuration
        self.createdAt = summary.createdAt
    }
}

public struct StorageInfo {
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
