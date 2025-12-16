// =============================================================================
// Storage — Data Importer
// =============================================================================
// Import data from JSON export format (including test data)
// =============================================================================

import Foundation
import SharedModels

public actor DataImporter {
    private let databaseManager: DatabaseManager
    
    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    // MARK: - JSON Import
    
    /// Import data from JSON export format
    /// This matches the export format from DataExporter and can be used for:
    /// - Restoring backups
    /// - Importing test/dummy data
    /// - Data migration
    public func importFromJSON(data: Data) async throws -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let export = try decoder.decode(JSONExport.self, from: data)
        
        var importedChunks = 0
        var importedSegments = 0
        var importedSummaries = 0
        var errors: [String] = []
        
        // Import audio chunks
        for jsonChunk in export.audioChunks {
            do {
                let chunk = AudioChunk(
                    id: jsonChunk.id,
                    fileURL: jsonChunk.fileURL,
                    startTime: jsonChunk.startTime,
                    endTime: jsonChunk.endTime,
                    format: AudioFormat(rawValue: jsonChunk.format) ?? .m4a,
                    sampleRate: jsonChunk.sampleRate,
                    createdAt: jsonChunk.createdAt,
                    sessionId: jsonChunk.sessionId,
                    chunkIndex: jsonChunk.chunkIndex
                )
                try await databaseManager.insertAudioChunk(chunk)
                importedChunks += 1
            } catch {
                errors.append("Failed to import chunk \(jsonChunk.id): \(error)")
            }
        }
        
        // Import transcript segments if available
        if let segments = export.transcriptSegments {
            for jsonSegment in segments {
                do {
                    let segment = TranscriptSegment(
                        id: jsonSegment.id,
                        audioChunkID: jsonSegment.audioChunkID,
                        startTime: jsonSegment.startTime,
                        endTime: jsonSegment.endTime,
                        text: jsonSegment.text,
                        confidence: jsonSegment.confidence,
                        languageCode: jsonSegment.languageCode,
                        createdAt: jsonSegment.createdAt,
                        sentimentScore: jsonSegment.sentimentScore
                    )
                    try await databaseManager.insertTranscriptSegment(segment)
                    importedSegments += 1
                } catch {
                    errors.append("Failed to import segment \(jsonSegment.id): \(error)")
                }
            }
        }
        
        // Import summaries
        for jsonSummary in export.summaries {
            do {
                let summary = Summary(
                    id: jsonSummary.id,
                    periodType: PeriodType(rawValue: jsonSummary.periodType) ?? .session,
                    periodStart: jsonSummary.periodStart,
                    periodEnd: jsonSummary.periodEnd,
                    text: jsonSummary.text,
                    createdAt: jsonSummary.createdAt,
                    sessionId: jsonSummary.sessionId
                )
                try await databaseManager.insertSummary(summary)
                importedSummaries += 1
            } catch {
                errors.append("Failed to import summary \(jsonSummary.id): \(error)")
            }
        }
        
        return ImportResult(
            importedChunks: importedChunks,
            importedSegments: importedSegments,
            importedSummaries: importedSummaries,
            errors: errors
        )
    }
}

// MARK: - Import Result

public struct ImportResult: Sendable {
    public let importedChunks: Int
    public let importedSegments: Int
    public let importedSummaries: Int
    public let errors: [String]
    
    public var isSuccessful: Bool {
        return errors.isEmpty
    }
    
    public var hasPartialSuccess: Bool {
        return !errors.isEmpty && (importedChunks > 0 || importedSegments > 0 || importedSummaries > 0)
    }
    
    public var summary: String {
        var parts: [String] = []
        if importedChunks > 0 {
            parts.append("\(importedChunks) audio chunks")
        }
        if importedSegments > 0 {
            parts.append("\(importedSegments) transcript segments")
        }
        if importedSummaries > 0 {
            parts.append("\(importedSummaries) summaries")
        }
        
        let imported = parts.isEmpty ? "No data imported" : "Imported: " + parts.joined(separator: ", ")
        
        if !errors.isEmpty {
            return "\(imported). \(errors.count) errors occurred."
        }
        
        return imported
    }
}

// Note: JSON models are defined in DataExporter.swift and shared between import/export
