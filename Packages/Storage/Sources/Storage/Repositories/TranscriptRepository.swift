// =============================================================================
// Storage — Transcript Repository
// =============================================================================
// CRUD operations, search, and sentiment analytics for transcript segments.
// =============================================================================

import Foundation
import SQLite3
import SharedModels
import os.log

public actor TranscriptRepository {
    private let logger = Logger(subsystem: "com.jsayram.lifewrapped", category: "Storage")
    private let connection: DatabaseConnection
    
    public init(connection: DatabaseConnection) {
        self.connection = connection
    }
    
    // MARK: - Transcript CRUD
    
    public func insert(_ segment: TranscriptSegment) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                INSERT INTO transcript_segments 
                (id, audio_chunk_id, start_time, end_time, text, confidence, language_code, created_at, speaker_label, entities_json, word_count, sentiment_score)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
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
            
            sqlite3_bind_int(stmt, 11, Int32(segment.wordCount))
            
            if let sentimentScore = segment.sentimentScore {
                sqlite3_bind_double(stmt, 12, sentimentScore)
            } else {
                sqlite3_bind_null(stmt, 12)
            }
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(await connection.lastError())
            }
        }
    }
    
    public func fetch(id: UUID) async throws -> TranscriptSegment? {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT id, audio_chunk_id, start_time, end_time, text, confidence, language_code, created_at, speaker_label, entities_json, word_count, sentiment_score
                FROM transcript_segments
                WHERE id = ?
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return try parseTranscriptSegment(from: stmt)
            }
            
            return nil
        }
    }
    
    public func fetchSegmentsByChunk(audioChunkID: UUID) async throws -> [TranscriptSegment] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT id, audio_chunk_id, start_time, end_time, text, confidence, language_code, created_at, speaker_label, entities_json, word_count, sentiment_score
                FROM transcript_segments
                WHERE audio_chunk_id = ?
                ORDER BY start_time ASC
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, audioChunkID.uuidString, -1, SQLITE_TRANSIENT)
            
            var segments: [TranscriptSegment] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                segments.append(try parseTranscriptSegment(from: stmt))
            }
            
            return segments
        }
    }
    
    public func delete(id: UUID) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = "DELETE FROM transcript_segments WHERE id = ?"
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(await connection.lastError())
            }
        }
    }
    
    /// Update transcript segment text (for user edits)
    /// Also recalculates word count automatically
    public func updateText(id: UUID, newText: String) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let wordCount = newText.split(separator: " ").count
            
            let sql = """
                UPDATE transcript_segments 
                SET text = ?, word_count = ?
                WHERE id = ?
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, newText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(wordCount))
            sqlite3_bind_text(stmt, 3, id.uuidString, -1, SQLITE_TRANSIENT)
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(await connection.lastError())
            }
            
            logger.debug("Updated transcript segment \(id) text, new word count: \(wordCount)")
        }
    }
    
    // MARK: - Search & Queries
    
    /// Search for sessions containing text in transcripts
    /// Returns session IDs that have matching transcript text
    public func searchSessionsByTranscript(query: String) async throws -> Set<UUID> {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT DISTINCT ac.session_id
                FROM transcript_segments ts
                INNER JOIN audio_chunks ac ON ts.audio_chunk_id = ac.id
                WHERE ts.text LIKE ?
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            // Use wildcards for partial matching
            let searchPattern = "%\(query)%"
            sqlite3_bind_text(stmt, 1, searchPattern, -1, SQLITE_TRANSIENT)
            
            var sessionIds: Set<UUID> = []
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let sessionIdCStr = sqlite3_column_text(stmt, 0),
                   let sessionId = UUID(uuidString: String(cString: sessionIdCStr)) {
                    sessionIds.insert(sessionId)
                }
            }
            
            logger.debug("Found \(sessionIds.count) sessions matching transcript query: \(query)")
            return sessionIds
        }
    }
    
    /// Check if all chunks in a session have been transcribed
    public func isSessionTranscriptionComplete(sessionId: UUID) async throws -> Bool {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT COUNT(DISTINCT ac.id) as total_chunks,
                       COUNT(DISTINCT ts.audio_chunk_id) as transcribed_chunks
                FROM audio_chunks ac
                LEFT JOIN transcript_segments ts ON ac.id = ts.audio_chunk_id
                WHERE ac.session_id = ?
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                let totalChunks = sqlite3_column_int(stmt, 0)
                let transcribedChunks = sqlite3_column_int(stmt, 1)
                return totalChunks == transcribedChunks && totalChunks > 0
            }
            
            return false
        }
    }
    
    public func getSegments(from startDate: Date, to endDate: Date) async throws -> [TranscriptSegment] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT ts.id, ts.audio_chunk_id, ts.start_time, ts.end_time, ts.text, ts.confidence, 
                       ts.language_code, ts.created_at, ts.speaker_label, ts.entities_json, ts.word_count, ts.sentiment_score
                FROM transcript_segments ts
                INNER JOIN audio_chunks ac ON ts.audio_chunk_id = ac.id
                WHERE ac.start_time >= ? AND ac.start_time < ?
                ORDER BY ac.start_time ASC, ts.start_time ASC
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_double(stmt, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, endDate.timeIntervalSince1970)
            
            var segments: [TranscriptSegment] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                segments.append(try parseTranscriptSegment(from: stmt))
            }
            
            return segments
        }
    }
    
    /// Efficiently get total word count for a session
    public func fetchSessionWordCount(sessionId: UUID) async throws -> Int {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT SUM(ts.word_count) 
                FROM transcript_segments ts
                INNER JOIN audio_chunks ac ON ts.audio_chunk_id = ac.id
                WHERE ac.session_id = ?
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
            
            return 0
        }
    }
    
    // MARK: - Sentiment Analytics
    
    /// Fetch average sentiment score for a specific session
    public func fetchSessionSentiment(sessionId: UUID) async throws -> Double? {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT AVG(ts.sentiment_score)
                FROM transcript_segments ts
                INNER JOIN audio_chunks ac ON ts.audio_chunk_id = ac.id
                WHERE ac.session_id = ? AND ts.sentiment_score IS NOT NULL
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                if sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                    return sqlite3_column_double(stmt, 0)
                }
            }
            
            return nil
        }
    }
    
    /// Fetch daily average sentiment scores for date range
    public func fetchDailySentiment(from startDate: Date, to endDate: Date) async throws -> [(date: Date, sentiment: Double)] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT 
                    DATE(ac.start_time, 'unixepoch') as day,
                    AVG(ts.sentiment_score) as avg_sentiment
                FROM transcript_segments ts
                INNER JOIN audio_chunks ac ON ts.audio_chunk_id = ac.id
                WHERE ac.start_time >= ? 
                    AND ac.start_time < ?
                    AND ts.sentiment_score IS NOT NULL
                GROUP BY day
                ORDER BY day ASC
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_double(stmt, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, endDate.timeIntervalSince1970)
            
            var results: [(Date, Double)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let dayString = sqlite3_column_text(stmt, 0) {
                    let dayStr = String(cString: dayString)
                    let sentiment = sqlite3_column_double(stmt, 1)
                    
                    // Parse date from "YYYY-MM-DD" format
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    if let date = formatter.date(from: dayStr) {
                        results.append((date, sentiment))
                    }
                }
            }
            
            return results
        }
    }
    
    /// Fetch language distribution from all transcript segments
    public func fetchLanguageDistribution() async throws -> [(language: String, wordCount: Int)] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT 
                    language_code,
                    SUM(word_count) as total_words
                FROM transcript_segments
                WHERE language_code IS NOT NULL
                GROUP BY language_code
                ORDER BY total_words DESC
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            var results: [(String, Int)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let language = String(cString: sqlite3_column_text(stmt, 0))
                let wordCount = Int(sqlite3_column_int64(stmt, 1))
                results.append((language, wordCount))
            }
            
            return results
        }
    }
    
    /// Fetch dominant language for a specific session
    public func fetchSessionLanguage(sessionId: UUID) async throws -> String? {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT 
                    ts.language_code,
                    SUM(ts.word_count) as total_words
                FROM transcript_segments ts
                INNER JOIN audio_chunks ac ON ts.audio_chunk_id = ac.id
                WHERE ac.session_id = ?
                    AND ts.language_code IS NOT NULL
                GROUP BY ts.language_code
                ORDER BY total_words DESC
                LIMIT 1
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            let sessionIdString = sessionId.uuidString
            sqlite3_bind_text(stmt, 1, (sessionIdString as NSString).utf8String, -1, nil)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return String(cString: sqlite3_column_text(stmt, 0))
            }
            
            return nil
        }
    }
    
    // MARK: - Parsing Helper
    
    nonisolated private func parseTranscriptSegment(from stmt: OpaquePointer?) throws -> TranscriptSegment {
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
        
        let wordCount = Int(sqlite3_column_int(stmt, 10))
        
        let sentimentScore: Double?
        if sqlite3_column_type(stmt, 11) != SQLITE_NULL {
            sentimentScore = sqlite3_column_double(stmt, 11)
        } else {
            sentimentScore = nil
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
            entitiesJSON: entitiesJSON,
            wordCount: wordCount,
            sentimentScore: sentimentScore
        )
    }
}
