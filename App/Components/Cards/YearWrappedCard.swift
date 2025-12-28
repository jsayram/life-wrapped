import SwiftUI
import SharedModels
import Summarization


struct YearWrappedCard: View {
    let summary: Summary
    let coordinator: AppCoordinator
    let onRegenerate: () -> Void
    let isRegenerating: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("✨")
                            .font(.title2)
                        Text("Year Wrapped")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    Text("AI-powered yearly summary")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Staleness badge
                    if coordinator.yearWrapNewSessionCount > 0 {
                        Label(
                            "Outdated (\(coordinator.yearWrapNewSessionCount) new \(coordinator.yearWrapNewSessionCount == 1 ? "session" : "sessions"))",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.orange.opacity(0.15))
                        )
                        .padding(.top, 2)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Copy button
                    Button {
                        UIPasteboard.general.string = summary.text
                        coordinator.showSuccess("Year Wrapped summary copied")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.body)
                            .foregroundStyle(AppTheme.skyBlue)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.skyBlue.opacity(0.1))
                    )
                    
                    // Regenerate button
                    Button {
                        onRegenerate()
                    } label: {
                        if isRegenerating {
                            ProgressView()
                                .tint(AppTheme.purple)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.body)
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
            
            // Summary text - scrollable
            ScrollView {
                Text(summary.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: 300)
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

// MARK: - Generate Year Wrap Card

