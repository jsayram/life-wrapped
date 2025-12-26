import SwiftUI
import Summarization

struct SummaryQualityCard: View {
    let emoji: String
    let title: String
    let subtitle: String
    let detail: String
    let tier: EngineTier
    let isSelected: Bool
    let isAvailable: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? AppTheme.purple : Color.gray.opacity(0.5), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(AppTheme.purple)
                            .frame(width: 12, height: 12)
                    }
                }
                
                // Emoji
                Text(emoji)
                    .font(.title2)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(isAvailable ? .secondary : Color.orange)
                }
                
                Spacer()
                
                // Lock icon if unavailable
                if !isAvailable {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .opacity(isAvailable ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
    }
}
