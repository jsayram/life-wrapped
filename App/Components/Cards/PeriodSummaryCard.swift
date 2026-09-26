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
        VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SUMMARY")
                        .font(.caption)
                        .tracking(0.8)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(title)
                        .font(AppTheme.titleFont(size: 24))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    IconSquareButton(systemImage: "doc.on.doc", accessibilityLabel: "Copy summary", action: onCopy)
                    if isRegenerating {
                        ProgressView()
                            .frame(width: 36, height: 36)
                    } else {
                        IconSquareButton(systemImage: "arrow.clockwise", accessibilityLabel: "Regenerate summary", action: onRegenerate)
                    }
                }
            }

            Text(summary.text)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .overlay(AppTheme.hairline)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .graphiteCard()
    }
}
