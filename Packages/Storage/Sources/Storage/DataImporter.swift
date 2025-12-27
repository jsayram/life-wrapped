// =============================================================================
// Storage — Data Importer
// =============================================================================
// Import data from JSON export format (including test data)
// =============================================================================

import Foundation
import SharedModels

public actor DataImporter {
    private let databaseManager: DatabaseManager
    
    // Progress callback (called on main actor for UI updates)
    public var onProgress: (@MainActor @Sendable (Int, Int) -> Void)?
    
    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    // Setter for progress callback (actor-isolated)
    public func setProgressCallback(_ callback: @escaping @MainActor @Sendable (Int, Int) -> Void) {
        self.onProgress = callback
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
        
        // Calculate total items for progress tracking
        let totalItems = export.audioChunks.count + (export.transcriptSegments?.count ?? 0) + export.summaries.count
        var currentIndex = 0
        
        var importedChunks = 0
        var importedSegments = 0
        var importedSummaries = 0
        var skippedItems: [(id: String, reason: String)] = []
        var errors: [(id: String, error: String)] = []
        
        // Import audio chunks
        for jsonChunk in export.audioChunks {
            currentIndex += 1
            await reportProgress(currentIndex, totalItems)
            
            do {
                // Check for duplicate
                if let existing = try await databaseManager.fetchAudioChunk(id: jsonChunk.id) {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    let dateStr = formatter.string(from: existing.createdAt)
                    skippedItems.append((jsonChunk.id.uuidString, "Already exists (created \(dateStr))"))
                    continue
                }
                
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
                errors.append((jsonChunk.id.uuidString, "Insert failed: \(error.localizedDescription)"))
            }
        }
        
        // Import transcript segments if available
        if let segments = export.transcriptSegments {
            for jsonSegment in segments {
                currentIndex += 1
                await reportProgress(currentIndex, totalItems)
                
                do {
                    // Check for duplicate
                    if try await databaseManager.fetchTranscriptSegment(id: jsonSegment.id) != nil {
                        skippedItems.append((jsonSegment.id.uuidString, "Already exists"))
                        continue
                    }
                    
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
                    errors.append((jsonSegment.id.uuidString, "Insert failed: \(error.localizedDescription)"))
                }
            }
        }
        
        // Import summaries
        for jsonSummary in export.summaries {
            currentIndex += 1
            await reportProgress(currentIndex, totalItems)
            
            do {
                // Check for duplicate
                if try await databaseManager.fetchSummary(id: jsonSummary.id) != nil {
                    skippedItems.append((jsonSummary.id.uuidString, "Already exists"))
                    continue
                }
                
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
                errors.append((jsonSummary.id.uuidString, "Insert failed: \(error.localizedDescription)"))
            }
        }
        
        return ImportResult(
            importedChunks: importedChunks,
            importedSegments: importedSegments,
            importedSummaries: importedSummaries,
            skippedItems: skippedItems,
            errors: errors
        )
    }
    
    private func reportProgress(_ current: Int, _ total: Int) async {
        guard let onProgress = onProgress else { return }
        await onProgress(current, total)
    }
}

// MARK: - Import Result

public struct ImportResult: Sendable {
    public let importedChunks: Int
    public let importedSegments: Int
    public let importedSummaries: Int
    public let skippedItems: [(id: String, reason: String)]
    public let errors: [(id: String, error: String)]
    
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
        
        var status = imported
        if !skippedItems.isEmpty {
            status += ". \(skippedItems.count) duplicates skipped"
        }
        if !errors.isEmpty {
            status += ". \(errors.count) errors occurred"
        }
        
        return status
    }
}

// Note: JSON models are defined in DataExporter.swift and shared between import/export
