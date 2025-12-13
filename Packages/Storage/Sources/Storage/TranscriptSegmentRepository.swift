// =============================================================================
// Storage — Transcript Segment Repository
// =============================================================================
// CRUD operations for TranscriptSegment entities using raw SQLite3 API.
// Thread-safe through DatabaseManager actor isolation.
// =============================================================================

import Foundation
import SQLite3
import SharedModels

/// SQLite transient destructor for text binding
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Repository for TranscriptSegment CRUD operations
@available(iOS 18.0, watchOS 11.0, macOS 15.0, *)
public actor TranscriptSegmentRepository {
    private let manager: DatabaseManager
    
    public init(manager: DatabaseManager) {
        self.manager = manager
    }
    
    // MARK: - Create
    
    public func insert(_ segment: TranscriptSegment) async throws {
        let sql = """
            INSERT INTO transcript_segments 
            (id, audio_chunk_id, start_time, end_time, text, confidence, language_code, created_at, speaker_label, entities_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        
        guard let db = await manager.getDB() else {
            throw StorageError.notOpen
        }
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(await manager.lastError())
        }
        
        try bind(segment, to: stmt)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(await manager.lastError())
        }
    }
    
    // MARK: - Read
    
    public func fetch(id: UUID) async throws -> TranscriptSegment? {
        let sql = """
            SELECT id, audio_chunk_id, start_time, end_time, text, confidence, language_code, created_at, speaker_label, entities_json
            FROM transcript_segments
            WHERE id = ?
            """
        
        guard let db = await manager.getDB() else {
            throw StorageError.notOpen
        }
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(await manager.lastError())
        }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return try parseTranscriptSegment(from: stmt)
        }
        
        return nil
    }
    
    public func fetchByAudioChunk(audioChunkID: UUID) async throws -> [TranscriptSegment] {
        let sql = """
            SELECT id, audio_chunk_id, start_time, end_time, text, confidence, language_code, created_at, speaker_label, entities_json
            FROM transcript_segments
            WHERE audio_chunk_id = ?
            ORDER BY start_time ASC
            """
        
        guard let db = await manager.getDB() else {
            throw StorageError.notOpen
        }
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(await manager.lastError())
        }
        
        sqlite3_bind_text(stmt, 1, audioChunkID.uuidString, -1, SQLITE_TRANSIENT)
        
        var segments: [TranscriptSegment] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let segment = try parseTranscriptSegment(from: stmt)
            segments.append(segment)
        }
        
        return segments
    }
    
    public func fetchAll(audioChunkID: UUID? = nil, limit: Int? = nil, offset: Int = 0) async throws -> [TranscriptSegment] {
        var sql = """
            SELECT id, audio_chunk_id, start_time, end_time, text, confidence, language_code, created_at, speaker_label, entities_json
            FROM transcript_segments
            """
        
        if audioChunkID != nil {
            sql += " WHERE audio_chunk_id = ?"
        }
        
        sql += " ORDER BY start_time ASC"
        
        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }
        
        guard let db = await manager.getDB() else {
            throw StorageError.notOpen
        }
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(await manager.lastError())
        }
        
        var index: Int32 = 1
        if let audioChunkID = audioChunkID {
            sqlite3_bind_text(stmt, index, audioChunkID.uuidString, -1, SQLITE_TRANSIENT)
            index += 1
        }
        
        var segments: [TranscriptSegment] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let segment = try parseTranscriptSegment(from: stmt)
            segments.append(segment)
        }
        
        return segments
    }
    
    // MARK: - Update
    
    public func update(_ segment: TranscriptSegment) async throws {
        let sql = """
            UPDATE transcript_segments
            SET audio_chunk_id = ?, start_time = ?, end_time = ?, text = ?, confidence = ?, 
                language_code = ?, speaker_label = ?, entities_json = ?
            WHERE id = ?
            """
        
        guard let db = await manager.getDB() else {
            throw StorageError.notOpen
        }
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(await manager.lastError())
        }
        
        sqlite3_bind_text(stmt, 1, segment.audioChunkID.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, segment.startTime)
        sqlite3_bind_double(stmt, 3, segment.endTime)
        sqlite3_bind_text(stmt, 4, segment.text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 5, Double(segment.confidence))
        sqlite3_bind_text(stmt, 6, segment.languageCode, -1, SQLITE_TRANSIENT)
        
        if let speakerLabel = segment.speakerLabel {
            sqlite3_bind_text(stmt, 7, speakerLabel, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        
        if let entitiesJSON = segment.entitiesJSON {
            sqlite3_bind_text(stmt, 8, entitiesJSON, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        
        sqlite3_bind_text(stmt, 9, segment.id.uuidString, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(await manager.lastError())
        }
    }
    
    // MARK: - Delete
    
    public func delete(id: UUID) async throws {
        let sql = "DELETE FROM transcript_segments WHERE id = ?"
        
        guard let db = await manager.getDB() else {
            throw StorageError.notOpen
        }
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(await manager.lastError())
        }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(await manager.lastError())
        }
    }
    
    // MARK: - Helper Methods
    
    private func bind(_ segment: TranscriptSegment, to stmt: OpaquePointer?) throws {
        sqlite3_bind_text(stmt, 1, segment.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, segment.audioChunkID.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, segment.startTime)
        sqlite3_bind_double(stmt, 4, segment.endTime)
        sqlite3_bind_text(stmt, 5, segment.text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 6, Double(segment.confidence))
        sqlite3_bind_text(stmt, 7, segment.languageCode, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 8, segment.createdAt.timeIntervalSince1970)
        
        if let speakerLabel = segment.speakerLabel {
            sqlite3_bind_text(stmt, 9, speakerLabel, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        
        if let entitiesJSON = segment.entitiesJSON {
            sqlite3_bind_text(stmt, 10, entitiesJSON, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 10)
        }
    }
    
    private func parseTranscriptSegment(from stmt: OpaquePointer?) throws -> TranscriptSegment {
        guard let idString = sqlite3_column_text(stmt, 0),
              let audioChunkIDString = sqlite3_column_text(stmt, 1),
              let textString = sqlite3_column_text(stmt, 4),
              let languageCodeString = sqlite3_column_text(stmt, 6) else {
            throw StorageError.invalidData("Missing required TranscriptSegment column data")
        }
        
        guard let id = UUID(uuidString: String(cString: idString)),
              let audioChunkID = UUID(uuidString: String(cString: audioChunkIDString)) else {
            throw StorageError.invalidData("Could not parse TranscriptSegment UUID fields")
        }
        
        let startTime = sqlite3_column_double(stmt, 2)
        let endTime = sqlite3_column_double(stmt, 3)
        let text = String(cString: textString)
        let confidence = Float(sqlite3_column_double(stmt, 5))
        let languageCode = String(cString: languageCodeString)
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
        
        let speakerLabel: String?
        if let speakerLabelText = sqlite3_column_text(stmt, 8) {
            speakerLabel = String(cString: speakerLabelText)
        } else {
            speakerLabel = nil
        }
        
        let entitiesJSON: String?
        if let entitiesText = sqlite3_column_text(stmt, 9) {
            entitiesJSON = String(cString: entitiesText)
        } else {
            entitiesJSON = nil
        }
        
        return TranscriptSegment(
            id: id,
            audioChunkID: audioChunkID,
            startTime: startTime,
            endTime: endTime,
            text: text,
            confidence: confidence,
            languageCode: languageCode,
            createdAt: createdAt,
            speakerLabel: speakerLabel,
            entitiesJSON: entitiesJSON
        )
    }
}
