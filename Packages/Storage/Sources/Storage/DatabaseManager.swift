// =============================================================================
// Storage — Database Manager
// =============================================================================
// SQLite database manager with App Group support and thread-safe access.
// Uses raw SQLite3 API for maximum control and zero dependencies.
// =============================================================================

import Foundation
import SQLite3
import SharedModels
import os.log

/// SQLite transient destructor for text binding
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thread-safe SQLite database manager
public actor DatabaseManager {
    private let logger = Logger(subsystem: "com.jsayram.lifewrapped", category: "Storage")
    
    private var db: OpaquePointer?
    private let databaseURL: URL
    private let fileManager = FileManager.default
    
    /// Current database schema version
    private static let currentSchemaVersion = 1
    
    /// Public accessor for database path
    public func getDatabasePath() -> String {
        databaseURL.path
    }
    
    // MARK: - Initialization
    
    public init(containerIdentifier: String = AppConstants.appGroupIdentifier) async throws {
        // Get App Group container for sharing with widgets/watch
        print("💾 [DatabaseManager] Looking for App Group: \(containerIdentifier)")
        let containerURL: URL
        if let appGroupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: containerIdentifier
        ) {
            containerURL = appGroupURL
            print("✅ [DatabaseManager] App Group found: \(containerURL.path)")
        } else {
            // Fallback to Documents directory for simulator/development
            print("⚠️ [DatabaseManager] App Group not available, using Documents directory as fallback")
            guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                print("❌ [DatabaseManager] Documents directory not available")
                throw StorageError.appGroupContainerNotFound(containerIdentifier)
            }
            containerURL = documentsURL
            print("✅ [DatabaseManager] Using Documents directory: \(containerURL.path)")
        }
        
        // Create database directory if needed
        let databaseDirectory = containerURL.appendingPathComponent("Database", isDirectory: true)
        print("💾 [DatabaseManager] Creating database directory...")
        try fileManager.createDirectory(
            at: databaseDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        print("✅ [DatabaseManager] Database directory created")
        
        self.databaseURL = databaseDirectory.appendingPathComponent(AppConstants.databaseFilename)
        
        logger.info("Database path: \(self.databaseURL.path)")
        print("💾 [DatabaseManager] Database path: \(self.databaseURL.path)")
        
        // Open database connection
        print("💾 [DatabaseManager] Opening database connection...")
        try openDatabase()
        print("✅ [DatabaseManager] Database opened")
        
        // Run migrations
        print("💾 [DatabaseManager] Running migrations...")
        try migrate()
        print("✅ [DatabaseManager] Migrations complete")
    }
    
    /// Close the database connection
    public func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }
    
    deinit {
        // Note: In production, call close() explicitly before letting the actor deallocate
        // deinit can't access actor-isolated state in Swift 6
    }
    
    // MARK: - Database Connection
    
    private func openDatabase() throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        
        if sqlite3_open_v2(databaseURL.path, &db, flags, nil) != SQLITE_OK {
            throw StorageError.databaseOpenFailed(databaseURL.path)
        }
        
        // Enable foreign keys
        try execute("PRAGMA foreign_keys = ON")
        
        // Set journal mode to WAL for better concurrency
        try execute("PRAGMA journal_mode = WAL")
        
        // Optimize for performance
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA temp_store = MEMORY")
        try execute("PRAGMA cache_size = -64000") // 64MB cache
        
        logger.info("Database opened successfully")
    }
    
    // MARK: - Migrations
    
    private func migrate() throws {
        let currentVersion = try getUserVersion()
        logger.info("Current schema version: \(currentVersion)")
        
        if currentVersion < Self.currentSchemaVersion {
            logger.info("Running migrations from v\(currentVersion) to v\(Self.currentSchemaVersion)")
            try runMigrations(from: currentVersion, to: Self.currentSchemaVersion)
        }
    }
    
    private func getUserVersion() throws -> Int {
        var version: Int32 = 0
        let sql = "PRAGMA user_version"
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            version = sqlite3_column_int(stmt, 0)
        }
        
        return Int(version)
    }
    
    private func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }
    
    private func runMigrations(from: Int, to: Int) throws {
        for version in (from + 1)...to {
            logger.info("🔄 [DatabaseManager] Starting migration v\(version)")
            
            // Begin transaction for atomic migration
            try execute("BEGIN TRANSACTION")
            logger.info("📝 [DatabaseManager] Transaction started for v\(version)")
            
            do {
                switch version {
                case 1:
                    try applySchema()
                default:
                    throw StorageError.unknownMigrationVersion(version)
                }
                
                try setUserVersion(version)
                
                // Commit transaction
                try execute("COMMIT")
                logger.info("✅ [DatabaseManager] Migration v\(version) completed and committed")
            } catch {
                // Rollback on any error
                try? execute("ROLLBACK")
                logger.error("❌ [DatabaseManager] Migration v\(version) failed, rolled back: \(error.localizedDescription)")
                throw error
            }
        }
    }
    
    // MARK: - Database Schema (V1 - Greenfield)
    
    /// Complete database schema for Life Wrapped V1
    private func applySchema() throws {
        // Audio chunks table
        try execute("""
            CREATE TABLE IF NOT EXISTS audio_chunks (
                id TEXT PRIMARY KEY NOT NULL,
                file_url TEXT NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                format TEXT NOT NULL,
                sample_rate INTEGER NOT NULL,
                created_at REAL NOT NULL,
                session_id TEXT NOT NULL,
                chunk_index INTEGER NOT NULL DEFAULT 0
            )
            """)
        
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_audio_chunks_start_time
            ON audio_chunks(start_time)
            """)
        
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_audio_chunks_session
            ON audio_chunks(session_id, chunk_index)
            """)
        
        // Transcript segments table
        try execute("""
            CREATE TABLE IF NOT EXISTS transcript_segments (
                id TEXT PRIMARY KEY NOT NULL,
                audio_chunk_id TEXT NOT NULL,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                text TEXT NOT NULL,
                confidence REAL NOT NULL,
                language_code TEXT NOT NULL,
                created_at REAL NOT NULL,
                speaker_label TEXT,
                entities_json TEXT,
                word_count INTEGER NOT NULL DEFAULT 0,
                sentiment_score REAL,
                FOREIGN KEY (audio_chunk_id) REFERENCES audio_chunks(id) ON DELETE CASCADE
            )
            """)
        
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_transcript_segments_audio_chunk_id
            ON transcript_segments(audio_chunk_id)
            """)
        
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_transcript_segments_created_at
            ON transcript_segments(created_at)
            """)
        
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_transcript_segments_sentiment
            ON transcript_segments(sentiment_score)
            """)
        
        // Summaries table (includes session_id for session-level summaries)
        try execute("""
            CREATE TABLE IF NOT EXISTS summaries (
                id TEXT PRIMARY KEY NOT NULL,
                period_type TEXT NOT NULL,
                period_start REAL NOT NULL,
                period_end REAL NOT NULL,
                text TEXT NOT NULL,
                created_at REAL NOT NULL,
                session_id TEXT,
                topics_json TEXT,
                entities_json TEXT,
                engine_tier TEXT
            )
            """)
        
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_summaries_period
            ON summaries(period_type, period_start, period_end)
            """)
        
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_summaries_session
            ON summaries(session_id)
            """)
        
        // Session metadata table (titles, notes, favorites)
        try execute("""
            CREATE TABLE IF NOT EXISTS session_metadata (
                session_id TEXT PRIMARY KEY,
                title TEXT,
                notes TEXT,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """)
        
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_session_metadata_favorite
            ON session_metadata(is_favorite)
            """)
        
        // Insights rollups table
        try execute("""
            CREATE TABLE IF NOT EXISTS insights_rollups (
                id TEXT PRIMARY KEY NOT NULL,
                bucket_type TEXT NOT NULL,
                bucket_start REAL NOT NULL,
                bucket_end REAL NOT NULL,
                word_count INTEGER NOT NULL,
                speaking_seconds REAL NOT NULL,
                segment_count INTEGER NOT NULL,
                created_at REAL NOT NULL
            )
            """)
        
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_insights_rollups_bucket
            ON insights_rollups(bucket_type, bucket_start, bucket_end)
            """)
        
        // Control events table
        try execute("""
            CREATE TABLE IF NOT EXISTS control_events (
                id TEXT PRIMARY KEY NOT NULL,
                timestamp REAL NOT NULL,
                source TEXT NOT NULL,
                type TEXT NOT NULL,
                payload_json TEXT
            )
            """)
        
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_control_events_timestamp
            ON control_events(timestamp)
            """)
        
        logger.info("✅ Database schema V1 created successfully")
    }
    
    // MARK: - Utilities
    
    private func execute(_ sql: String) throws {
        var errorMsg: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorMsg) }
        
        if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
            let error = errorMsg.map { String(cString: $0) } ?? "Unknown error"
            throw StorageError.executionFailed(error)
        }
    }
    
    /// Get the last error message from SQLite
    private func lastError() -> String {
        guard let db = db else { return "Database not open" }
        return String(cString: sqlite3_errmsg(db))
    }
    
    // MARK: - AudioChunk CRUD
    
    public func insertAudioChunk(_ chunk: AudioChunk) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            INSERT INTO audio_chunks (id, file_url, start_time, end_time, format, sample_rate, created_at, session_id, chunk_index)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, chunk.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, chunk.fileURL.absoluteString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, chunk.startTime.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 4, chunk.endTime.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 5, chunk.format.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 6, Int32(chunk.sampleRate))
        sqlite3_bind_double(stmt, 7, chunk.createdAt.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 8, chunk.sessionId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 9, Int32(chunk.chunkIndex))
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
    }
    
    public func fetchAudioChunk(id: UUID) throws -> AudioChunk? {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            SELECT id, file_url, start_time, end_time, format, sample_rate, created_at, session_id, chunk_index
            FROM audio_chunks
            WHERE id = ?
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return try parseAudioChunk(from: stmt)
        }
        
        return nil
    }
    
    public func fetchAllAudioChunks(limit: Int? = nil, offset: Int = 0) throws -> [AudioChunk] {
        guard let db = db else { throw StorageError.notOpen }
        
        var sql = """
            SELECT id, file_url, start_time, end_time, format, sample_rate, created_at, session_id, chunk_index
            FROM audio_chunks
            ORDER BY start_time DESC
            """
        
        if let limit = limit {
            sql += " LIMIT \(limit) OFFSET \(offset)"
        }
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        var chunks: [AudioChunk] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chunk = try parseAudioChunk(from: stmt)
            chunks.append(chunk)
        }
        
        return chunks
    }
    
    /// Fetch recent audio chunks (convenience method)
    public func fetchRecentAudioChunks(limit: Int = 50) throws -> [AudioChunk] {
        return try fetchAllAudioChunks(limit: limit)
    }
    
    public func deleteAudioChunk(id: UUID) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = "DELETE FROM audio_chunks WHERE id = ?"
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
    }
    
    // MARK: - Session Queries
    
    /// Fetch all chunks belonging to a session, ordered by chunk_index
    public func fetchChunksBySession(sessionId: UUID) throws -> [AudioChunk] {
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
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
        
        var chunks: [AudioChunk] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            chunks.append(try parseAudioChunk(from: stmt))
        }
        
        return chunks
    }
    
    /// Fetch all unique sessions with their first chunk's timestamp
    public func fetchSessions(limit: Int = 100) throws -> [(sessionId: UUID, firstChunkTime: Date, chunkCount: Int)] {
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
            throw StorageError.prepareFailed(lastError())
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
    
    // MARK: - Analytics Queries
    
    /// Fetch session counts grouped by hour of day (0-23)
    /// Returns array of (hour, count, sessionIds) for each hour that has sessions
    public func fetchSessionsByHour() throws -> [(hour: Int, count: Int, sessionIds: [UUID])] {
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
            throw StorageError.prepareFailed(lastError())
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
    
    /// Fetch the longest recording session by total duration
    /// Returns (sessionId, duration, date) or nil if no sessions exist
    public func fetchLongestSession() throws -> (sessionId: UUID, duration: TimeInterval, date: Date)? {
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
            throw StorageError.prepareFailed(lastError())
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
    
    /// Fetch the most active month by session count
    /// Returns (year, month, count, sessionIds) or nil if no sessions exist
    public func fetchMostActiveMonth() throws -> (year: Int, month: Int, count: Int, sessionIds: [UUID])? {
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
            throw StorageError.prepareFailed(lastError())
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
    
    /// Fetch all transcript text within a date range
    public func fetchTranscriptText(startDate: Date, endDate: Date) throws -> [String] {
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
            throw StorageError.prepareFailed(lastError())
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
    
    /// Fetch session counts grouped by day of week (0 = Sunday, 6 = Saturday)
    public func fetchSessionsByDayOfWeek() throws -> [(dayOfWeek: Int, count: Int, sessionIds: [UUID])] {
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
            throw StorageError.prepareFailed(lastError())
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
    
    /// Delete an entire session (all chunks)
    public func deleteSession(sessionId: UUID) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        // Cascade delete will handle transcript_segments via FK
        let sql = "DELETE FROM audio_chunks WHERE session_id = ?"
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
    }
    
    private func parseAudioChunk(from stmt: OpaquePointer?) throws -> AudioChunk {
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
        
        // Parse session fields (columns 7 and 8)
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
    
    // MARK: - TranscriptSegment CRUD
    
    public func insertTranscriptSegment(_ segment: TranscriptSegment) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            INSERT INTO transcript_segments 
            (id, audio_chunk_id, start_time, end_time, text, confidence, language_code, created_at, speaker_label, entities_json, word_count, sentiment_score)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
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
            throw StorageError.stepFailed(lastError())
        }
    }
    
    public func fetchTranscriptSegment(id: UUID) throws -> TranscriptSegment? {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            SELECT id, audio_chunk_id, start_time, end_time, text, confidence, language_code, created_at, speaker_label, entities_json, word_count
            FROM transcript_segments
            WHERE id = ?
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return try parseTranscriptSegment(from: stmt)
        }
        
        return nil
    }
    
    public func fetchTranscriptSegments(audioChunkID: UUID) throws -> [TranscriptSegment] {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            SELECT id, audio_chunk_id, start_time, end_time, text, confidence, language_code, created_at, speaker_label, entities_json, word_count
            FROM transcript_segments
            WHERE audio_chunk_id = ?
            ORDER BY start_time ASC
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, audioChunkID.uuidString, -1, SQLITE_TRANSIENT)
        
        var segments: [TranscriptSegment] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            segments.append(try parseTranscriptSegment(from: stmt))
        }
        
        return segments
    }
    
    public func deleteTranscriptSegment(id: UUID) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = "DELETE FROM transcript_segments WHERE id = ?"
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
    }
    
    /// Update transcript segment text (for user edits)
    /// Also recalculates word count automatically
    public func updateTranscriptSegmentText(id: UUID, newText: String) throws {
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
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, newText, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(wordCount))
        sqlite3_bind_text(stmt, 3, id.uuidString, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
        
        logger.debug("Updated transcript segment \(id) text, new word count: \(wordCount)")
    }

    /// Check if all chunks in a session have been transcribed
    public func isSessionTranscriptionComplete(sessionId: UUID) throws -> Bool {
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
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let totalChunks = sqlite3_column_int(stmt, 0)
            let transcribedChunks = sqlite3_column_int(stmt, 1)
            return totalChunks == transcribedChunks && totalChunks > 0
        }
        
        return false
    }
    
    public func getTranscriptSegments(from startDate: Date, to endDate: Date) throws -> [TranscriptSegment] {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
        SELECT ts.* FROM transcript_segments ts
        INNER JOIN audio_chunks ac ON ts.audio_chunk_id = ac.id
        WHERE ac.start_time >= ? AND ac.start_time < ?
        ORDER BY ac.start_time ASC, ts.start_time ASC
        """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_double(stmt, 1, startDate.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, endDate.timeIntervalSince1970)
        
        var segments: [TranscriptSegment] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            segments.append(try parseTranscriptSegment(from: stmt))
        }
        
        return segments
    }
    
    /// Efficiently get total word count for a session
    public func fetchSessionWordCount(sessionId: UUID) throws -> Int {
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
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        
        return 0
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
    
    // MARK: - Sentiment Analytics
    
    /// Fetch average sentiment score for a specific session
    public func fetchSessionSentiment(sessionId: UUID) throws -> Double? {
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
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            if sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                return sqlite3_column_double(stmt, 0)
            }
        }
        
        return nil
    }
    
    /// Fetch daily average sentiment scores for date range
    public func fetchDailySentiment(from startDate: Date, to endDate: Date) throws -> [(date: Date, sentiment: Double)] {
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
            throw StorageError.prepareFailed(lastError())
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
    
    /// Fetch language distribution from all transcript segments
    public func fetchLanguageDistribution() throws -> [(language: String, wordCount: Int)] {
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
            throw StorageError.prepareFailed(lastError())
        }
        
        var results: [(String, Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let language = String(cString: sqlite3_column_text(stmt, 0))
            let wordCount = Int(sqlite3_column_int64(stmt, 1))
            results.append((language, wordCount))
        }
        
        return results
    }
    
    /// Fetch dominant language for a specific session
    public func fetchSessionLanguage(sessionId: UUID) throws -> String? {
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
            throw StorageError.prepareFailed(lastError())
        }
        
        let sessionIdString = sessionId.uuidString
        sqlite3_bind_text(stmt, 1, (sessionIdString as NSString).utf8String, -1, nil)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return String(cString: sqlite3_column_text(stmt, 0))
        }
        
        return nil
    }
    
    // MARK: - Session Metadata CRUD
    
    /// Session metadata model for title, notes, favorites
    public struct SessionMetadata: Sendable {
        public let sessionId: UUID
        public var title: String?
        public var notes: String?
        public var isFavorite: Bool
        public let createdAt: Date
        public var updatedAt: Date
        
        public init(sessionId: UUID, title: String? = nil, notes: String? = nil, isFavorite: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
            self.sessionId = sessionId
            self.title = title
            self.notes = notes
            self.isFavorite = isFavorite
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
    
    /// Insert or update session metadata
    public func upsertSessionMetadata(_ metadata: SessionMetadata) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            INSERT INTO session_metadata (session_id, title, notes, is_favorite, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET
                title = excluded.title,
                notes = excluded.notes,
                is_favorite = excluded.is_favorite,
                updated_at = excluded.updated_at
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
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
        sqlite3_bind_double(stmt, 5, metadata.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 6, metadata.updatedAt.timeIntervalSince1970)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
        
        logger.debug("Upserted session metadata for: \(metadata.sessionId)")
    }
    
    /// Fetch session metadata by session ID
    public func fetchSessionMetadata(sessionId: UUID) throws -> SessionMetadata? {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            SELECT session_id, title, notes, is_favorite, created_at, updated_at
            FROM session_metadata
            WHERE session_id = ?
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return parseSessionMetadata(from: stmt)
        }
        
        return nil
    }
    
    /// Update session title
    public func updateSessionTitle(sessionId: UUID, title: String?) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        // First check if metadata exists
        if let existing = try fetchSessionMetadata(sessionId: sessionId) {
            var updated = existing
            updated.title = title
            updated.updatedAt = Date()
            try upsertSessionMetadata(updated)
        } else {
            // Create new metadata with just the title
            let metadata = SessionMetadata(sessionId: sessionId, title: title)
            try upsertSessionMetadata(metadata)
        }
    }
    
    /// Update session notes
    public func updateSessionNotes(sessionId: UUID, notes: String?) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        if let existing = try fetchSessionMetadata(sessionId: sessionId) {
            var updated = existing
            updated.notes = notes
            updated.updatedAt = Date()
            try upsertSessionMetadata(updated)
        } else {
            let metadata = SessionMetadata(sessionId: sessionId, notes: notes)
            try upsertSessionMetadata(metadata)
        }
    }
    
    /// Toggle session favorite status
    public func toggleSessionFavorite(sessionId: UUID) throws -> Bool {
        guard let db = db else { throw StorageError.notOpen }
        
        if let existing = try fetchSessionMetadata(sessionId: sessionId) {
            var updated = existing
            updated.isFavorite = !existing.isFavorite
            updated.updatedAt = Date()
            try upsertSessionMetadata(updated)
            return updated.isFavorite
        } else {
            let metadata = SessionMetadata(sessionId: sessionId, isFavorite: true)
            try upsertSessionMetadata(metadata)
            return true
        }
    }
    
    /// Delete session metadata
    public func deleteSessionMetadata(sessionId: UUID) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = "DELETE FROM session_metadata WHERE session_id = ?"
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
    }
    
    /// Parse session metadata from SQLite statement
    private func parseSessionMetadata(from stmt: OpaquePointer?) -> SessionMetadata? {
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
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
        
        return SessionMetadata(
            sessionId: sessionId,
            title: title,
            notes: notes,
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    
    // MARK: - Summary CRUD
    
    public func insertSummary(_ summary: Summary) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            INSERT INTO summaries (id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, summary.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, summary.periodType.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, summary.periodStart.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 4, summary.periodEnd.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 5, summary.text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 6, summary.createdAt.timeIntervalSince1970)
        
        if let sessionId = summary.sessionId {
            sqlite3_bind_text(stmt, 7, sessionId.uuidString, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        
        if let topicsJSON = summary.topicsJSON {
            sqlite3_bind_text(stmt, 8, topicsJSON, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        
        if let entitiesJSON = summary.entitiesJSON {
            sqlite3_bind_text(stmt, 9, entitiesJSON, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        
        if let engineTier = summary.engineTier {
            sqlite3_bind_text(stmt, 10, engineTier, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 10)
        }
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
    }
    
    public func fetchSummary(id: UUID) throws -> Summary? {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            SELECT id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier
            FROM summaries
            WHERE id = ?
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return try parseSummary(from: stmt)
        }
        
        return nil
    }
    
    public func fetchSummaries(periodType: PeriodType? = nil, limit: Int = 100) throws -> [Summary] {
        guard let db = db else { throw StorageError.notOpen }
        
        var sql = """
            SELECT id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier
            FROM summaries
            """
        
        if periodType != nil {
            sql += " WHERE period_type = ?"
        }
        
        sql += " ORDER BY period_start DESC LIMIT \(limit)"
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        if let periodType = periodType {
            sqlite3_bind_text(stmt, 1, periodType.rawValue, -1, SQLITE_TRANSIENT)
        }
        
        var summaries: [Summary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            summaries.append(try parseSummary(from: stmt))
        }
        
        return summaries
    }
    
    /// Fetch all summaries (convenience method for export)
    public func fetchAllSummaries() throws -> [Summary] {
        return try fetchSummaries(periodType: nil, limit: 10000)
    }
    
    /// Fetch summary for a specific session
    public func fetchSummaryForSession(sessionId: UUID) throws -> Summary? {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            SELECT id, period_type, period_start, period_end, text, created_at, session_id
            FROM summaries
            WHERE session_id = ?
            ORDER BY created_at DESC
            LIMIT 1
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return try parseSummary(from: stmt)
        }
        
        return nil
    }
    
    /// Fetch period summary for a specific date and type
    public func fetchPeriodSummary(type: PeriodType, date: Date) throws -> Summary? {
        guard let db = db else { throw StorageError.notOpen }
        
        // For week/month, find the summary where the date falls within the period range
        // For day, match the exact day
        let sql = """
            SELECT id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier
            FROM summaries
            WHERE period_type = ?
            AND ? >= period_start
            AND ? < period_end
            AND session_id IS NULL
            LIMIT 1
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, type.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 3, date.timeIntervalSince1970)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return try parseSummary(from: stmt)
        }
        
        return nil
    }
    
    /// Upsert (insert or update) a period summary
    public func upsertPeriodSummary(type: PeriodType, text: String, start: Date, end: Date) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        // Check if summary exists
        if let existing = try fetchPeriodSummary(type: type, date: start) {
            // Update existing
            let sql = """
                UPDATE summaries
                SET text = ?, period_end = ?
                WHERE id = ?
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(lastError())
            }
            
            sqlite3_bind_text(stmt, 1, text, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, end.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, existing.id.uuidString, -1, SQLITE_TRANSIENT)
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(lastError())
            }
        } else {
            // Insert new
            let summary = Summary(
                id: UUID(),
                periodType: type,
                periodStart: start,
                periodEnd: end,
                text: text,
                createdAt: start,
                sessionId: nil
            )
            try insertSummary(summary)
        }
    }
    
    /// Fetch all sessions for a specific date
    public func fetchSessionsByDate(date: Date) throws -> [RecordingSession] {
        guard let db = db else { throw StorageError.notOpen }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Get all session IDs for this date
        let sql = """
            SELECT session_id
            FROM audio_chunks
            WHERE start_time >= ? AND start_time < ?
            GROUP BY session_id
            ORDER BY MIN(start_time) ASC
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_double(stmt, 1, startOfDay.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, endOfDay.timeIntervalSince1970)
        
        var sessionIds: [UUID] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sessionIdString = String(cString: sqlite3_column_text(stmt, 0))
            if let sessionId = UUID(uuidString: sessionIdString) {
                sessionIds.append(sessionId)
            }
        }
        
        // Fetch full sessions with chunks and metadata
        var sessions: [RecordingSession] = []
        for sessionId in sessionIds {
            let chunks = try fetchChunksBySession(sessionId: sessionId)
            if !chunks.isEmpty {
                let metadata = try fetchSessionMetadata(sessionId: sessionId)
                let session = RecordingSession(
                    sessionId: sessionId, 
                    chunks: chunks,
                    title: metadata?.title,
                    notes: metadata?.notes,
                    isFavorite: metadata?.isFavorite ?? false
                )
                sessions.append(session)
            }
        }
        
        return sessions
    }
    
    /// Fetch all daily summaries for a date range
    public func fetchDailySummaries(from startDate: Date, to endDate: Date) throws -> [Summary] {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            SELECT id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier
            FROM summaries
            WHERE period_type = 'day'
            AND period_start >= ? AND period_start < ?
            AND session_id IS NULL
            ORDER BY period_start ASC
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_double(stmt, 1, startDate.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, endDate.timeIntervalSince1970)
        
        var summaries: [Summary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let summary = try? parseSummary(from: stmt) {
                summaries.append(summary)
            }
        }
        
        return summaries
    }
    
    public func deleteSummary(id: UUID) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = "DELETE FROM summaries WHERE id = ?"
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
    }
    
    private func parseSummary(from stmt: OpaquePointer?) throws -> Summary {
        guard let idString = sqlite3_column_text(stmt, 0),
              let periodTypeString = sqlite3_column_text(stmt, 1),
              let textString = sqlite3_column_text(stmt, 4) else {
            throw StorageError.invalidData("Missing required Summary column data")
        }
        
        guard let id = UUID(uuidString: String(cString: idString)),
              let periodType = PeriodType(rawValue: String(cString: periodTypeString)) else {
            throw StorageError.invalidData("Could not parse Summary fields")
        }
        
        let periodStart = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
        let periodEnd = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let text = String(cString: textString)
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
        
        // Parse optional session_id
        let sessionId: UUID?
        if let sessionIdText = sqlite3_column_text(stmt, 6) {
            sessionId = UUID(uuidString: String(cString: sessionIdText))
        } else {
            sessionId = nil
        }
        
        // Parse optional topics_json
        let topicsJSON: String?
        if let topicsText = sqlite3_column_text(stmt, 7) {
            topicsJSON = String(cString: topicsText)
        } else {
            topicsJSON = nil
        }
        
        // Parse optional entities_json
        let entitiesJSON: String?
        if let entitiesText = sqlite3_column_text(stmt, 8) {
            entitiesJSON = String(cString: entitiesText)
        } else {
            entitiesJSON = nil
        }
        
        // Parse optional engine_tier
        let engineTier: String?
        if let engineText = sqlite3_column_text(stmt, 9) {
            engineTier = String(cString: engineText)
        } else {
            engineTier = nil
        }
        
        return Summary(
            id: id,
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            text: text,
            createdAt: createdAt,
            sessionId: sessionId,
            topicsJSON: topicsJSON,
            entitiesJSON: entitiesJSON,
            engineTier: engineTier
        )
    }
    
    // MARK: - InsightsRollup CRUD
    
    public func insertRollup(_ rollup: InsightsRollup) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        // Delete any existing rollup for the same bucket_type and bucket_start
        let deleteSql = """
            DELETE FROM insights_rollups 
            WHERE bucket_type = ? AND bucket_start = ?
            """
        
        var deleteStmt: OpaquePointer?
        defer { sqlite3_finalize(deleteStmt) }
        
        if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStmt, 1, rollup.bucketType.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(deleteStmt, 2, rollup.bucketStart.timeIntervalSince1970)
            _ = sqlite3_step(deleteStmt)
        }
        
        // Now insert the new rollup
        let sql = """
            INSERT INTO insights_rollups (id, bucket_type, bucket_start, bucket_end, word_count, speaking_seconds, segment_count, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, rollup.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, rollup.bucketType.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, rollup.bucketStart.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 4, rollup.bucketEnd.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 5, Int32(rollup.wordCount))
        sqlite3_bind_double(stmt, 6, rollup.speakingSeconds)
        sqlite3_bind_int(stmt, 7, Int32(rollup.segmentCount))
        sqlite3_bind_double(stmt, 8, rollup.createdAt.timeIntervalSince1970)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
    }
    
    public func fetchRollup(id: UUID) throws -> InsightsRollup? {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            SELECT id, bucket_type, bucket_start, bucket_end, word_count, speaking_seconds, segment_count, created_at
            FROM insights_rollups
            WHERE id = ?
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return try parseRollup(from: stmt)
        }
        
        return nil
    }
    
    public func fetchRollups(bucketType: PeriodType? = nil, limit: Int = 100) throws -> [InsightsRollup] {
        guard let db = db else { throw StorageError.notOpen }
        
        var sql = """
            SELECT id, bucket_type, bucket_start, bucket_end, word_count, speaking_seconds, segment_count, created_at
            FROM insights_rollups
            """
        
        if bucketType != nil {
            sql += " WHERE bucket_type = ?"
        }
        
        sql += " ORDER BY bucket_start DESC LIMIT \(limit)"
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        if let bucketType = bucketType {
            sqlite3_bind_text(stmt, 1, bucketType.rawValue, -1, SQLITE_TRANSIENT)
        }
        
        var rollups: [InsightsRollup] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rollups.append(try parseRollup(from: stmt))
        }
        
        return rollups
    }
    
    /// Fetch rollup for a specific date range
    public func fetchRollup(bucketType: PeriodType, bucketStart: Date) throws -> InsightsRollup? {
        guard let db = db else { throw StorageError.notOpen }
        
        // Calculate end of the period based on bucket type
        let calendar = Calendar.current
        let bucketEnd: Date
        switch bucketType {
        case .session:
            // Session rollups are not used, but handle for completeness
            bucketEnd = calendar.date(byAdding: .hour, value: 1, to: bucketStart) ?? bucketStart
        case .hour:
            bucketEnd = calendar.date(byAdding: .hour, value: 1, to: bucketStart) ?? bucketStart
        case .day:
            bucketEnd = calendar.date(byAdding: .day, value: 1, to: bucketStart) ?? bucketStart
        case .week:
            bucketEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: bucketStart) ?? bucketStart
        case .month:
            bucketEnd = calendar.date(byAdding: .month, value: 1, to: bucketStart) ?? bucketStart
        }
        
        let sql = """
            SELECT id, bucket_type, bucket_start, bucket_end, word_count, speaking_seconds, segment_count, created_at
            FROM insights_rollups
            WHERE bucket_type = ? AND bucket_start >= ? AND bucket_start < ?
            LIMIT 1
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, bucketType.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, bucketStart.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 3, bucketEnd.timeIntervalSince1970)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return try parseRollup(from: stmt)
        }
        
        return nil
    }
    
    public func deleteRollup(id: UUID) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = "DELETE FROM insights_rollups WHERE id = ?"
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
    }
    
    private func parseRollup(from stmt: OpaquePointer?) throws -> InsightsRollup {
        guard let idString = sqlite3_column_text(stmt, 0),
              let bucketTypeString = sqlite3_column_text(stmt, 1) else {
            throw StorageError.invalidData("Missing required InsightsRollup column data")
        }
        
        guard let id = UUID(uuidString: String(cString: idString)),
              let bucketType = PeriodType(rawValue: String(cString: bucketTypeString)) else {
            throw StorageError.invalidData("Could not parse InsightsRollup fields")
        }
        
        let bucketStart = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
        let bucketEnd = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let wordCount = Int(sqlite3_column_int(stmt, 4))
        let speakingSeconds = sqlite3_column_double(stmt, 5)
        let segmentCount = Int(sqlite3_column_int(stmt, 6))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
        
        return InsightsRollup(
            id: id,
            bucketType: bucketType,
            bucketStart: bucketStart,
            bucketEnd: bucketEnd,
            wordCount: wordCount,
            speakingSeconds: speakingSeconds,
            segmentCount: segmentCount,
            createdAt: createdAt
        )
    }
    
    // MARK: - ControlEvent CRUD
    
    public func insertEvent(_ event: ControlEvent) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            INSERT INTO control_events (id, timestamp, source, type, payload_json)
            VALUES (?, ?, ?, ?, ?)
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, event.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, event.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, event.source.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, event.type.rawValue, -1, SQLITE_TRANSIENT)
        
        if let payload = event.payloadJSON {
            sqlite3_bind_text(stmt, 5, payload, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
    }
    
    public func fetchEvent(id: UUID) throws -> ControlEvent? {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            SELECT id, timestamp, source, type, payload_json
            FROM control_events
            WHERE id = ?
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return try parseEvent(from: stmt)
        }
        
        return nil
    }
    
    public func fetchEvents(limit: Int = 100) throws -> [ControlEvent] {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            SELECT id, timestamp, source, type, payload_json
            FROM control_events
            ORDER BY timestamp DESC
            LIMIT \(limit)
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        var events: [ControlEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            events.append(try parseEvent(from: stmt))
        }
        
        return events
    }
    
    public func deleteEvent(id: UUID) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = "DELETE FROM control_events WHERE id = ?"
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(lastError())
        }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
    }
    
    private func parseEvent(from stmt: OpaquePointer?) throws -> ControlEvent {
        guard let idString = sqlite3_column_text(stmt, 0),
              let sourceString = sqlite3_column_text(stmt, 2),
              let typeString = sqlite3_column_text(stmt, 3) else {
            throw StorageError.invalidData("Missing required ControlEvent column data")
        }
        
        guard let id = UUID(uuidString: String(cString: idString)),
              let source = EventSource(rawValue: String(cString: sourceString)),
              let type = EventType(rawValue: String(cString: typeString)) else {
            throw StorageError.invalidData("Could not parse ControlEvent fields")
        }
        
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
        
        let payloadJSON: String?
        if let payloadText = sqlite3_column_text(stmt, 4) {
            payloadJSON = String(cString: payloadText)
        } else {
            payloadJSON = nil
        }
        
        return ControlEvent(
            id: id,
            timestamp: timestamp,
            source: source,
            type: type,
            payloadJSON: payloadJSON
        )
    }
}
