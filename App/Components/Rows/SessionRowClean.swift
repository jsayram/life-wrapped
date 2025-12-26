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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Title or date/time
                    if let title = session.title, !title.isEmpty {
                        Text(title)
                            .font(.headline)
                            .lineLimit(2)
                    } else {
                        Text(session.startTime, format: .dateTime.month().day().hour().minute())
                            .font(.headline)
                    }
                    
                    Text(timeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Favorite star
                if session.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
            
            // Duration and word count
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(formatDuration(session.duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                if let count = wordCount, count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft")
                        Text("\(count) words")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.secondary)
            
            // Status indicators
            HStack(spacing: 6) {
                if session.chunkCount > 1 {
                    StatusPill(text: "\(session.chunkCount) parts", color: .blue, icon: "waveform")
                }
                
                if hasSummary {
                    StatusPill(text: "Summarized", color: .green, icon: "checkmark.circle.fill")
                }
                
                // Show processing if wordCount is nil (still being transcribed)
                if wordCount == nil {
                    StatusPill(text: "Processing", color: .orange, icon: "gearshape.fill")
                }
                // Show "No Words" badge if transcription complete but 0 words
                else if let count = wordCount, count == 0 {
                    StatusPill(text: "No Words To Transcribe", color: .gray, icon: "mic.slash.fill")
                }
            }
        }
        .padding(.vertical, 6)
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: session.startTime)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
