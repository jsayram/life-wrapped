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
    
    // MARK: - Initialization
    
    public init(containerIdentifier: String = AppConstants.appGroupIdentifier) async throws {
        // Get App Group container for sharing with widgets/watch
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: containerIdentifier
        ) else {
            throw StorageError.appGroupContainerNotFound(containerIdentifier)
        }
        
        // Create database directory if needed
        let databaseDirectory = containerURL.appendingPathComponent("Database", isDirectory: true)
        try fileManager.createDirectory(
            at: databaseDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        
        self.databaseURL = databaseDirectory.appendingPathComponent(AppConstants.databaseFilename)
        
        logger.info("Database path: \(self.databaseURL.path)")
        
        // Open database connection
        try openDatabase()
        
        // Run migrations
        try migrate()
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
            logger.info("Applying migration v\(version)")
            
            switch version {
            case 1:
                try applyMigrationV1()
            default:
                throw StorageError.unknownMigrationVersion(version)
            }
            
            try setUserVersion(version)
            logger.info("Migration v\(version) completed")
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
                created_at REAL NOT NULL
            )
            """)
        
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_audio_chunks_start_time
            ON audio_chunks(start_time)
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
            INSERT INTO audio_chunks (id, file_url, start_time, end_time, format, sample_rate, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
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
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.stepFailed(lastError())
        }
    }
    
    public func fetchAudioChunk(id: UUID) throws -> AudioChunk? {
        guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            SELECT id, file_url, start_time, end_time, format, sample_rate, created_at
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
            SELECT id, file_url, start_time, end_time, format, sample_rate, created_at
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
        
        return AudioChunk(
            id: id,
            fileURL: fileURL,
            startTime: startTime,
            endTime: endTime,
            format: format,
            sampleRate: sampleRate,
            createdAt: createdAt
        )
    }
}
