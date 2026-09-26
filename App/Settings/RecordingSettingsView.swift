import SwiftUI
import Transcription

struct RecordingSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var chunkDuration: Double = 180
    @State private var languagesSummary: String = ""
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Split recordings every")
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text("\(Int(chunkDuration))s")
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    
                    Slider(value: $chunkDuration, in: 30...300, step: 30) {
                        Text("Part length")
                    } minimumValueLabel: {
                        EmptyView()
                    } maximumValueLabel: {
                        EmptyView()
                    }
                    .tint(AppTheme.accent)

                    HStack {
                        Text("30s")
                        Spacer()
                        Text("300s")
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .onChange(of: chunkDuration) { oldValue, newValue in
                        coordinator.audioCapture.autoChunkDuration = newValue
                        UserDefaults.standard.autoChunkDuration = newValue
                        coordinator.showSuccess("Parts set to \(Int(newValue))s")
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Parts")
            } footer: {
                Text("Shorter parts transcribe faster. Longer parts keep more context.")
            }
            
            Section {
                SettingsRowLabel(icon: "waveform", title: "Format", value: "AAC")
                
                SettingsRowLabel(icon: "gauge.with.dots.needle.33percent", title: "Sample rate", value: "44.1 kHz")
                
                SettingsRowLabel(icon: "speaker.wave.1", title: "Channels", value: "Mono")
            } header: {
                Text("Audio quality")
            } footer: {
                Text("Tuned for voice with small file sizes.")
            }
            
            Section {
                NavigationLink(destination: LanguageSettingsView()) {
                    SettingsRowLabel(icon: "globe", title: "Languages", value: languagesSummary)
                }
            } header: {
                Text("Detection")
            }
        }
        .themedScreen()
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            let codes = (UserDefaults.standard.array(forKey: "enabledLanguages") as? [String]) ?? ["en", "es"]
            let names = codes.map { LanguageDetector.displayName(for: $0) }.sorted()
            languagesSummary = names.count > 2 ? "\(names.count) languages" : names.joined(separator: ", ")
        }
        .task {
            // Load saved setting or use current value
            let savedDuration = UserDefaults.standard.autoChunkDuration
            chunkDuration = savedDuration
            coordinator.audioCapture.autoChunkDuration = savedDuration
        }
    }
}

// MARK: - AI Settings View
