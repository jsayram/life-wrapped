// =============================================================================
// Storage — Schema Manager
// =============================================================================
// Database schema management and migrations.
// =============================================================================

import Foundation
import SQLite3
import os.log

public actor SchemaManager {
    private let logger = Logger(subsystem: "com.jsayram.lifewrapped", category: "Storage")
    private let connection: DatabaseConnection
    
    /// Current database schema version
    private static let currentSchemaVersion = 1
    
    public init(connection: DatabaseConnection) {
        self.connection = connection
    }
    
    /// Run migrations if needed
    public func migrate() async throws {
        let currentVersion = try await getUserVersion()
        logger.info("Current schema version: \(currentVersion)")
        
        if currentVersion < Self.currentSchemaVersion {
            logger.info("Running migrations from v\(currentVersion) to v\(Self.currentSchemaVersion)")
            try await runMigrations(from: currentVersion, to: Self.currentSchemaVersion)
        }
    }
    
    private func getUserVersion() async throws -> Int {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
        
            var version: Int32 = 0
            let sql = "PRAGMA user_version"
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await connection.lastError())
            }
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                version = sqlite3_column_int(stmt, 0)
            }
            
            return Int(version)
        }
    }
    
    private func setUserVersion(_ version: Int) async throws {
        try await connection.execute("PRAGMA user_version = \(version)")
    }
    
    private func runMigrations(from: Int, to: Int) async throws {
        for version in (from + 1)...to {
            logger.info("🔄 [SchemaManager] Starting migration v\(version)")
            
            // Begin transaction for atomic migration
            try await connection.execute("BEGIN TRANSACTION")
            logger.info("📝 [SchemaManager] Transaction started for v\(version)")
            
            do {
                switch version {
                case 1:
                    try await applySchema()
                default:
                    throw StorageError.unknownMigrationVersion(version)
                }
                
                try await setUserVersion(version)
                
                // Commit transaction
                try await connection.execute("COMMIT")
                logger.info("✅ [SchemaManager] Migration v\(version) completed and committed")
            } catch {
                // Rollback on any error
                try? await connection.execute("ROLLBACK")
                logger.error("❌ [SchemaManager] Migration v\(version) failed, rolled back: \(error.localizedDescription)")
                throw error
            }
        }
    }
    
    private func applySchema() async throws {
        // Audio chunks table
        try await connection.execute("""
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
        
        try await connection.execute("""
            CREATE INDEX IF NOT EXISTS idx_audio_chunks_start_time
            ON audio_chunks(start_time)
            """)
        
        try await connection.execute("""
            CREATE INDEX IF NOT EXISTS idx_audio_chunks_session
            ON audio_chunks(session_id, chunk_index)
            """)
        
        // Transcript segments table
        try await connection.execute("""
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
        
        try await connection.execute("""
            CREATE INDEX IF NOT EXISTS idx_transcript_segments_audio_chunk_id
            ON transcript_segments(audio_chunk_id)
            """)
        
        try await connection.execute("""
            CREATE INDEX IF NOT EXISTS idx_transcript_segments_created_at
            ON transcript_segments(created_at)
            """)
        
        try await connection.execute("""
            CREATE INDEX IF NOT EXISTS idx_transcript_segments_sentiment
            ON transcript_segments(sentiment_score)
            """)
        
        // Summaries table
        try await connection.execute("""
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
                engine_tier TEXT,
                source_ids TEXT,
                input_hash TEXT
            )
            """)
        
        try await connection.execute("""
            CREATE INDEX IF NOT EXISTS idx_summaries_period
            ON summaries(period_type, period_start, period_end)
            """)
        
        try await connection.execute("""
            CREATE INDEX IF NOT EXISTS idx_summaries_session
            ON summaries(session_id)
            """)
        
        // Session metadata table
        try await connection.execute("""
            CREATE TABLE IF NOT EXISTS session_metadata (
                session_id TEXT PRIMARY KEY,
                title TEXT,
                notes TEXT,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """)
        
        try await connection.execute("""
            CREATE INDEX IF NOT EXISTS idx_session_metadata_favorite
            ON session_metadata(is_favorite)
            """)
        
        // Insights rollups table
        try await connection.execute("""
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
        
        try await connection.execute("""
            CREATE INDEX IF NOT EXISTS idx_insights_rollups_bucket
            ON insights_rollups(bucket_type, bucket_start, bucket_end)
            """)
        
        // Control events table
        try await connection.execute("""
            CREATE TABLE IF NOT EXISTS control_events (
                id TEXT PRIMARY KEY NOT NULL,
                timestamp REAL NOT NULL,
                source TEXT NOT NULL,
                type TEXT NOT NULL,
                payload_json TEXT
            )
            """)
        
        try await connection.execute("""
            CREATE INDEX IF NOT EXISTS idx_control_events_timestamp
            ON control_events(timestamp)
            """)
        
        logger.info("✅ Database schema V1 created successfully")
    }
}
