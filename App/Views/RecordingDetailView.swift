// =============================================================================
// RecordingDetailView — View recording details and transcription
// =============================================================================

import SwiftUI
import SharedModels

struct RecordingDetailView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let recording: AudioChunk
    
    @State private var transcriptSegments: [TranscriptSegment] = []
    @State private var isLoading = true
    @State private var loadError: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Recording Info Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recording Details")
                        .font(.headline)
                    
                    InfoRow(label: "Date", value: recording.startTime.formatted(date: .abbreviated, time: .shortened))
                    InfoRow(label: "Duration", value: formatDuration(recording.duration))
                    InfoRow(label: "File Size", value: formatFileSize(recording.fileSize))
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                
                // Playback Controls
                VStack(spacing: 16) {
                    // Waveform placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemBackground))
                        .frame(height: 60)
                        .overlay {
                            if coordinator.audioPlayback.currentlyPlayingURL == recording.fileURL {
                                // Show progress
                                GeometryReader { geometry in
                                    let progress = coordinator.audioPlayback.duration > 0 
                                        ? coordinator.audioPlayback.currentTime / coordinator.audioPlayback.duration 
                                        : 0
                                    
                                    HStack(spacing: 0) {
                                        Rectangle()
                                            .fill(Color.blue.opacity(0.3))
                                            .frame(width: geometry.size.width * progress)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    
                    // Play/Pause Button
                    Button {
                        playRecording()
                    } label: {
                        HStack {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title)
                            
                            if isPlaying {
                                Text("\(formatTime(coordinator.audioPlayback.currentTime)) / \(formatTime(coordinator.audioPlayback.duration))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Tap to play")
                                    .font(.subheadline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                
                // Transcription Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transcription")
                        .font(.headline)
                    
                    if isLoading {
                        ProgressView("Loading transcription...")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if let error = loadError {
                        Text("Error: \(error)")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                            .padding()
                    } else if transcriptSegments.isEmpty {
                        Text("No transcription available")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(transcriptSegments, id: \.id) { segment in
                                Text(segment.text)
                                    .font(.body)
                                    .padding(.vertical, 4)
                            }
                        }
                        .padding()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTranscription()
        }
    }
    
    private var isPlaying: Bool {
        coordinator.audioPlayback.currentlyPlayingURL == recording.fileURL && coordinator.audioPlayback.isPlaying
    }
    
    private func playRecording() {
        if coordinator.audioPlayback.currentlyPlayingURL == recording.fileURL {
            coordinator.audioPlayback.togglePlayPause()
        } else {
            do {
                try coordinator.audioPlayback.play(url: recording.fileURL)
            } catch {
                loadError = "Could not play recording: \(error.localizedDescription)"
            }
        }
    }
    
    private func loadTranscription() async {
        isLoading = true
        loadError = nil
        
        do {
            transcriptSegments = try await coordinator.fetchTranscript(for: recording.id)
            print("📄 [RecordingDetailView] Loaded \(transcriptSegments.count) transcript segments")
            
            // Debug: print the first segment if available
            if let first = transcriptSegments.first {
                print("📄 [RecordingDetailView] First segment: '\(first.text)'")
            }
        } catch {
            print("❌ [RecordingDetailView] Failed to load transcription: \(error)")
            loadError = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        } else {
            let mb = kb / 1024
            return String(format: "%.1f MB", mb)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}
