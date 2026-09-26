import SwiftUI
import SharedModels
import Summarization


struct GeneratePeriodSummaryCard: View {
    let title: String
    let isGenerating: Bool
    let onGenerate: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: onGenerate) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(AppTheme.titleFont(size: 24))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Generate an on-device summary of the recordings in this period.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Group {
                    if isGenerating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(AppTheme.onAccent)
                            Text("Generating")
                                .fontWeight(.semibold)
                        }
                    } else {
                        Label("Generate summary", systemImage: "sparkles")
                            .fontWeight(.semibold)
                    }
                }
                .font(.body)
                .foregroundStyle(AppTheme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous)
                        .fill(AppTheme.accent)
                )
                .padding(.top, 4)
            }
            .graphiteCard()
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }
}

// MARK: - Year Wrapped Card

