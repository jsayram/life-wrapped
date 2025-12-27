import SwiftUI


struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy First")
                    .font(.title.bold())
                
                VStack(alignment: .leading, spacing: 12) {
                    PrivacyPoint(
                        icon: "waveform",
                        title: "Transcription: 100% On-Device",
                        description: "All audio recording and speech-to-text happens locally using Apple's Speech framework. Zero network calls."
                    )
                    
                    PrivacyPoint(
                        icon: "sparkles",
                        title: "AI Summaries: User-Controlled",
                        description: "Uses OpenAI or Anthropic APIs only if you provide your own API keys. Otherwise, on-device processing with Apple Intelligence or Basic summaries."
                    )
                    
                    PrivacyPoint(
                        icon: "network",
                        title: "Network Calls: Transparent",
                        description: "With API keys: Connects to OpenAI (api.openai.com) or Anthropic (api.anthropic.com) using YOUR keys. Without keys: 100% offline."
                    )
                    
                    PrivacyPoint(
                        icon: "eye.slash.fill",
                        title: "No Tracking",
                        description: "We don't collect analytics, telemetry, or usage data. Your API keys are stored securely in Keychain."
                    )
                    
                    PrivacyPoint(
                        icon: "square.and.arrow.up",
                        title: "Your Data, Your Control",
                        description: "Export or delete your data anytime. Audio files and transcripts never leave your device."
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyPoint: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardGradient(for: colorScheme))
                .allowsHitTesting(false)
        )
        .cornerRadius(12)
    }
}

// MARK: - Recording Detail View

// MARK: - Session Detail View


// MARK: - Language Settings View

// MARK: - Overview Summary Card

