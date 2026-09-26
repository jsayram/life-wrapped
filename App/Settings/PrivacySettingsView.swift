import SwiftUI

struct PrivacySettingsView: View {
    var body: some View {
        List {
            Section {
                SettingsRowLabel(icon: "waveform", title: "Transcription", value: "On-device")
                SettingsRowLabel(icon: "sparkle", title: "AI summaries", value: "Your choice")
                SettingsRowLabel(icon: "icloud.slash", title: "iCloud sync", value: "Off")
                SettingsRowLabel(icon: "chart.bar", title: "Analytics", value: "None")
            } header: {
                Text("Privacy status")
            } footer: {
                Text("Audio is transcribed on your \(DeviceName.current) with Apple's Speech framework and never leaves it. Basic, Smart and Smarter summaries also stay on your \(DeviceName.current). Transcripts are sent out only if you choose Smartest, to the OpenAI or Anthropic account you connect.")
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
        .navigationTitle("Privacy & Terms")
        .navigationBarTitleDisplayMode(.large)
    }
}
