// =============================================================================
// Storage — Summary Repository
// =============================================================================
// CRUD operations and queries for summaries (session and period-based).
// =============================================================================

import Foundation
import SQLite3
import SharedModels
import os.log

public actor SummaryRepository {
    private let logger = Logger(subsystem: "com.jsayram.lifewrapped", category: "Storage")
    private let connection: DatabaseConnection
    
    public init(connection: DatabaseConnection) {
        self.connection = connection
    }
    
    // MARK: - Summary CRUD
    
    public func insert(_ summary: Summary) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                INSERT INTO summaries (id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier, source_ids, input_hash)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
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
            
            if let sourceIds = summary.sourceIds {
                sqlite3_bind_text(stmt, 11, sourceIds, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 11)
            }
            
            if let inputHash = summary.inputHash {
                sqlite3_bind_text(stmt, 12, inputHash, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 12)
            }
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(await self.connection.lastError())
            }
        }
    }
    
    public func fetch(id: UUID) async throws -> Summary? {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier, source_ids, input_hash
                FROM summaries
                WHERE id = ?
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return try self.parseSummary(from: stmt)
            }
            
            return nil
        }
    }
    
    public func fetchSummaries(periodType: PeriodType? = nil, limit: Int = 100) async throws -> [Summary] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            var sql = """
                SELECT id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier, source_ids, input_hash
                FROM summaries
                """
            
            if periodType != nil {
                sql += " WHERE period_type = ?"
            }
            
            sql += " ORDER BY period_start DESC LIMIT \(limit)"
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            
            if let periodType = periodType {
                sqlite3_bind_text(stmt, 1, periodType.rawValue, -1, SQLITE_TRANSIENT)
            }
            
            var summaries: [Summary] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                summaries.append(try self.parseSummary(from: stmt))
            }
            
            return summaries
        }
    }
    
    /// Fetch all summaries (convenience method for export)
    public func fetchAll() async throws -> [Summary] {
        return try await fetchSummaries(periodType: nil, limit: 10000)
    }
    
    public func delete(id: UUID) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = "DELETE FROM summaries WHERE id = ?"
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(await self.connection.lastError())
            }
        }
    }
    
    // MARK: - Session Summary Queries
    
    /// Fetch summary for a specific session
    public func fetchForSession(sessionId: UUID) async throws -> Summary? {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier, source_ids, input_hash
                FROM summaries
                WHERE session_id = ?
                ORDER BY created_at DESC
                LIMIT 1
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return try self.parseSummary(from: stmt)
            }
            
            return nil
        }
    }
    
    /// Fetch session summaries within a date range
    public func fetchSessionSummariesInDateRange(from startDate: Date, to endDate: Date) async throws -> [Summary] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier, source_ids, input_hash
                FROM summaries
                WHERE period_type = 'session'
                AND period_start >= ?
                AND period_start <= ?
                ORDER BY period_start DESC
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            
            sqlite3_bind_double(stmt, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, endDate.timeIntervalSince1970)
            
            var summaries: [Summary] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                summaries.append(try self.parseSummary(from: stmt))
            }
            
            return summaries
        }
    }
    
    // MARK: - Period Summary Queries
    
    /// Fetch period summary for a specific date and type
    public func fetchPeriodSummary(type: PeriodType, date: Date) async throws -> Summary? {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier, source_ids, input_hash
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
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            
            sqlite3_bind_text(stmt, 1, type.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, date.timeIntervalSince1970)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return try self.parseSummary(from: stmt)
            }
            
            return nil
        }
    }
    
    /// Upsert (insert or update) a period summary with full structured data
    public func upsertPeriodSummary(
        type: PeriodType,
        text: String,
        start: Date,
        end: Date,
        topicsJSON: String? = nil,
        entitiesJSON: String? = nil,
        engineTier: String? = nil,
        sourceIds: String? = nil,
        inputHash: String? = nil
    ) async throws {
        // Check if summary exists
        if let existing = try await fetchPeriodSummary(type: type, date: start) {
            // Update existing with structured data
            try await connection.withDatabase { db in
                guard let db = db else { throw StorageError.notOpen }
                
                let sql = """
                    UPDATE summaries
                    SET text = ?, period_end = ?, topics_json = ?, entities_json = ?, engine_tier = ?, source_ids = ?, input_hash = ?
                    WHERE id = ?
                    """
                
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    throw StorageError.prepareFailed(await self.connection.lastError())
                }
                
                sqlite3_bind_text(stmt, 1, text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 2, end.timeIntervalSince1970)
                
                if let topics = topicsJSON {
                    sqlite3_bind_text(stmt, 3, topics, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 3)
                }
                
                if let entities = entitiesJSON {
                    sqlite3_bind_text(stmt, 4, entities, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 4)
                }
                
                if let tier = engineTier {
                    sqlite3_bind_text(stmt, 5, tier, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 5)
                }
                
                if let sources = sourceIds {
                    sqlite3_bind_text(stmt, 6, sources, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                
                if let hash = inputHash {
                    sqlite3_bind_text(stmt, 7, hash, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }
                
                sqlite3_bind_text(stmt, 8, existing.id.uuidString, -1, SQLITE_TRANSIENT)
                
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw StorageError.stepFailed(await self.connection.lastError())
                }
            }
        } else {
            // Insert new with structured data
            let summary = Summary(
                id: UUID(),
                periodType: type,
                periodStart: start,
                periodEnd: end,
                text: text,
                createdAt: start,
                sessionId: nil,
                topicsJSON: topicsJSON,
                entitiesJSON: entitiesJSON,
                engineTier: engineTier,
                sourceIds: sourceIds,
                inputHash: inputHash
            )
            try await insert(summary)
        }
    }
    
    // MARK: - Daily/Weekly/Monthly Summary Queries
    
    /// Fetch all daily summaries for a date range
    public func fetchDailySummaries(from startDate: Date, to endDate: Date) async throws -> [Summary] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier, source_ids, input_hash
                FROM summaries
                WHERE period_type = 'day'
                AND period_start >= ? AND period_start < ?
                AND session_id IS NULL
                ORDER BY period_start ASC
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            
            sqlite3_bind_double(stmt, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, endDate.timeIntervalSince1970)
            
            var summaries: [Summary] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let summary = try? self.parseSummary(from: stmt) {
                    summaries.append(summary)
                }
            }
            
            return summaries
        }
    }
    
    /// Fetch all weekly summaries for a date range
    public func fetchWeeklySummaries(from startDate: Date, to endDate: Date) async throws -> [Summary] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier, source_ids, input_hash
                FROM summaries
                WHERE period_type = 'week'
                AND period_start >= ? AND period_start < ?
                AND session_id IS NULL
                ORDER BY period_start ASC
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            
            sqlite3_bind_double(stmt, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, endDate.timeIntervalSince1970)
            
            var summaries: [Summary] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let summary = try? self.parseSummary(from: stmt) {
                    summaries.append(summary)
                }
            }
            
            return summaries
        }
    }
    
    /// Fetch all monthly summaries for a date range
    public func fetchMonthlySummaries(from startDate: Date, to endDate: Date) async throws -> [Summary] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT id, period_type, period_start, period_end, text, created_at, session_id, topics_json, entities_json, engine_tier, source_ids, input_hash
                FROM summaries
                WHERE period_type = 'month'
                AND period_start >= ? AND period_start < ?
                AND session_id IS NULL
                ORDER BY period_start ASC
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            
            sqlite3_bind_double(stmt, 1, startDate.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, endDate.timeIntervalSince1970)
            
            var summaries: [Summary] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let summary = try? self.parseSummary(from: stmt) {
                    summaries.append(summary)
                }
            }
            
            return summaries
        }
    }
    
    // MARK: - Parsing Helper
    
    nonisolated private func parseSummary(from stmt: OpaquePointer?) throws -> Summary {
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
        
        // Parse optional source_ids
        let sourceIds: String?
        if let sourceText = sqlite3_column_text(stmt, 10) {
            sourceIds = String(cString: sourceText)
        } else {
            sourceIds = nil
        }
        
        // Parse optional input_hash
        let inputHash: String?
        if let hashText = sqlite3_column_text(stmt, 11) {
            inputHash = String(cString: hashText)
        } else {
            inputHash = nil
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
            engineTier: engineTier,
            sourceIds: sourceIds,
            inputHash: inputHash
        )
    }
}
