import SwiftUI
import SharedModels


struct SessionRowView: View {
    let session: RecordingSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.startTime, style: .date)
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 12) {
                Label(formatTime(session.startTime), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Label(formatDuration(session.totalDuration), systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

// MARK: - Array Extension

// MARK: - Preview

