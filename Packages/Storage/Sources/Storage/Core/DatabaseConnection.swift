// =============================================================================
// Storage — Database Connection
// =============================================================================
// Core database connection management with thread-safe access.
// Shared by all repositories.
// =============================================================================

import Foundation
import SQLite3
import SharedModels
import os.log

/// SQLite transient destructor for text binding
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thread-safe database connection actor
public actor DatabaseConnection {
    private let logger = Logger(subsystem: "com.jsayram.lifewrapped", category: "Storage")
    nonisolated(unsafe) private var db: OpaquePointer?
    public let databaseURL: URL
    private let fileManager = FileManager.default
    
    /// Initialize with specific database URL
    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }
    
    /// Initialize with App Group container identifier (auto-creates path)
    public init(containerIdentifier: String) async throws {
        #if DEBUG
        print("💾 [DatabaseConnection] Looking for App Group: \(containerIdentifier)")
        #endif
        let containerURL: URL
        if let appGroupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: containerIdentifier
        ) {
            containerURL = appGroupURL
            #if DEBUG
            print("✅ [DatabaseConnection] App Group found: \(containerURL.path)")
            #endif
        } else {
            // Fallback to Documents directory for simulator/development
            #if DEBUG
            print("⚠️ [DatabaseConnection] App Group not available, using Documents directory as fallback")
            #endif
            guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                #if DEBUG
                print("❌ [DatabaseConnection] Documents directory not available")
                #endif
                throw StorageError.appGroupContainerNotFound(containerIdentifier)
            }
            containerURL = documentsURL
            #if DEBUG
            print("✅ [DatabaseConnection] Using Documents directory: \(containerURL.path)")
            #endif
        }
        
        // Create database directory if needed
        let databaseDirectory = containerURL.appendingPathComponent("Database", isDirectory: true)
        #if DEBUG
        print("💾 [DatabaseConnection] Creating database directory...")
        #endif
        try fileManager.createDirectory(
            at: databaseDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        #if DEBUG
        print("✅ [DatabaseConnection] Database directory created")
        #endif
        
        self.databaseURL = databaseDirectory.appendingPathComponent(AppConstants.databaseFilename)
        
        logger.info("Database path: \(self.databaseURL.path)")
        #if DEBUG
        print("💾 [DatabaseConnection] Database path: \(self.databaseURL.path)")
        #endif
        
        // Open database connection
        #if DEBUG
        print("💾 [DatabaseConnection] Opening database connection...")
        #endif
        try open()
        #if DEBUG
        print("✅ [DatabaseConnection] Database opened")
        #endif
    }
    
    /// Execute a block with safe access to the database pointer
    /// This method ensures thread-safe access without crossing actor boundaries
    public func withDatabase<T>(_ body: @Sendable (OpaquePointer?) async throws -> T) async rethrows -> T {
        // Note: db access is safe here because we're within the actor's isolation domain
        // The @Sendable closure executes immediately on the actor
        return try await body(db)
    }
    
    /// Open database connection
    public func open() throws {
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
    
    /// Close the database connection
    public func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }
    
    /// Execute a SQL statement
    public func execute(_ sql: String) throws {
        var errorMsg: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorMsg) }
        
        if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
            let error = errorMsg.map { String(cString: $0) } ?? "Unknown error"
            throw StorageError.executionFailed(error)
        }
    }
    
    /// Get the last error message from SQLite
    public func lastError() -> String {
        guard let db = db else { return "Database not open" }
        return String(cString: sqlite3_errmsg(db))
    }
    
    /// Get the database path
    public func getDatabasePath() -> String {
        databaseURL.path
    }
}
