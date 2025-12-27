// InsightsRepository.swift
// Storage
//
// InsightsRollup CRUD operations

import Foundation
import SharedModels
import SQLite3

/// Repository for InsightsRollup operations - time-based aggregations
public actor InsightsRepository {
    private let connection: DatabaseConnection
    
    public init(connection: DatabaseConnection) {
        self.connection = connection
    }
    
    // MARK: - Insert
    
    /// Insert or replace a rollup (deletes existing rollup for same bucket before inserting)
    public func insert(_ rollup: InsightsRollup) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            // Delete existing rollup for this bucket type and start date
            let deleteSql = """
                DELETE FROM insights_rollups
                WHERE bucket_type = ? AND bucket_start = ?
                """
            
            var deleteStmt: OpaquePointer?
            defer { sqlite3_finalize(deleteStmt) }
            
            guard sqlite3_prepare_v2(db, deleteSql, -1, &deleteStmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(self.getLastError(db))
            }
            
            sqlite3_bind_text(deleteStmt, 1, rollup.bucketType.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(deleteStmt, 2, rollup.bucketStart.timeIntervalSince1970)
            
            _ = sqlite3_step(deleteStmt) // Ignore result - may not exist
            
            // Insert the new rollup
            let insertSql = """
                INSERT INTO insights_rollups (
                    id, bucket_type, bucket_start, bucket_end,
                    word_count, speaking_seconds, segment_count, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """
            
            var insertStmt: OpaquePointer?
            defer { sqlite3_finalize(insertStmt) }
            
            guard sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(self.getLastError(db))
            }
            
            sqlite3_bind_text(insertStmt, 1, rollup.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insertStmt, 2, rollup.bucketType.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(insertStmt, 3, rollup.bucketStart.timeIntervalSince1970)
            sqlite3_bind_double(insertStmt, 4, rollup.bucketEnd.timeIntervalSince1970)
            sqlite3_bind_int(insertStmt, 5, Int32(rollup.wordCount))
            sqlite3_bind_double(insertStmt, 6, rollup.speakingSeconds)
            sqlite3_bind_int(insertStmt, 7, Int32(rollup.segmentCount))
            sqlite3_bind_double(insertStmt, 8, rollup.createdAt.timeIntervalSince1970)
            
            guard sqlite3_step(insertStmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(self.getLastError(db))
            }
        }
    }
    
    // MARK: - Fetch
    
    /// Fetch a rollup by ID
    public func fetch(id: UUID) async throws -> InsightsRollup? {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT id, bucket_type, bucket_start, bucket_end,
                       word_count, speaking_seconds, segment_count, created_at
                FROM insights_rollups
                WHERE id = ?
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(self.getLastError(db))
            }
            
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return try self.parseRollup(from: stmt)
            }
            
            return nil
        }
    }
    
    /// Fetch rollups with optional bucket type filter and limit
    public func fetchRollups(bucketType: PeriodType? = nil, limit: Int = 100) async throws -> [InsightsRollup] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            var sql = """
                SELECT id, bucket_type, bucket_start, bucket_end,
                       word_count, speaking_seconds, segment_count, created_at
                FROM insights_rollups
                """
            
            if let bucketType = bucketType {
                sql += " WHERE bucket_type = '\(bucketType.rawValue)'"
            }
            
            sql += " ORDER BY bucket_start DESC LIMIT \(limit)"
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(self.getLastError(db))
            }
            
            var rollups: [InsightsRollup] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rollups.append(try self.parseRollup(from: stmt))
            }
            
            return rollups
        }
    }
    
    /// Fetch a specific rollup by bucket type and start date
    public func fetchRollup(bucketType: PeriodType, bucketStart: Date) async throws -> InsightsRollup? {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT id, bucket_type, bucket_start, bucket_end,
                       word_count, speaking_seconds, segment_count, created_at
                FROM insights_rollups
                WHERE bucket_type = ? AND bucket_start = ?
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(self.getLastError(db))
            }
            
            sqlite3_bind_text(stmt, 1, bucketType.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, bucketStart.timeIntervalSince1970)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return try self.parseRollup(from: stmt)
            }
            
            return nil
        }
    }
    
    // MARK: - Delete
    
    /// Delete a rollup by ID
    public func delete(id: UUID) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = "DELETE FROM insights_rollups WHERE id = ?"
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(self.getLastError(db))
            }
            
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(self.getLastError(db))
            }
        }
    }
    
    /// Delete all rollups
    public func deleteAll() async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = "DELETE FROM insights_rollups"
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(self.getLastError(db))
            }
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(self.getLastError(db))
            }
        }
    }
    
    // MARK: - Private Helpers
    
    nonisolated private func getLastError(_ db: OpaquePointer?) -> String {
        if let errorPointer = sqlite3_errmsg(db) {
            return String(cString: errorPointer)
        }
        return "Unknown error"
    }
    
    /// Parse an InsightsRollup from a statement (8 columns)
    nonisolated private func parseRollup(from stmt: OpaquePointer?) throws -> InsightsRollup {
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
}
