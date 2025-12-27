// ControlEventRepository.swift
// Storage
//
// ControlEvent CRUD operations

import Foundation
import SharedModels
import SQLite3

/// Repository for ControlEvent operations - app control events
public actor ControlEventRepository {
    private let connection: DatabaseConnection
    
    public init(connection: DatabaseConnection) {
        self.connection = connection
    }
    
    // MARK: - Insert
    
    /// Insert a control event
    public func insert(_ event: ControlEvent) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                INSERT INTO control_events (id, timestamp, source, type, payload_json)
                VALUES (?, ?, ?, ?, ?)
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(self.getLastError(db))
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
                throw StorageError.stepFailed(self.getLastError(db))
            }
        }
    }
    
    // MARK: - Fetch
    
    /// Fetch a control event by ID
    public func fetch(id: UUID) async throws -> ControlEvent? {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = """
                SELECT id, timestamp, source, type, payload_json
                FROM control_events
                WHERE id = ?
                """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(self.getLastError(db))
            }
            
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return try self.parseEvent(from: stmt)
            }
            
            return nil
        }
    }
    
    /// Fetch control events with limit
    public func fetchEvents(limit: Int = 100) async throws -> [ControlEvent] {
        try await connection.withDatabase { db in
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
                throw StorageError.prepareFailed(self.getLastError(db))
            }
            
            var events: [ControlEvent] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                events.append(try self.parseEvent(from: stmt))
            }
            
            return events
        }
    }
    
    // MARK: - Delete
    
    /// Delete a control event by ID
    public func delete(id: UUID) async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = "DELETE FROM control_events WHERE id = ?"
            
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
    
    /// Delete all control events
    public func deleteAll() async throws {
        try await connection.withDatabase { db in
            guard let db = db else { throw StorageError.notOpen }
            
            let sql = "DELETE FROM control_events"
            
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
    
    /// Parse a ControlEvent from a statement (5 columns)
    nonisolated private func parseEvent(from stmt: OpaquePointer?) throws -> ControlEvent {
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
