import SwiftUI

struct PrivacySettingsView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Transcription", systemImage: "waveform")
                        Spacer()
                        Text("On-Device")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                    Text("100% local, uses Apple Speech framework")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 32)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("AI Summaries", systemImage: "sparkles")
                        Spacer()
                        Text("User-Controlled")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                    Text("Uses your API keys (OpenAI/Anthropic) or on-device fallback")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 32)
                }
                
                HStack {
                    Label("iCloud Sync", systemImage: "icloud.slash")
                    Spacer()
                    Text("Disabled")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Label("Analytics", systemImage: "chart.bar.xaxis")
                    Spacer()
                    Text("None")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Privacy Status")
            } footer: {
                Text("Transcription always happens on-device. AI summaries use external APIs only if you provide API keys, otherwise on-device processing.")
            }
            
            Section {
                NavigationLink(destination: PrivacyPolicyView()) {
                    Label("Privacy Policy", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
