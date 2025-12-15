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
    private static let currentSchemaVersion = 2
    
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
                    try applyMigrationV1()
                case 2:
                    try applyMigrationV2()
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
    
    // MARK: - Schema (Migration V1)
    
    private func applyMigrationV1() throws {
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
            CREATE TABLE IF NOT EXISTS summaries (
                id TEXT PRIMARY KEY NOT NULL,
                period_type TEXT NOT NULL,
                period_start REAL NOT NULL,
                period_end REAL NOT NULL,
                text TEXT NOT NULL,
                created_at REAL NOT NULL
            )
            """)
        
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_summaries_period
            ON summaries(period_type, period_start, period_end)
            """)
        
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
        
        logger.info("Schema v1 created successfully")
    }
    
    // MARK: - Schema (Migration V2)
    
    private func applyMigrationV2() throws {
        // Add session_id column to summaries table for session-level summaries
        try execute("""
            ALTER TABLE summaries ADD COLUMN session_id TEXT
            """)
        
        // Create index for session_id lookups
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_summaries_session
            ON summaries(session_id)
            """)
        
        logger.info("Schema v2 applied successfully: Added session_id to summaries")
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
                MIN(created_at) as first_chunk_time,
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
                CAST(strftime('%H', datetime(created_at, 'unixepoch', 'localtime')) AS INTEGER) as hour,
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
            (id, audio_chunk_id, start_time, end_time, text, confidence, language_code, created_at, speaker_label, entities_json, word_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            wordCount: wordCount
        )
    }
    
    // MARK: - Summary CRUD
    
    public func insertSummary(_ summary: Summary) throws {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            INSERT INTO summaries (id, period_type, period_start, period_end, text, created_at, session_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
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
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
    }
    
    public func fetchSummary(id: UUID) throws -> Summary? {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            SELECT id, period_type, period_start, period_end, text, created_at, session_id
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
            SELECT id, period_type, period_start, period_end, text, created_at, session_id
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
        
        return Summary(
            id: id,
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            text: text,
            createdAt: createdAt,
            sessionId: sessionId
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
