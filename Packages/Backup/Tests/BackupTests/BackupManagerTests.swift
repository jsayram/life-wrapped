// =============================================================================
// Backup — Tests
// =============================================================================

import Testing
@testable import Backup

@Test func backupManagerInitializes() async throws {
    let manager = BackupManager()
    #expect(manager != nil)
}
