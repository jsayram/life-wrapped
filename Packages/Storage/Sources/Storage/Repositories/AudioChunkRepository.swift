// =============================================================================
// Storage — Audio Chunk Repository
// =============================================================================
// CRUD operations for audio chunks.
// =============================================================================

import Foundation
import SQLite3
import SharedModels

public actor AudioChunkRepository {
    private let connection: DatabaseConnection
    
    public init(connection: DatabaseConnection) {
        self.connection = connection
    }
    
    public func insert(_ chunk: AudioChunk) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            INSERT INTO audio_chunks (id, file_url, start_time, end_time, format, sample_rate, created_at, session_id, chunk_index)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(await connection.lastError())
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
            throw StorageError.stepFailed(await connection.lastError())
        }
        }
    }
    
    public func fetch(id: UUID) async throws -> AudioChunk? {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
        
        let sql = """
            SELECT id, file_url, start_time, end_time, format, sample_rate, created_at, session_id, chunk_index
            FROM audio_chunks
            WHERE id = ?
            """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.prepareFailed(await connection.lastError())
        }
        
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        
            if sqlite3_step(stmt) == SQLITE_ROW {
                return try parseAudioChunk(from: stmt)
            }
            
            return nil
        }
    }
    
    public func fetchAll(limit: Int? = nil, offset: Int = 0) async throws -> [AudioChunk] {
        try await connection.withDatabase { db in
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
            throw StorageError.prepareFailed(await connection.lastError())
        }
        
        var chunks: [AudioChunk] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chunk = try parseAudioChunk(from: stmt)
            chunks.append(chunk)
        }
        
        return chunks
        }
    }
    
    public func fetchRecent(limit: Int = 50) async throws -> [AudioChunk] {
        return try await fetchAll(limit: limit)
    }
    
    public func delete(id: UUID) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
        
        let sql = "DELETE FROM audio_chunks WHERE id = ?"
        
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
}
