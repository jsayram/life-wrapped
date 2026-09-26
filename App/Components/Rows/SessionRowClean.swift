// =============================================================================
// SessionRowClean.swift — Clean session list row with metadata
// =============================================================================

import SwiftUI
import SharedModels

// MARK: - Clean Session Row

struct SessionRowClean: View {
    let session: RecordingSession
    let wordCount: Int?
    let hasSummary: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: (session.category ?? .personal).outlineSymbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 22, height: 22)
                .padding(.top, 1)
                .accessibilityLabel((session.category ?? .personal).displayName)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(displayTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                    if session.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .accessibilityLabel("Favorite")
                    }
                }

                // Meta line: time, duration, words or status
                HStack(spacing: 10) {
                    Text(timeString)
                    Text(formatDuration(session.totalDuration))
                        .monospacedDigit()
                    Text(statusText)
                    if hasSummary {
                        Image(systemName: "checkmark.circle")
                            .accessibilityLabel("Summarized")
                    }
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private var displayTitle: String {
        if let title = session.title, !title.isEmpty { return title }
        return "Untitled recording"
    }

    private var statusText: String {
        guard let count = wordCount else { return "Transcribing" }
        if count == 0 { return "No speech" }
        return "\(count.formatted()) words"
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: session.startTime)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
