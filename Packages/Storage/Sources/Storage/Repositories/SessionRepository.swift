// =============================================================================
// Storage — Session Repository
// =============================================================================
// Session queries, analytics, and metadata operations.
// =============================================================================

import Foundation
import SQLite3
import SharedModels
import os.log

public actor SessionRepository {
    private let logger = Logger(subsystem: "com.jsayram.lifewrapped", category: "Storage")
    private let connection: DatabaseConnection
    
    public init(connection: DatabaseConnection) {
        self.connection = connection
    }
    
    // MARK: - Session Metadata Model
    
    /// Session metadata model for title, notes, favorites, and category
    public struct SessionMetadata: Sendable {
        public let sessionId: UUID
        public var title: String?
        public var notes: String?
        public var isFavorite: Bool
        public var category: SessionCategory?
        public let createdAt: Date
        public var updatedAt: Date
        
        public init(sessionId: UUID, title: String? = nil, notes: String? = nil, isFavorite: Bool = false, category: SessionCategory? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
            self.sessionId = sessionId
            self.title = title
            self.notes = notes
            self.isFavorite = isFavorite
            self.category = category
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
    
    // MARK: - Session Queries
    
    /// Fetch all chunks belonging to a session, ordered by chunk_index
    public func fetchChunksBySession(sessionId: UUID) async throws -> [AudioChunk] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT id, file_url, start_time, end_time, format, sample_rate, created_at, session_id, chunk_index
                FROM audio_chunks
                WHERE session_id = ?
                ORDER BY chunk_index ASC
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
            
            var chunks: [AudioChunk] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                chunks.append(try parseAudioChunk(from: stmt))
            }
            
            return chunks
        }
    }
    
    /// Fetch all unique sessions with their first chunk's timestamp
    public func fetchSessions(limit: Int = 100) async throws -> [(sessionId: UUID, firstChunkTime: Date, chunkCount: Int)] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT 
                    session_id,
                    MIN(start_time) as first_chunk_time,
                    COUNT(*) as chunk_count
                FROM audio_chunks
                GROUP BY session_id
                ORDER BY first_chunk_time DESC
                LIMIT ?
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_int(stmt, 1, Int32(limit))
            
            var sessions: [(UUID, Date, Int)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let sessionIdString = sqlite3_column_text(stmt, 0),
                      let sessionId = UUID(uuidString: String(cString: sessionIdString)) else {
                    continue
                }
                
                let firstChunkTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
                let chunkCount = Int(sqlite3_column_int(stmt, 2))
                
                sessions.append((sessionId, firstChunkTime, chunkCount))
            }
            
            return sessions
        }
    }
    
    /// Fetch sessions by date
    public func fetchByDate(date: Date) async throws -> [RecordingSession] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            
            let sql = """
                SELECT DISTINCT session_id, MIN(start_time) as first_time
                FROM audio_chunks
                WHERE start_time >= ? AND start_time < ?
                GROUP BY session_id
                ORDER BY first_time DESC
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_double(stmt, 1, startOfDay.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, endOfDay.timeIntervalSince1970)
            
            var sessions: [RecordingSession] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let idString = sqlite3_column_text(stmt, 0),
                   let id = UUID(uuidString: String(cString: idString)) {
                    sessions.append(RecordingSession(sessionId: id, chunks: []))
                }
            }
            
            return sessions
        }
    }
    
    /// Delete an entire session (all chunks)
    public func deleteSession(sessionId: UUID) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            // Cascade delete will handle transcript_segments via FK
            let sql = "DELETE FROM audio_chunks WHERE session_id = ?"
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(await connection.lastError())
            }
        }
    }
    
    /// Fetch sessions filtered by category
    public func fetchSessionsByCategory(category: SessionCategory, limit: Int? = nil) async throws -> [RecordingSession] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT DISTINCT ac.session_id, MIN(ac.start_time) as first_time
                FROM audio_chunks ac
                INNER JOIN session_metadata sm ON ac.session_id = sm.session_id
                WHERE sm.category = ?
                GROUP BY ac.session_id
                ORDER BY first_time DESC
                \(limit != nil ? "LIMIT ?" : "")
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, category.rawValue, -1, SQLITE_TRANSIENT)
            if let limit = limit {
                sqlite3_bind_int(stmt, 2, Int32(limit))
            }
            
            var sessions: [RecordingSession] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let idString = sqlite3_column_text(stmt, 0),
                   let id = UUID(uuidString: String(cString: idString)) {
                    // Fetch full session with chunks and metadata
                    let chunks = try await fetchChunksBySession(sessionId: id)
                    let metadata = try await fetchSessionMetadata(sessionId: id)
                    sessions.append(RecordingSession(
                        sessionId: id,
                        chunks: chunks,
                        title: metadata?.title,
                        notes: metadata?.notes,
                        isFavorite: metadata?.isFavorite ?? false,
                        category: metadata?.category
                    ))
                }
            }
            
            return sessions
        }
    }
    
    // MARK: - Analytics Queries
    
    /// Fetch session counts grouped by hour of day (0-23)
    public func fetchSessionsByHour() async throws -> [(hour: Int, count: Int, sessionIds: [UUID])] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT 
                    CAST(strftime('%H', datetime(start_time, 'unixepoch', 'localtime')) AS INTEGER) as hour,
                    session_id
                FROM audio_chunks
                WHERE chunk_index = 0
                ORDER BY hour
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            // Group by hour
            var hourGroups: [Int: [UUID]] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let hour = Int(sqlite3_column_int(stmt, 0))
                guard let sessionIdString = sqlite3_column_text(stmt, 1),
                      let sessionId = UUID(uuidString: String(cString: sessionIdString)) else {
                    continue
                }
                
                hourGroups[hour, default: []].append(sessionId)
            }
            
            // Convert to sorted array
            return hourGroups.map { (hour: $0.key, count: $0.value.count, sessionIds: $0.value) }
                .sorted { $0.hour < $1.hour }
        }
    }
    
    /// Fetch the longest recording session by total duration
    public func fetchLongestSession() async throws -> (sessionId: UUID, duration: TimeInterval, date: Date)? {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT 
                    session_id,
                    SUM(end_time - start_time) as total_duration,
                    MIN(created_at) as session_date
                FROM audio_chunks
                GROUP BY session_id
                ORDER BY total_duration DESC
                LIMIT 1
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                guard let sessionIdString = sqlite3_column_text(stmt, 0),
                      let sessionId = UUID(uuidString: String(cString: sessionIdString)) else {
                    return nil
                }
                
                let duration = sqlite3_column_double(stmt, 1)
                let date = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                
                return (sessionId, duration, date)
            }
            
            return nil
        }
    }
    
    /// Fetch the most active month by session count
    public func fetchMostActiveMonth() async throws -> (year: Int, month: Int, count: Int, sessionIds: [UUID])? {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT 
                    CAST(strftime('%Y', datetime(created_at, 'unixepoch', 'localtime')) AS INTEGER) as year,
                    CAST(strftime('%m', datetime(created_at, 'unixepoch', 'localtime')) AS INTEGER) as month,
                    session_id
                FROM audio_chunks
                WHERE chunk_index = 0
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            // Group by year-month
            var groupDict: [String: (year: Int, month: Int, sessionIds: [UUID])] = [:]
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let year = Int(sqlite3_column_int(stmt, 0))
                let month = Int(sqlite3_column_int(stmt, 1))
                guard let sessionIdString = sqlite3_column_text(stmt, 2),
                      let sessionId = UUID(uuidString: String(cString: sessionIdString)) else {
                    continue
                }
                
                let key = "\(year)-\(month)"
                if var existing = groupDict[key] {
                    existing.sessionIds.append(sessionId)
                    groupDict[key] = existing
                } else {
                    groupDict[key] = (year, month, [sessionId])
                }
            }
            
            // Find month with most sessions
            return groupDict.values
                .map { (year: $0.year, month: $0.month, count: $0.sessionIds.count, sessionIds: $0.sessionIds) }
                .max { $0.count < $1.count }
        }
    }
    
    /// Fetch all transcript text within a date range
    public func fetchTranscriptText(startDate: Date, endDate: Date) async throws -> [String] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT ts.text
                FROM transcript_segments ts
                INNER JOIN audio_chunks ac ON ts.audio_chunk_id = ac.id
                WHERE ac.created_at >= ? AND ac.created_at <= ?
                ORDER BY ts.start_time
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_double(stmt, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, endDate.timeIntervalSince1970)
            
            var texts: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let textPtr = sqlite3_column_text(stmt, 0) {
                    let text = String(cString: textPtr)
                    texts.append(text)
                }
            }
            
            return texts
        }
    }
    
    /// Fetch session counts grouped by day of week (0 = Sunday, 6 = Saturday)
    public func fetchSessionsByDayOfWeek() async throws -> [(dayOfWeek: Int, count: Int, sessionIds: [UUID])] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            // SQLite strftime('%w') returns day of week: 0 = Sunday, 6 = Saturday
            let sql = """
                SELECT 
                    CAST(strftime('%w', datetime(created_at, 'unixepoch', 'localtime')) AS INTEGER) as day_of_week,
                    session_id
                FROM audio_chunks
                WHERE chunk_index = 0
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            // Group by day of week
            var dayGroups: [Int: [UUID]] = [:]
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let dayOfWeek = Int(sqlite3_column_int(stmt, 0))
                guard let sessionIdString = sqlite3_column_text(stmt, 1),
                      let sessionId = UUID(uuidString: String(cString: sessionIdString)) else {
                    continue
                }
                
                dayGroups[dayOfWeek, default: []].append(sessionId)
            }
            
            // Convert to array and sort by day (0-6)
            return dayGroups
                .map { (dayOfWeek: $0.key, count: $0.value.count, sessionIds: $0.value) }
                .sorted { $0.dayOfWeek < $1.dayOfWeek }
        }
    }
    
    /// Fetch sessions grouped by year
    public func fetchSessionsByYear() async throws -> [(year: Int, count: Int, sessionIds: [UUID])] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT 
                    CAST(strftime('%Y', datetime(created_at, 'unixepoch', 'localtime')) AS INTEGER) as year,
                    session_id
                FROM audio_chunks
                WHERE chunk_index = 0
                ORDER BY year DESC
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            // Group by year
            var yearGroups: [Int: [UUID]] = [:]
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let year = Int(sqlite3_column_int(stmt, 0))
                guard let sessionIdString = sqlite3_column_text(stmt, 1),
                      let sessionId = UUID(uuidString: String(cString: sessionIdString)) else {
                    continue
                }
                
                yearGroups[year, default: []].append(sessionId)
            }
            
            // Convert to array and sort by year (descending: newest first)
            return yearGroups
                .map { (year: $0.key, count: $0.value.count, sessionIds: $0.value) }
                .sorted { $0.year > $1.year }
        }
    }
    
    // MARK: - Session Metadata CRUD
    
    /// Insert or update session metadata
    public func upsertSessionMetadata(_ metadata: SessionMetadata) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                INSERT INTO session_metadata (session_id, title, notes, is_favorite, category, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(session_id) DO UPDATE SET
                    title = excluded.title,
                    notes = excluded.notes,
                    is_favorite = excluded.is_favorite,
                    category = excluded.category,
                    updated_at = excluded.updated_at
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, metadata.sessionId.uuidString, -1, SQLITE_TRANSIENT)
            
            if let title = metadata.title {
                sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            
            if let notes = metadata.notes {
                sqlite3_bind_text(stmt, 3, notes, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            
            sqlite3_bind_int(stmt, 4, metadata.isFavorite ? 1 : 0)
            
            if let category = metadata.category {
                sqlite3_bind_text(stmt, 5, category.rawValue, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            
            sqlite3_bind_double(stmt, 6, metadata.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 7, metadata.updatedAt.timeIntervalSince1970)
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(await connection.lastError())
            }
            
            logger.debug("Upserted session metadata for: \(metadata.sessionId)")
        }
    }
    
    /// Fetch session metadata by session ID
    public func fetchSessionMetadata(sessionId: UUID) async throws -> SessionMetadata? {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT session_id, title, notes, is_favorite, category, created_at, updated_at
                FROM session_metadata
                WHERE session_id = ?
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return parseSessionMetadata(from: stmt)
            }
            
            return nil
        }
    }
    
    /// Update session title
    public func updateSessionTitle(sessionId: UUID, title: String?) async throws {
        // First check if metadata exists
        if let existing = try await fetchSessionMetadata(sessionId: sessionId) {
            var updated = existing
            updated.title = title
            updated.updatedAt = Date()
            try await upsertSessionMetadata(updated)
        } else {
            // Create new metadata with just the title
            let metadata = SessionMetadata(sessionId: sessionId, title: title)
            try await upsertSessionMetadata(metadata)
        }
    }
    
    /// Update session notes
    public func updateSessionNotes(sessionId: UUID, notes: String?) async throws {
        if let existing = try await fetchSessionMetadata(sessionId: sessionId) {
            var updated = existing
            updated.notes = notes
            updated.updatedAt = Date()
            try await upsertSessionMetadata(updated)
        } else {
            let metadata = SessionMetadata(sessionId: sessionId, notes: notes)
            try await upsertSessionMetadata(metadata)
        }
    }
    
    /// Toggle session favorite status
    public func toggleSessionFavorite(sessionId: UUID) async throws -> Bool {
        if let existing = try await fetchSessionMetadata(sessionId: sessionId) {
            var updated = existing
            updated.isFavorite = !existing.isFavorite
            updated.updatedAt = Date()
            try await upsertSessionMetadata(updated)
            return updated.isFavorite
        } else {
            let metadata = SessionMetadata(sessionId: sessionId, isFavorite: true)
            try await upsertSessionMetadata(metadata)
            return true
        }
    }
    
    /// Update session category
    public func updateSessionCategory(sessionId: UUID, category: SessionCategory?) async throws {
        if let existing = try await fetchSessionMetadata(sessionId: sessionId) {
            var updated = existing
            updated.category = category
            updated.updatedAt = Date()
            try await upsertSessionMetadata(updated)
        } else {
            let metadata = SessionMetadata(sessionId: sessionId, category: category)
            try await upsertSessionMetadata(metadata)
        }
    }
    
    /// Delete session metadata
    public func deleteSessionMetadata(sessionId: UUID) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = "DELETE FROM session_metadata WHERE session_id = ?"
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(await connection.lastError())
            }
        }
    }
    
    /// Delete all session metadata
    public func deleteAllMetadata() async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = "DELETE FROM session_metadata"
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(await connection.lastError())
            }
        }
    }
    
    // MARK: - Parsing Helpers
    
    nonisolated private func parseAudioChunk(from stmt: OpaquePointer?) throws -> AudioChunk {
        guard let idString = sqlite3_column_text(stmt, 0),
              let fileURLString = sqlite3_column_text(stmt, 1),
              let formatString = sqlite3_column_text(stmt, 4) else {
            throw StorageError.invalidData("Missing required AudioChunk column data")
        }
        
        guard let id = UUID(uuidString: String(cString: idString)),
              let fileURL = URL(string: String(cString: fileURLString)),
              let format = AudioFormat(rawValue: String(cString: formatString)) else {
            throw StorageError.invalidData("Could not parse AudioChunk fields")
        }
        
        let startTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
        let endTime = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let sampleRate = Int(sqlite3_column_int(stmt, 5))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
        
        guard let sessionIdString = sqlite3_column_text(stmt, 7),
              let sessionId = UUID(uuidString: String(cString: sessionIdString)) else {
            throw StorageError.invalidData("Missing required session_id")
        }
        
        let chunkIndex = Int(sqlite3_column_int(stmt, 8))
        
        return AudioChunk(
            id: id,
            fileURL: fileURL,
            startTime: startTime,
            endTime: endTime,
            format: format,
            sampleRate: sampleRate,
            createdAt: createdAt,
            sessionId: sessionId,
            chunkIndex: chunkIndex
        )
    }
    
    nonisolated private func parseSessionMetadata(from stmt: OpaquePointer?) -> SessionMetadata? {
        guard let stmt = stmt else { return nil }
        
        guard let sessionIdCStr = sqlite3_column_text(stmt, 0),
              let sessionId = UUID(uuidString: String(cString: sessionIdCStr)) else {
            return nil
        }
        
        let title: String? = sqlite3_column_type(stmt, 1) != SQLITE_NULL 
            ? String(cString: sqlite3_column_text(stmt, 1))
            : nil
        
        let notes: String? = sqlite3_column_type(stmt, 2) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 2))
            : nil
        
        let isFavorite = sqlite3_column_int(stmt, 3) != 0
        
        let category: SessionCategory? = sqlite3_column_type(stmt, 4) != SQLITE_NULL
            ? SessionCategory(rawValue: String(cString: sqlite3_column_text(stmt, 4)))
            : nil
        
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
        
        return SessionMetadata(
            sessionId: sessionId,
            title: title,
            notes: notes,
            isFavorite: isFavorite,
            category: category,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
