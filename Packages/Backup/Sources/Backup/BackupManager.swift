// =============================================================================
// Backup — Backup Manager
// =============================================================================

import Foundation
import SharedModels
import Storage

/// Manager for exporting and importing application data
public actor BackupManager {
    
    // MARK: - Public API
    
    public init() {}
    
    /// Export all application data to JSON format
    public func exportData() async throws -> Data {
        // TODO: Implement data export
        throw BackupError.notImplemented
    }
    
    /// Import application data from JSON format
    public func importData(_ data: Data) async throws {
        // TODO: Implement data import
        throw BackupError.notImplemented
    }
}

// MARK: - Errors

public enum BackupError: Error, Sendable {
    case notImplemented
    case exportFailed(String)
    case importFailed(String)
}
