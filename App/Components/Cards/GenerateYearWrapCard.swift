import SwiftUI
import SharedModels
import Summarization


struct GenerateYearWrapCard: View {
    let onGenerate: () -> Void
    let isGenerating: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button {
            onGenerate()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Wrap your year")
                    .font(AppTheme.titleFont(size: 24))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("A summary of your whole year with highlights, people and trends. Takes 2 to 3 minutes and can't be stopped once started.")
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
                        Label("Generate", systemImage: "sparkles")
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .fill(AppTheme.card)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }
}

// MARK: - Topic Tags View

