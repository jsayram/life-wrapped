import SwiftUI


struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy first")
                    .font(AppTheme.titleFont(size: 28))
                
                VStack(alignment: .leading, spacing: 12) {
                    PrivacyPoint(
                        icon: "waveform",
                        title: "Transcription: 100% On-Device",
                        description: "All audio recording and speech-to-text happens on your iPhone using Apple's Speech framework, set to on-device recognition only. Your audio is never uploaded."
                    )
                    
                    PrivacyPoint(
                        icon: "sparkles",
                        title: "AI Summaries: User-Controlled",
                        description: "Uses OpenAI or Anthropic APIs only if you provide your own API keys. Otherwise, summaries are made on your iPhone with Basic, the Smart model, or Apple Intelligence."
                    )
                    
                    PrivacyPoint(
                        icon: "exclamationmark.shield",
                        title: "BYOK: Your Data, Your Responsibility",
                        description: "When using External API with your keys, YOU are responsible for the data you send to third-party providers and any API costs. We are not responsible for how OpenAI or Anthropic handle your data."
                    )
                    
                    PrivacyPoint(
                        icon: "network",
                        title: "Network Calls: Transparent",
                        description: "The app only goes online to: download the optional Smart model from Hugging Face (huggingface.co), handle purchases through the App Store, and, if you choose Smartest, send transcripts to OpenAI (api.openai.com) or Anthropic (api.anthropic.com) with your own key, after a quick connection check to apple.com. Everything else works offline."
                    )
                    
                    PrivacyPoint(
                        icon: "eye.slash",
                        title: "No Tracking",
                        description: "We don't collect analytics, telemetry, or usage data. Your API keys are stored securely in Keychain."
                    )
                    
                    PrivacyPoint(
                        icon: "square.and.arrow.up",
                        title: "Your Data, Your Control",
                        description: "Export or delete your data anytime. Audio files never leave your iPhone. Transcripts leave it only when you use Smartest, and only go to the provider you connect. If you back up your iPhone with iCloud or a computer, iOS includes the app's data in that backup. The full policy is at jsayram.github.io/life-wrapped/privacy."
                    )
                }
            }
            .padding()
        }
        .themedScreen()
        .navigationTitle("Privacy policy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The page shows its own serif heading
            ToolbarItem(placement: .principal) { Text("").accessibilityHidden(true) }
        }
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
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .graphiteCard()
    }
}

// MARK: - Recording Detail View

// MARK: - Session Detail View


// MARK: - Language Settings View

// MARK: - Overview Summary Card

