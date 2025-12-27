import SwiftUI
import Summarization

struct GenerationOverlay: View {
    let progress: Double
    let phase: String
    let engineTier: EngineTier?
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .blur(radius: 2)
            
            VStack(spacing: 24) {
                // CPU icon with animation
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.purple.opacity(0.3), AppTheme.magenta.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .scaleEffect(1.0 + progress * 0.2)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: progress)
                    
                    Image(systemName: "cpu")
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.purple, AppTheme.magenta],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(spacing: 12) {
                    Text(engineTier == .basic ? "Processing" : "AI Processing")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    // Progress bar
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 280, height: 8)
                        
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.purple, AppTheme.magenta],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 280 * progress, height: 8)
                            .animation(.linear(duration: 0.3), value: progress)
                    }
                    
                    Text("\(Int(progress * 100))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    
                    Text(phase)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 20)
                }
                
                if let engineTier = engineTier {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(AppTheme.skyBlue)
                            Text(engineTier == .basic ? "What's happening?" : "Why does this take time?")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                        }
                        
                        Group {
                            switch engineTier {
                            case .basic:
                                Text("Life Wrapped is creating a basic summary by extracting key information from your transcript. This is a simple, fast process that works offline.")
                            case .local:
                                Text("Life Wrapped is using Phi-3.5, a powerful local AI model running directly on your device. This provides high-quality summaries while keeping all your data private.")
                            case .apple:
                                Text("Life Wrapped performs a comprehensive analysis directly on your iPhone using Apple Intelligence. No data leaves your device — it's completely private.")
                            case .external:
                                let provider = UserDefaults.standard.string(forKey: "externalAPIProvider") ?? "OpenAI"
                                Text("Life Wrapped uses \(provider)'s advanced AI to perform intelligent processing and generate the best possible summary of your transcript. This provides the most comprehensive and insightful analysis.")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Once complete, future views of this session are instant!")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground).opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [AppTheme.purple.opacity(0.5), AppTheme.magenta.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 40)
        }
    }
}
