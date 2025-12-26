import SwiftUI

struct RecordingSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var chunkDuration: Double = 180
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Auto-Chunk Duration")
                        Spacer()
                        Text("\(Int(chunkDuration))s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(value: $chunkDuration, in: 30...300, step: 30) {
                        Text("Chunk Duration")
                    }
                    .tint(AppTheme.purple)
                    .onChange(of: chunkDuration) { oldValue, newValue in
                        coordinator.audioCapture.autoChunkDuration = newValue
                        UserDefaults.standard.autoChunkDuration = newValue
                        coordinator.showSuccess("Chunk duration updated to \(Int(newValue))s")
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Chunk Settings")
            } footer: {
                Text("Recordings are automatically split into chunks of this duration for efficient processing and transcription.")
            }
            
            Section {
                HStack {
                    Label("Format", systemImage: "waveform")
                    Spacer()
                    Text("AAC")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Label("Sample Rate", systemImage: "dial.medium")
                    Spacer()
                    Text("44.1 kHz")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Label("Channels", systemImage: "speaker.wave.2")
                    Spacer()
                    Text("Mono")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Audio Quality")
            } footer: {
                Text("Optimized settings for voice recording with smaller file sizes.")
            }
            
            Section {
                NavigationLink(destination: LanguageSettingsView()) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Languages")
                            Text("Manage which languages can be detected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "globe")
                            .foregroundStyle(AppTheme.emerald)
                    }
                }
            } header: {
                Text("Detection")
            }
        }
        .navigationTitle("Recording Chunks")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Load saved setting or use current value
            let savedDuration = UserDefaults.standard.autoChunkDuration
            chunkDuration = savedDuration
            coordinator.audioCapture.autoChunkDuration = savedDuration
        }
    }
}

// MARK: - AI Settings View
