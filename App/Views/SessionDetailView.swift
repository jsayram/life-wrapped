// =============================================================================
// SessionDetailView — View multi-chunk session details
// =============================================================================

import SwiftUI
import SharedModels
import Transcription

struct SessionDetailView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let session: RecordingSession
    
    @State private var transcriptSegments: [TranscriptSegment] = []
    @State private var sessionSentiment: Double?
    @State private var sessionLanguage: String?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var currentlyPlayingChunkIndex: Int?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Session Info Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Session Details")
                            .font(.headline)
                        Spacer()
                        HStack(spacing: 8) {
                            // Language badge
                            if let language = sessionLanguage {
                                HStack(spacing: 6) {
                                    Text(LanguageDetector.flagEmoji(for: language))
                                        .font(.title3)
                                    Text(LanguageDetector.displayName(for: language))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.15))
                                .clipShape(Capsule())
                            }
                            
                            // Sentiment badge
                            if let sentiment = sessionSentiment {
                                HStack(spacing: 6) {
                                    Text(sentimentEmoji(sentiment))
                                        .font(.title2)
                                    Text(sentimentCategory(sentiment))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(sentimentColor(sentiment))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(sentimentColor(sentiment).opacity(0.15))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    
                    InfoRow(label: "Date", value: session.startTime.formatted(date: .abbreviated, time: .shortened))
                    InfoRow(label: "Total Duration", value: formatDuration(session.totalDuration))
                    InfoRow(label: "Parts", value: "\(session.chunkCount) chunk\(session.chunkCount == 1 ? "" : "s")")
                    
                    if !transcriptSegments.isEmpty {
                        let wordCount = transcriptSegments.reduce(0) { $0 + $1.text.split(separator: " ").count }
                        InfoRow(label: "Word Count", value: "\(wordCount) words")
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                
                // Chunks Section (for multi-chunk sessions)
                if session.chunkCount > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recording Parts")
                            .font(.headline)
                        
                        ForEach(Array(session.chunks.enumerated()), id: \.element.id) { index, chunk in
                            ChunkCard(
                                chunk: chunk,
                                index: index,
                                isPlaying: currentlyPlayingChunkIndex == index && coordinator.audioPlayback.isPlaying,
                                onPlay: {
                                    playChunk(at: index)
                                }
                            )
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                
                // Play All Button (for multi-chunk)
                if session.chunkCount > 1 {
                    Button {
                        playSession()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                            Text("Play All Parts")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                
                // Single chunk playback (for single-chunk sessions)
                if session.chunkCount == 1, let chunk = session.chunks.first {
                    VStack(spacing: 16) {
                        // Waveform placeholder
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.tertiarySystemBackground))
                            .frame(height: 60)
                            .overlay {
                                if coordinator.audioPlayback.currentlyPlayingURL == chunk.fileURL {
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
                        
                        Button {
                            playChunk(at: 0)
                        } label: {
                            HStack {
                                Image(systemName: isPlayingFirstChunk ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.title)
                                
                                if isPlayingFirstChunk {
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
                }
                
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
                            .font(.subheadline)
                            .padding()
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(groupedByChunk, id: \.chunkIndex) { group in
                                if session.chunkCount > 1 {
                                    // Show chunk marker for multi-chunk sessions
                                    HStack {
                                        Divider()
                                            .frame(width: 40)
                                        Text("Part \(group.chunkIndex + 1)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Divider()
                                    }
                                }
                                
                                Text(group.text)
                                    .font(.body)
                            }
                        }
                        .padding()
                    }
                }
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
        .onReceive(coordinator.audioPlayback.$currentlyPlayingURL) { url in
            updateCurrentlyPlayingChunk(url: url)
        }
    }
    
    private var isPlayingFirstChunk: Bool {
        guard let firstChunk = session.chunks.first else { return false }
        return coordinator.audioPlayback.currentlyPlayingURL == firstChunk.fileURL 
            && coordinator.audioPlayback.isPlaying
    }
    
    private var groupedByChunk: [(chunkIndex: Int, text: String)] {
        // Group segments by chunk and combine text
        var groups: [Int: [TranscriptSegment]] = [:]
        
        for segment in transcriptSegments {
            for (index, chunk) in session.chunks.enumerated() {
                if segment.audioChunkID == chunk.id {
                    groups[index, default: []].append(segment)
                    break
                }
            }
        }
        
        return groups.keys.sorted().map { chunkIndex in
            let segments = groups[chunkIndex] ?? []
            let text = segments.map { $0.text }.joined(separator: " ")
            return (chunkIndex, text)
        }
    }
    
    private func loadTranscription() async {
        print("📄 [SessionDetailView] Loading transcription for session \(session.sessionId)")
        isLoading = true
        loadError = nil
        
        do {
            transcriptSegments = try await coordinator.fetchSessionTranscript(sessionId: session.sessionId)
            print("📄 [SessionDetailView] Loaded \(transcriptSegments.count) transcript segments")
        } catch {
            print("❌ [SessionDetailView] Failed to load transcription: \(error)")
            loadError = error.localizedDescription
        }
        
        // Load sentiment for this session
        do {
            sessionSentiment = try await coordinator.fetchSessionSentiment(sessionId: session.sessionId)
        } catch {
            print("❌ [SessionDetailView] Failed to load sentiment: \(error)")
        }
        
        // Load dominant language for this session
        do {
            sessionLanguage = try await coordinator.fetchSessionLanguage(sessionId: session.sessionId)
        } catch {
            print("❌ [SessionDetailView] Failed to load language: \(error)")
        }
        
        isLoading = false
    }
    
    private func updateCurrentlyPlayingChunk(url: URL?) {
        guard let url = url else {
            currentlyPlayingChunkIndex = nil
            return
        }
        
        currentlyPlayingChunkIndex = session.chunks.firstIndex { $0.fileURL == url }
    }
    
    private func playChunk(at index: Int) {
        guard index < session.chunks.count else { return }
        let chunk = session.chunks[index]
        
        if coordinator.audioPlayback.currentlyPlayingURL == chunk.fileURL && coordinator.audioPlayback.isPlaying {
            coordinator.audioPlayback.pause()
        } else if coordinator.audioPlayback.currentlyPlayingURL == chunk.fileURL {
            coordinator.audioPlayback.resume()
        } else {
            coordinator.audioPlayback.play(url: chunk.fileURL)
        }
        
        currentlyPlayingChunkIndex = index
    }
    
    private func playSession() {
        // For now, play first chunk. Future: implement sequential playback
        playChunk(at: 0)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return "\(seconds)s"
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Chunk Card

struct ChunkCard: View {
    let chunk: AudioChunk
    let index: Int
    let isPlaying: Bool
    let onPlay: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Part \(index + 1)")
                    .font(.headline)
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(formatDuration(chunk.duration))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    Text(chunk.startTime, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
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
    
    // MARK: - Sentiment Helpers
    
    private func sentimentEmoji(_ score: Double) -> String {
        switch score {
        case ..<(-0.5): return "😢"
        case -0.5..<(-0.2): return "😔"
        case -0.2..<0.2: return "😐"
        case 0.2..<0.5: return "🙂"
        default: return "😊"
        }
    }
    
    private func sentimentCategory(_ score: Double) -> String {
        switch score {
        case ..<(-0.3): return "Negative"
        case -0.3..<0.3: return "Neutral"
        default: return "Positive"
        }
    }
    
    private func sentimentColor(_ score: Double) -> Color {
        switch score {
        case ..<(-0.3): return .red
        case -0.3..<0.3: return .gray
        default: return .green
        }
    }
}

// MARK: - Info Row

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
