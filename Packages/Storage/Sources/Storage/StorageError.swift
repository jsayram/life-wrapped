// =============================================================================
// Storage — Error Types
// =============================================================================

import Foundation

/// Errors that can occur during Storage package operations
public enum StorageError: Error, LocalizedError, Sendable {
    case appGroupContainerNotFound(String)
    case databaseOpenFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case migrationFailed(String)
    case executionFailed(String)
    case unknownMigrationVersion(Int)
    case notOpen
    case invalidData(String)
    
    public var errorDescription: String? {
        switch self {
        case .appGroupContainerNotFound(let identifier):
            "App Group container not found: \(identifier)"
        case .databaseOpenFailed(let message):
            "Failed to open database: \(message)"
        case .prepareFailed(let message):
            "Failed to prepare SQL statement: \(message)"
        case .stepFailed(let message):
            "Failed to execute SQL statement: \(message)"
        case .migrationFailed(let message):
            "Database migration failed: \(message)"
        case .executionFailed(let message):
            "SQL execution failed: \(message)"
        case .unknownMigrationVersion(let version):
            "Unknown migration version: \(version)"
        case .notOpen:
            "Database is not open"
        case .invalidData(let message):
            "Invalid data: \(message)"
        }
    }
}
