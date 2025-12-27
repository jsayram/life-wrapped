import SwiftUI
import SharedModels
import Summarization


struct PeriodSummaryCard: View {
    let title: String
    let subtitle: String
    let summary: Summary
    let isRegenerating: Bool
    let onCopy: () -> Void
    let onRegenerate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack(alignment: .top) {
                Text("✨")
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Copy
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.skyBlue)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.skyBlue.opacity(0.1))
                    )
                
                    // Regenerate
                    Button(action: onRegenerate) {
                        if isRegenerating {
                            ProgressView()
                                .tint(AppTheme.purple)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.magenta)
                        }
                    }
                    .disabled(isRegenerating)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.magenta.opacity(0.1))
                    )
                }
            }
            
            Divider()
            
            ScrollView {
                Text(summary.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 150, maxHeight: 250)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(8)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    AppTheme.darkPurple.opacity(0.15),
                    AppTheme.magenta.opacity(0.1),
                    AppTheme.purple.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.magenta.opacity(0.3), AppTheme.purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .cornerRadius(16)
        .shadow(color: AppTheme.purple.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

