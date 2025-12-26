// =============================================================================
// RecordingRow.swift — Audio chunk list row
// =============================================================================

import SwiftUI
import SharedModels

struct RecordingRow: View {
    let recording: AudioChunk
    let isPlaying: Bool
    var showPlayButton: Bool = true
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(recording.startTime, style: .date)
                    .font(.headline)
                
                HStack(spacing: 16) {
                    Text(recording.startTime, style: .time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(formatDuration(recording.duration))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Play/Pause button (optional)
            if showPlayButton {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
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
