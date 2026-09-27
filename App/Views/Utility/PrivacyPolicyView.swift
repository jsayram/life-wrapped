import SwiftUI


struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy first")
                    .scaledFont(size: 28, design: .serif)
                
                VStack(alignment: .leading, spacing: 12) {
                    PrivacyPoint(
                        icon: "waveform",
                        title: "Transcription on your \(DeviceName.current)",
                        description: "All recording and speech-to-text happens on your \(DeviceName.current) with Apple's Speech framework, set to on-device recognition only. Your audio is never uploaded."
                    )
                    
                    PrivacyPoint(
                        icon: "sparkles",
                        title: "Summaries, your choice",
                        description: "Key Sentences, Offline AI and Apple Intelligence make summaries on your \(DeviceName.current), and nothing is sent. Cloud AI uses OpenAI or Anthropic with your own API key."
                    )
                    
                    PrivacyPoint(
                        icon: "arrow.up.right",
                        title: "What Cloud AI sends",
                        description: "Text only, never audio: a recording's transcript and Work or Personal label for its summary, the start of its summary for its title, and your recording summaries and notes for month summaries and Year Wrap. You're responsible for what you send and for your API costs. We don't control how OpenAI or Anthropic handle it."
                    )
                    
                    PrivacyPoint(
                        icon: "network",
                        title: "When the app goes online",
                        description: "Only to download the optional Offline AI model from Hugging Face (huggingface.co), to handle purchases through the App Store, and, once you save an API key for Cloud AI, to reach OpenAI (api.openai.com) or Anthropic (api.anthropic.com) after a quick connection check to apple.com. Everything else works offline."
                    )
                    
                    PrivacyPoint(
                        icon: "eye.slash",
                        title: "No tracking",
                        description: "No account, analytics, crash reporting, ads or tracking. Your API keys are stored in the Keychain on this \(DeviceName.current)."
                    )
                    
                    PrivacyPoint(
                        icon: "square.and.arrow.up",
                        title: "Your data, your control",
                        description: "Export or delete your data anytime in Settings, then Data. If you back up your \(DeviceName.current) with iCloud or a computer, iOS includes the app's data in that backup. The full policy is at jsayram.github.io/life-wrapped/privacy."
                    )
                }
            }
            .padding()
        }
        .themedScreen()
        .readableMargins()
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
                .scaledFont(size: 20, weight: .regular)
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

