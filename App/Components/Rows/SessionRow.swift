// =============================================================================
// SessionRow.swift — Legacy session row (compatibility wrapper)
// =============================================================================

import SwiftUI
import SharedModels

// MARK: - Legacy SessionRow (kept for compatibility)

struct SessionRow: View {
    let session: RecordingSession
    let wordCount: Int?
    let sentiment: Double?
    let language: String?
    
    var body: some View {
        SessionRowClean(
            session: session,
            wordCount: wordCount,
            hasSummary: false
        )
    }
}
