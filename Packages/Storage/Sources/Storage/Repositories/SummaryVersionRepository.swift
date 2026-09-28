// =============================================================================
// Storage — Summary Version Repository
// =============================================================================
// Earlier versions of summaries, kept when a summary is rewritten so the change
// can be undone. At most `keptPerSummary` versions are kept for each summary.
// =============================================================================

import Foundation
import SQLite3
import SharedModels
import os.log

public actor SummaryVersionRepository {
    private let logger = Logger(subsystem: "com.jsayram.lifewrapped", category: "Storage")
    private let connection: DatabaseConnection

    /// Versions kept for one summary; the oldest go first
    public static let keptPerSummary = 10

    public init(connection: DatabaseConnection) {
        self.connection = connection
    }

    public func insert(_ version: SummaryVersion) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            let sql = """
                INSERT INTO summary_versions (id, summary_key, text, created_at, replaced_at, engine_tier, topics_json, entities_json, source_ids, input_hash)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            sqlite3_bind_text(stmt, 1, version.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, version.summaryKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, version.text, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, version.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 5, version.replacedAt.timeIntervalSince1970)
            Self.bindOptionalText(stmt, 6, version.engineTier)
            Self.bindOptionalText(stmt, 7, version.topicsJSON)
            Self.bindOptionalText(stmt, 8, version.entitiesJSON)
            Self.bindOptionalText(stmt, 9, version.sourceIds)
            Self.bindOptionalText(stmt, 10, version.inputHash)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(await self.connection.lastError())
            }
        }
        try await prune(key: version.summaryKey)
    }

    /// Versions of one summary, newest first
    public func fetch(key: String) async throws -> [SummaryVersion] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            let sql = "SELECT id, summary_key, text, created_at, replaced_at, engine_tier, topics_json, entities_json, source_ids, input_hash FROM summary_versions WHERE summary_key = ? ORDER BY replaced_at DESC"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
            var versions: [SummaryVersion] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                versions.append(try Self.parse(stmt))
            }
            return versions
        }
    }

    public func fetchAll() async throws -> [SummaryVersion] {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            let sql = "SELECT id, summary_key, text, created_at, replaced_at, engine_tier, topics_json, entities_json, source_ids, input_hash FROM summary_versions ORDER BY replaced_at DESC"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            var versions: [SummaryVersion] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                versions.append(try Self.parse(stmt))
            }
            return versions
        }
    }

    public func exists(id: UUID) async throws -> Bool {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT 1 FROM summary_versions WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    public func delete(id: UUID) async throws {
        try await run("DELETE FROM summary_versions WHERE id = ?", binding: id.uuidString)
    }

    public func deleteAll(key: String) async throws {
        try await run("DELETE FROM summary_versions WHERE summary_key = ?", binding: key)
    }

    public func deleteAll() async throws {
        try await connection.execute("DELETE FROM summary_versions")
    }

    /// Keep the newest `keptPerSummary` versions of a summary
    private func prune(key: String) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            let sql = """
                DELETE FROM summary_versions WHERE summary_key = ? AND id NOT IN (
                    SELECT id FROM summary_versions WHERE summary_key = ? ORDER BY replaced_at DESC LIMIT ?
                )
                """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(Self.keptPerSummary))
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(await self.connection.lastError())
            }
        }
    }

    private func run(_ sql: String, binding value: String) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(await self.connection.lastError())
            }
            sqlite3_bind_text(stmt, 1, value, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.stepFailed(await self.connection.lastError())
            }
        }
    }

    nonisolated private static func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    nonisolated private static func text(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        sqlite3_column_text(stmt, index).map { String(cString: $0) }
    }

    nonisolated private static func parse(_ stmt: OpaquePointer?) throws -> SummaryVersion {
        guard let idText = text(stmt, 0), let id = UUID(uuidString: idText),
              let key = text(stmt, 1), let body = text(stmt, 2) else {
            throw StorageError.invalidData("Missing required SummaryVersion column data")
        }
        return SummaryVersion(
            id: id,
            summaryKey: key,
            text: body,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
            replacedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
            engineTier: text(stmt, 5),
            topicsJSON: text(stmt, 6),
            entitiesJSON: text(stmt, 7),
            sourceIds: text(stmt, 8),
            inputHash: text(stmt, 9)
        )
    }
}
