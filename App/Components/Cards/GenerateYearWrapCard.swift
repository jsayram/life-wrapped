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
            VStack(spacing: 20) {
                // Animated sparkles icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.magenta.opacity(0.2), AppTheme.purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.magenta, AppTheme.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolEffect(.pulse.byLayer, options: .repeating)
                }
                
                VStack(spacing: 12) {
                    Text("Generate Year Wrapped")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Create an AI-powered summary of your entire year with insights, highlights, and trends")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                if isGenerating {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(AppTheme.purple)
                            .scaleEffect(1.2)
                        Text("Generating...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                } else {
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .font(.title3)
                            Text("Generate with AI")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.magenta, AppTheme.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: AppTheme.purple.opacity(0.4), radius: 12, y: 6)
                        
                        Text("Takes 2-3 minutes • Cannot be stopped")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(28)
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

