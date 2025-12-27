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
                    Text("Generate Year Wrapped")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("Create an AI-powered summary of your entire year")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                if isGenerating {
                    ProgressView()
                        .tint(AppTheme.purple)
                        .scaleEffect(1.2)
                        .padding(.top, 8)
                } else {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Generate with AI")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.magenta, AppTheme.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(
                LinearGradient(
                    colors: [
                        AppTheme.darkPurple.opacity(0.1),
                        AppTheme.magenta.opacity(0.05),
                        AppTheme.purple.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.magenta.opacity(0.3), AppTheme.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }
}

// MARK: - Topic Tags View

