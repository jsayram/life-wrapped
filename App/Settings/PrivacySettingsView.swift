import SwiftUI

struct PrivacySettingsView: View {
    var body: some View {
        List {
            Section {
                SettingsRowLabel(icon: "waveform", title: "Transcription", value: "On-device")
                SettingsRowLabel(icon: "sparkle", title: "AI summaries", value: "Your choice")
                SettingsRowLabel(icon: "icloud.slash", title: "Cloud sync", value: "None")
                SettingsRowLabel(icon: "chart.bar", title: "Analytics", value: "None")
            } header: {
                Text("Privacy status")
            } footer: {
                Text("Audio is transcribed on your \(DeviceName.current) with Apple's Speech framework and never leaves it. Key Sentences, Offline AI and Apple Intelligence summaries also stay on your \(DeviceName.current). Text from your journal (transcripts, summaries and notes) is sent out only if you choose Cloud AI, and only to the OpenAI or Anthropic account you connect.")
            }
            
            Section {
                NavigationLink(destination: PrivacyPolicyView()) {
                    SettingsRowLabel(icon: "doc.text", title: "Privacy policy")
                }
                
                NavigationLink(destination: TermsOfServiceView()) {
                    SettingsRowLabel(icon: "doc.plaintext", title: "Terms of service")
                }
            }
        }
        .themedScreen()
        .readableMargins()
        .navigationTitle("Privacy & Terms")
        .columnScreenTitleDisplayMode()
    }
}
