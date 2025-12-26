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
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.magenta, AppTheme.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(spacing: 8) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("Generate an on-device summary for this period")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                if isGenerating {
                    ProgressView()
                        .tint(AppTheme.purple)
                        .scaleEffect(1.1)
                        .padding(.top, 6)
                } else {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Generate with Local AI")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.purple, AppTheme.magenta],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardGradient(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [AppTheme.magenta.opacity(0.35), AppTheme.purple.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Year Wrapped Card

