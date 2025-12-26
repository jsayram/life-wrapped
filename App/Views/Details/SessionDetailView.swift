import SwiftUI
import SharedModels
import Summarization
import Charts


struct SessionDetailView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.colorScheme) var colorScheme
    let session: RecordingSession
    
    @State private var transcriptSegments: [TranscriptSegment] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var currentlyPlayingChunkIndex: Int?
    @State private var playbackUpdateTimer: Timer?
    @State private var forceUpdateTrigger = false
    @State private var isTranscriptionComplete = false
    @State private var transcriptionCheckTimer: Timer?
    @State private var sessionSummary: Summary?
    @State private var summaryLoadError: String?
    @State private var scrubbedTime: TimeInterval = 0
    
    // Session metadata
    @State private var sessionTitle: String = ""
    @State private var sessionNotes: String = ""
    @State private var initialSessionNotes: String = ""  // Track initial notes to detect changes
    @State private var isFavorite: Bool = false
    @State private var isEditingTitle: Bool = false
    @State private var isEditingNotes: Bool = false
    
    // Transcript editing
    @State private var editingSegmentId: UUID?
    @State private var editedText: String = ""
    @State private var transcriptWasEdited: Bool = false
    @State private var editedChunkIds: Set<UUID> = []  // Track which chunks were edited
    @State private var isRegeneratingSummary: Bool = false
    @FocusState private var isTextFieldFocused: Bool
    
    // AI Generation progress
    @State private var generationProgress: Double = 0.0
    @State private var generationPhase: String = ""
    @State private var showGenerationOverlay = false
    @State private var activeEngineForGeneration: EngineTier?
    @State private var showRegenerateWithNotesAlert: Bool = false
    @State private var notesWereAppended: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Session Title Section (Editable)
                sessionTitleSection
                
                // Transcription Processing Banner
                processingBannerSection
                
                // Session Info Card
                sessionInfoSection
                
                // Playback Controls
                playbackControlsSection
                
                // Personal Notes Section (moved here from bottom)
                personalNotesSection
                
                // Transcription Section
                transcriptionSection
                
                // Session Summary Section (if available or error)
                if let summary = sessionSummary {
                    sessionSummarySection(summary: summary)
                } else if let error = summaryLoadError {
                    sessionSummaryErrorSection(error: error)
                } else if isTranscriptionComplete {
                    sessionSummaryPlaceholderSection
                }
            }
            .padding()
        }
        .navigationTitle(sessionTitle.isEmpty ? "Recording" : sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                toolbarButtons
            }
        }
        .task {
            await loadSessionMetadata()
            await loadTranscription()
            await loadSessionSummary()
            checkTranscriptionStatus()
        }
        .onAppear {
            startPlaybackUpdateTimer()
            startTranscriptionCheckTimer()
        }
        .onDisappear {
            stopPlaybackUpdateTimer()
            stopTranscriptionCheckTimer()
            if isPlayingThisSession {
                coordinator.audioPlayback.stop()
            }
        }
        .overlay {
            if showGenerationOverlay {
                aiGenerationOverlay
            }
        }
        .alert("Regenerate Summary with Notes?", isPresented: $showRegenerateWithNotesAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove Notes") {
                Task {
                    notesWereAppended = false
                    await regenerateSummary()
                }
            }
            Button("Re-append Notes") {
                Task {
                    await regenerateSummary(reappendNotes: true)
                }
            }
        } message: {
            Text("Your notes are currently appended to the summary. Would you like to regenerate and re-append them, or remove them?")
        }
    }
    
    // MARK: - Processing Banner
    
    @ViewBuilder
    private var processingBannerSection: some View {
        if !isTranscriptionComplete {
            let pendingCount = session.chunkCount - transcriptSegments.map({ $0.audioChunkID }).uniqueCount
            HStack(spacing: 12) {
                ProgressView()
                    .tint(AppTheme.purple)
                    .scaleEffect(0.8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Processing Transcription...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(pendingCount) of \(session.chunkCount) chunks pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    Task { await refreshSession() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                        .foregroundStyle(AppTheme.purple)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(
                RadialGradient(
                    colors: [AppTheme.purple.opacity(0.15), AppTheme.purple.opacity(0.05)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 100
                )
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.purple.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Session Info Section
    
    private var sessionInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Details")
                .font(.headline)
            
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
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardGradient(for: colorScheme))
                .allowsHitTesting(false)
        )
        .cornerRadius(12)
    }
    
    // MARK: - Toolbar Buttons
    
    private var toolbarButtons: some View {
        HStack(spacing: 16) {
            Button {
                Task {
                    do {
                        isFavorite = try await coordinator.toggleSessionFavorite(sessionId: session.sessionId)
                    } catch {
                        print("❌ Failed to toggle favorite: \(error)")
                    }
                }
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            
            ShareLink(item: transcriptText) {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(transcriptSegments.isEmpty)
        }
    }
    
    // MARK: - Playback Controls Section
    
    private var playbackControlsSection: some View {
        VStack(spacing: 16) {
            scrubberSlider
            timeDisplayRow
            playPauseButton
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
    
    private var waveformView: some View {
        Canvas { canvasContext, size in
            let centerY = size.height / 2
            let barCount = 80
            let barWidth = size.width / CGFloat(barCount)
            let maxBarHeight = size.height * 0.8
            
            // Calculate amplitude for each bar based on transcript segments
            let totalDuration = session.totalDuration
            
            for i in 0..<barCount {
                let barStartTime = (Double(i) / Double(barCount)) * totalDuration
                let barEndTime = (Double(i + 1) / Double(barCount)) * totalDuration
                
                // Check if any transcript segments overlap with this bar's time range
                var hasContent = false
                for segment in transcriptSegments {
                    let segmentStart = segment.startTime
                    let segmentEnd = segment.startTime + (segment.duration ?? 1.0)
                    
                    if (segmentStart <= barEndTime && segmentEnd >= barStartTime) {
                        hasContent = true
                        break
                    }
                }
                
                // Calculate bar height (tall where speech exists, short elsewhere)
                let barHeight: CGFloat
                if hasContent {
                    // Add variation for visual interest
                    let variation = sin(Double(i) * 0.5) * 0.3 + 0.7
                    barHeight = maxBarHeight * CGFloat(variation)
                } else {
                    barHeight = 4.0 // Minimal height for silence
                }
                
                let x = CGFloat(i) * barWidth
                let y = centerY - barHeight / 2
                
                let barRect = CGRect(x: x, y: y, width: max(barWidth - 1, 1), height: barHeight)
                let barPath = Path(roundedRect: barRect, cornerRadius: barWidth / 2)
                
                // Color based on playback state
                let color: Color
                if isPlayingThisSession && coordinator.audioPlayback.isPlaying {
                    let progress = totalDuration > 0 ? totalElapsedTime / totalDuration : 0
                    let barProgress = Double(i) / Double(barCount)
                    color = barProgress <= progress ? AppTheme.magenta : AppTheme.purple.opacity(0.5)
                } else {
                    color = AppTheme.purple.opacity(0.4)
                }
                
                canvasContext.fill(barPath, with: .color(color))
            }
            
            // Draw playhead indicator if playing
            if isPlayingThisSession {
                let progress = session.totalDuration > 0 ? totalElapsedTime / session.totalDuration : 0
                let playheadX = size.width * progress
                
                let playheadPath = Path { path in
                    path.move(to: CGPoint(x: playheadX, y: 0))
                    path.addLine(to: CGPoint(x: playheadX, y: size.height))
                }
                
                canvasContext.stroke(playheadPath, with: .color(AppTheme.magenta), lineWidth: 3)
            }
        }
        .frame(height: 100)
    }
    
    private var scrubberSlider: some View {
        // Force slider to update by using forceUpdateTrigger
        let _ = forceUpdateTrigger
        
        return Slider(
            value: Binding(
                get: { 
                    let value = isPlayingThisSession ? totalElapsedTime : scrubbedTime
                    return value
                },
                set: { newValue in
                    if isPlayingThisSession {
                        seekToTotalTime(newValue)
                    } else {
                        scrubbedTime = newValue
                    }
                }
            ),
            in: 0...max(session.totalDuration, 0.1)
        )
        .tint(AppTheme.purple)
    }
    
    private var timeDisplayRow: some View {
        HStack {
            Text(formatTime(isPlayingThisSession ? totalElapsedTime : scrubbedTime))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            
            Spacer()
            
            if isPlayingThisSession, let currentURL = coordinator.audioPlayback.currentlyPlayingURL,
               let idx = session.chunks.firstIndex(where: { $0.fileURL == currentURL }) {
                Text("Part \(idx + 1) of \(session.chunkCount)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.purple)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            Text(formatTime(session.totalDuration))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
    
    private var playPauseButton: some View {
        Button { playSession() } label: {
            let isCurrentlyPlaying = isPlayingThisSession && coordinator.audioPlayback.isPlaying
            
            HStack(spacing: 16) {
                // Icon in a circular background
                ZStack {
                    Circle()
                        .fill(AppTheme.purple.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.purple)
                }
                
                // Text label
                VStack(alignment: .leading, spacing: 4) {
                    if isCurrentlyPlaying {
                        Text("Pause")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    } else if isPlayingThisSession {
                        Text("Resume")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    } else {
                        Text(session.chunkCount > 1 ? "Play All \(session.chunkCount) Parts" : "Play Recording")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    
                    Text(formatTime(session.totalDuration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(AppTheme.purple.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Transcription Section
    
    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - just the title
            Text("Recording Transcript")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            
            // Content directly below header
            transcriptionContent
                .padding(.horizontal, 12)
            
            // Action buttons at the bottom (only if there's content)
            if !transcriptSegments.isEmpty {
                HStack(spacing: 12) {
                    Spacer()
                    
                    // Copy all button
                    Button {
                        UIPasteboard.general.string = transcriptText
                        coordinator.showSuccess("Transcript copied")
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                                .font(.body)
                            Text("Copy All")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.skyBlue)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    RadialGradient(
                                        colors: [AppTheme.skyBlue.opacity(0.15), AppTheme.skyBlue.opacity(0.05)],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 50
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    LinearGradient(
                                        colors: [AppTheme.skyBlue.opacity(0.4), AppTheme.skyBlue.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    // Share button
                    ShareLink(item: transcriptText) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body)
                            Text("Share")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.skyBlue)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    RadialGradient(
                                        colors: [AppTheme.skyBlue.opacity(0.15), AppTheme.skyBlue.opacity(0.05)],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 50
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    LinearGradient(
                                        colors: [AppTheme.skyBlue.opacity(0.4), AppTheme.purple.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            } else {
                Spacer().frame(height: 12)
            }
        }
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardGradient(for: colorScheme))
                .allowsHitTesting(false)
        )
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var transcriptionContent: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(AppTheme.purple)
                Text("Loading transcription...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else if let error = loadError {
            Text("Error: \(error)")
                .foregroundStyle(.red)
                .font(.subheadline)
                .padding(.vertical, 8)
        } else if transcriptSegments.isEmpty {
            transcriptionEmptyState
        } else {
            transcriptionSegmentsList
        }
    }
    
    @ViewBuilder
    private var transcriptionEmptyState: some View {
        let chunkIds = Set(session.chunks.map { $0.id })
        let hasTranscribing = !chunkIds.isDisjoint(with: coordinator.transcribingChunkIds)
        let hasFailed = !chunkIds.isDisjoint(with: coordinator.failedChunkIds)
        
        if hasTranscribing {
            ContentUnavailableView(
                "Transcribing Audio...",
                systemImage: "waveform.path",
                description: Text("Your audio is being processed. This may take a moment.")
            )
            .padding(.vertical, 8)
        } else if hasFailed {
            ContentUnavailableView(
                "Transcription Failed",
                systemImage: "exclamationmark.triangle",
                description: Text("Unable to transcribe this recording. Try recording again.")
            )
            .padding(.vertical, 8)
        } else {
            ContentUnavailableView(
                "No Transcript",
                systemImage: "doc.text.slash",
                description: Text("No transcription available for this recording.")
            )
            .padding(.vertical, 8)
        }
    }
    
    private var transcriptionSegmentsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groupedSegmentsByChunk, id: \.chunkIndex) { group in
                let chunkId = session.chunks[safe: group.chunkIndex]?.id
                TranscriptChunkView(
                    chunkIndex: group.chunkIndex,
                    segments: group.segments,
                    session: session,
                    isCurrentChunk: isPlayingThisSession && currentChunkIndex == group.chunkIndex,
                    chunkId: chunkId,
                    coordinator: coordinator,
                    isEdited: chunkId.map { editedChunkIds.contains($0) } ?? false,
                    onSeekToChunk: { seekToChunk(group.chunkIndex) },
                    onTextEdited: { segmentId, newText in
                        if let chunkId = chunkId {
                            editedChunkIds.insert(chunkId)
                        }
                        saveTranscriptEdit(segmentId: segmentId, newText: newText)
                    }
                )
            }
            
            // Show regenerate prompt if transcript was edited
            if transcriptWasEdited && sessionSummary != nil {
                regenerateSummaryPrompt
            }
        }
    }
    
    private var regenerateSummaryPrompt: some View {
        HStack {
            Spacer()
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(AppTheme.magenta)
                    Text("Transcript was edited")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Text("The summary may be outdated. Would you like to regenerate it?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 12) {
                    // Dismiss button
                    Button {
                        transcriptWasEdited = false
                    } label: {
                        Text("Not Now")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    
                    // Regenerate button with loading state
                    Button {
                        Task {
                            await regenerateSummary()
                            transcriptWasEdited = false
                        }
                    } label: {
                        HStack {
                            if isRegeneratingSummary {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isRegeneratingSummary ? "Regenerating..." : "Regenerate Summary")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.magenta)
                    .disabled(isRegeneratingSummary)
                }
            }
            .padding()
            .background(
                RadialGradient(
                    colors: [AppTheme.magenta.opacity(0.15), AppTheme.magenta.opacity(0.05)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 100
                )
            )
            .cornerRadius(12)
            .frame(maxWidth: 400)
            Spacer()
        }
    }
    
    private func saveTranscriptEdit(segmentId: UUID, newText: String) {
        Task {
            do {
                try await coordinator.updateTranscriptText(segmentId: segmentId, newText: newText)
                transcriptWasEdited = true
                await loadTranscription()  // Refresh the segments
                coordinator.showSuccess("Transcript updated")
            } catch {
                print("❌ [SessionDetailView] Failed to save transcript edit: \(error)")
                coordinator.showError("Failed to save edit")
            }
        }
    }
    
    private func seekToChunk(_ chunkIndex: Int) {
        var targetTime: TimeInterval = 0
        for i in 0..<chunkIndex {
            targetTime += session.chunks[i].duration
        }
        seekToTotalTime(targetTime)
    }
    
    private func startPlaybackUpdateTimer() {
        stopPlaybackUpdateTimer()
        // Update at 30fps for smooth visual feedback (matches waveform animation)
        playbackUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { _ in
            Task { @MainActor in
                self.forceUpdateTrigger.toggle()
            }
        }
        // Add timer to common run loop mode to ensure it fires during UI interactions
        if let timer = playbackUpdateTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func stopPlaybackUpdateTimer() {
        playbackUpdateTimer?.invalidate()
        playbackUpdateTimer = nil
    }
    
    private func startTranscriptionCheckTimer() {
        // Check immediately
        checkTranscriptionStatus()
        
        // Then check every 2 seconds
        transcriptionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                self.checkTranscriptionStatus()
            }
        }
    }
    
    private func stopTranscriptionCheckTimer() {
        transcriptionCheckTimer?.invalidate()
        transcriptionCheckTimer = nil
    }
    
    private func checkTranscriptionStatus() {
        // Check using real-time status tracking from coordinator
        let chunkIds = Set(session.chunks.map { $0.id })
        
        // Check if any chunks are actively being transcribed right now
        let hasTranscribing = !chunkIds.isDisjoint(with: coordinator.transcribingChunkIds)
        
        // For chunks not actively transcribing, check if they have transcript segments
        // This handles both new transcriptions and previously completed ones
        let chunksWithTranscripts = Set(transcriptSegments.map { $0.audioChunkID })
        
        // A session is complete if:
        // 1. No chunks are currently being transcribed AND
        // 2. All chunks either have transcripts OR are marked as failed
        let allChunksAccountedFor = chunkIds.allSatisfy { chunkId in
            chunksWithTranscripts.contains(chunkId) || 
            coordinator.failedChunkIds.contains(chunkId)
        }
        
        let wasComplete = isTranscriptionComplete
        isTranscriptionComplete = !hasTranscribing && allChunksAccountedFor
        
        // If just completed, reload data and stop checking
        if !wasComplete && isTranscriptionComplete {
            Task {
                stopTranscriptionCheckTimer()
                // Reload transcription to get the latest segments
                await loadTranscription()
                // Load session summary
                await loadSessionSummary()
            }
        }
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
    
    private var groupedSegmentsByChunk: [(chunkIndex: Int, segments: [TranscriptSegment])] {
        // Group segments by chunk, preserving segment objects for editing
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
            (chunkIndex, groups[chunkIndex] ?? [])
        }
    }
    
    // Combined transcript text for sharing
    private var transcriptText: String {
        groupedByChunk.map { $0.text }.joined(separator: "\n\n")
    }
    
    // MARK: - Session Title Section
    
    private var sessionTitleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditingTitle {
                HStack {
                    TextField("Session Title", text: $sessionTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                        .focused($isTextFieldFocused)
                    
                    Button("Save") {
                        isEditingTitle = false
                        saveTitle()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.purple)
                    
                    Button("Cancel") {
                        isEditingTitle = false
                        sessionTitle = session.title ?? ""
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.skyBlue)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if !sessionTitle.isEmpty {
                            Text(sessionTitle)
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        
                        Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        isEditingTitle = true
                        isTextFieldFocused = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.title2)
                            .foregroundStyle(AppTheme.skyBlue)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Session Summary Section
    
    private var sessionSummaryPlaceholderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recording Chunks")
                    .font(.headline)
                
                Spacer()
                
                // Generate button
                Button {
                    Task {
                        await regenerateSummary()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isRegeneratingSummary {
                            ProgressView()
                                .tint(AppTheme.purple)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.body)
                        }
                        Text("Generate")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.darkPurple, AppTheme.magenta],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.purple.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.purple.opacity(0.4), AppTheme.magenta.opacity(0.3)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRegeneratingSummary)
            }
            
            if isRegeneratingSummary {
                HStack {
                    ProgressView()
                        .tint(AppTheme.purple)
                    Text("Generating AI summary...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } else {
                Text("Summary not yet generated. Tap Generate to create an AI summary of this recording.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
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
    
    private func sessionSummaryErrorSection(error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recording Summary")
                    .font(.headline)
                
                Spacer()
                
                // Retry button
                Button {
                    Task {
                        await regenerateSummary()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isRegeneratingSummary {
                            ProgressView()
                                .tint(.orange)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.body)
                        }
                        Text("Retry")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                Color.orange.opacity(0.4),
                                lineWidth: 1.5
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRegeneratingSummary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Summary Generation Failed")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if error.contains("API key") {
                    Text("Go to Settings → AI & Intelligence to add your API key.")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
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
    
    private func sessionSummarySection(summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recording Summary")
                    .font(.headline)
                
                Spacer()
                
                // Copy button
                Button {
                    UIPasteboard.general.string = summary.text
                    coordinator.showSuccess("Summary copied to clipboard")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                        .foregroundStyle(AppTheme.skyBlue)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppTheme.skyBlue.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    LinearGradient(
                                        colors: [AppTheme.skyBlue.opacity(0.4), AppTheme.purple.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Regenerate button
                Button {
                    Task {
                        // If notes were appended, ask user what to do
                        if notesWereAppended {
                            showRegenerateWithNotesAlert = true
                        } else {
                            await regenerateSummary()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isRegeneratingSummary {
                            ProgressView()
                                .tint(AppTheme.purple)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.body)
                        }
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.darkPurple, AppTheme.magenta],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.purple.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.purple.opacity(0.4), AppTheme.magenta.opacity(0.3)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRegeneratingSummary)
            }
            
            Text(summary.text)
                .font(.body)
                .foregroundStyle(.primary)
            
            // Show engine tier if available
            if let engineTier = summary.engineTier {
                HStack {
                    Image(systemName: engineIcon(for: engineTier))
                        .font(.caption)
                    Text("Generated by \(engineDisplayName(for: engineTier))")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 4)
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
    
    // MARK: - Additional Notes Section
    
    private var personalNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Additional Notes")
                    .font(.headline)
                
                Spacer()
                
                if isEditingNotes {
                    Button("Done") {
                        isEditingNotes = false
                        saveNotes()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        isEditingNotes = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.body)
                            .foregroundStyle(AppTheme.skyBlue)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppTheme.skyBlue.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        LinearGradient(
                                            colors: [AppTheme.skyBlue.opacity(0.4), AppTheme.skyBlue.opacity(0.3)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if isEditingNotes {
                TextEditor(text: $sessionNotes)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
            } else if sessionNotes.isEmpty {
                Text("Tap the pencil to add additional notes...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Text(sessionNotes)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            
            // Subtle button to append notes to summary
            if shouldShowRegenerateWithNotesButton {
                Button {
                    Task {
                        await regenerateSummaryWithNotes()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                        Text("Append to Summary")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(AppTheme.purple)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.purple.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.purple.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
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
    
    /// Show regenerate button only if: notes exist, summary exists, and notes changed after summary
    private var shouldShowRegenerateWithNotesButton: Bool {
        !sessionNotes.isEmpty &&
        sessionSummary != nil &&
        sessionNotes != initialSessionNotes
    }
    
    // MARK: - Helper Methods
    
    private func engineIcon(for tier: String) -> String {
        switch tier.lowercased() {
        case "apple": return "apple.intelligence"
        case "basic": return "bolt.fill"
        case "external": return "sparkles"
        case "rollup": return "arrow.triangle.merge"
        case "year wrap": return "sparkles"
        default: return "cpu"
        }
    }
    
    private func engineDisplayName(for tier: String) -> String {
        switch tier.lowercased() {
        case "apple": return "Apple Intelligence"
        case "basic": return "Basic"
        case "external": return "Year Wrapped Pro AI"
        case "rollup": return "Rollup"
        case "year wrap": return "Year Wrap"
        default: return tier.capitalized
        }
    }
    
    private func loadSessionMetadata() async {
        do {
            // Load metadata and track initial notes value
            let metadata = try await coordinator.fetchSessionMetadata(sessionId: session.sessionId)
            await MainActor.run {
                sessionTitle = metadata?.title ?? ""
                sessionNotes = metadata?.notes ?? ""
                initialSessionNotes = metadata?.notes ?? ""  // Track initial state
                isFavorite = metadata?.isFavorite ?? false
            }
        } catch {
            print("❌ [SessionDetailView] Failed to load metadata: \(error)")
        }
    }
    
    private func saveNotes() {
        Task {
            do {
                try await coordinator.updateSessionNotes(
                    sessionId: session.sessionId,
                    notes: sessionNotes.isEmpty ? nil : sessionNotes
                )
            } catch {
                print("❌ [SessionDetailView] Failed to save notes: \(error)")
            }
        }
    }
    
    private func regenerateSummaryWithNotes() async {
        guard !sessionNotes.isEmpty else { return }
        
        print("📝 [SessionDetailView] Appending notes to existing summary...")
        
        do {
            // Call coordinator to append notes
            try await coordinator.appendNotesToSessionSummary(sessionId: session.sessionId, notes: sessionNotes)
            
            print("✅ [SessionDetailView] Successfully appended notes to summary")
            
            // Reload summary to show changes
            await loadSessionSummary()
            
            // Mark that notes were incorporated and appended
            initialSessionNotes = sessionNotes
            notesWereAppended = true
            
            coordinator.showSuccess("Notes appended to summary")
        } catch {
            print("❌ [SessionDetailView] Failed to append notes to summary: \(error)")
            summaryLoadError = error.localizedDescription
            coordinator.showError("Failed to append notes")
        }
    }
    
    private func saveTitle() {
        Task {
            do {
                let titleToSave = sessionTitle.isEmpty ? nil : sessionTitle
                try await coordinator.updateSessionTitle(sessionId: session.sessionId, title: titleToSave)
                coordinator.showSuccess("Title saved")
            } catch {
                print("❌ [SessionDetailView] Failed to save title: \(error)")
            }
        }
    }
    
    private func regenerateSummary(reappendNotes: Bool = false) async {
        isRegeneratingSummary = true
        summaryLoadError = nil
        
        // Get active engine to customize overlay message
        guard let summCoord = coordinator.summarizationCoordinator else { return }
        let activeEngine = await summCoord.getActiveEngine()
        activeEngineForGeneration = activeEngine
        
        // Show overlay for all engines with different messages
        showGenerationOverlay = true
        generationProgress = 0.0
        
        // Set initial phase based on engine
        switch activeEngine {
        case .basic:
            generationPhase = "Processing transcript..."
        case .local:
            generationPhase = "Running local AI model..."
        case .apple:
            generationPhase = "Preparing..."
        case .external:
            generationPhase = "Connecting to AI service..."
        }
        
        defer { 
            isRegeneratingSummary = false
            showGenerationOverlay = false
        }
        
        do {
            // Force regeneration if transcript was edited, otherwise check cache
            let forceRegenerate = transcriptWasEdited
            
            // Start progress simulation with engine-specific phases
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                if !Task.isCancelled && showGenerationOverlay {
                    generationProgress = 0.1
                    switch activeEngine {
                    case .basic:
                        generationPhase = "Extracting key information..."
                    case .local:
                        generationPhase = "Loading local AI model..."
                    case .apple:
                        generationPhase = "Loading on-device AI model..."
                    case .external:
                        generationPhase = "Uploading transcript securely..."
                    }
                }
                
                try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s
                if !Task.isCancelled && showGenerationOverlay {
                    generationProgress = 0.3
                    switch activeEngine {
                    case .basic:
                        generationPhase = "Analyzing content..."
                    case .local:
                        generationPhase = "Running inference..."
                    case .apple:
                        generationPhase = "Analyzing transcript..."
                    case .external:
                        generationPhase = "AI analyzing your transcript..."
                    }
                }
                
                try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s
                if !Task.isCancelled && showGenerationOverlay {
                    generationProgress = 0.5
                    switch activeEngine {
                    case .basic:
                        generationPhase = "Identifying main topics..."
                    case .local:
                        generationPhase = "Processing with Phi-3.5..."
                    case .apple:
                        generationPhase = "Processing key points..."
                    case .external:
                        generationPhase = "Generating intelligent insights..."
                    }
                }
                
                try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s
                if !Task.isCancelled && showGenerationOverlay {
                    generationProgress = 0.7
                    switch activeEngine {
                    case .basic:
                        generationPhase = "Creating summary..."
                    case .local:
                        generationPhase = "Generating local summary..."
                    case .apple:
                        generationPhase = "Generating summary..."
                    case .external:
                        generationPhase = "Crafting comprehensive summary..."
                    }
                }
                
                try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s
                if !Task.isCancelled && showGenerationOverlay {
                    generationProgress = 0.9
                    generationPhase = "Finalizing..."
                }
            }
            
            // Actual generation (notes are never passed to AI anymore)
            try await coordinator.generateSessionSummary(
                sessionId: session.sessionId, 
                forceRegenerate: true,
                includeNotes: false
            )
            
            // If requested, re-append notes after regeneration
            if reappendNotes && !sessionNotes.isEmpty {
                try? await coordinator.appendNotesToSessionSummary(sessionId: session.sessionId, notes: sessionNotes)
                notesWereAppended = true
            } else {
                notesWereAppended = false
            }
            
            generationProgress = 1.0
            generationPhase = "Complete!"
            
            await loadSessionSummary()
            // Reset edit tracking after summary is regenerated
            editedChunkIds.removeAll()
            transcriptWasEdited = false
            
            try? await Task.sleep(nanoseconds: 500_000_000) // Show complete state briefly
            
            // Show success with engine used
            if let summary = sessionSummary {
                let engineName = summary.engineTier ?? "AI"
                coordinator.showSuccess("Summary generated with \(engineName)")
            } else {
                coordinator.showSuccess("Summary generated")
            }
        } catch {
            print("❌ [SessionDetailView] Failed to regenerate summary: \(error)")
            summaryLoadError = error.localizedDescription
            
            // Better error messaging
            if error.localizedDescription.contains("internet") || error.localizedDescription.contains("network") {
                coordinator.showError("Network error. Using offline summary.")
            } else if error.localizedDescription.contains("API key") {
                coordinator.showError("API key required for external AI")
            } else {
                coordinator.showError("Failed to generate summary")
            }
        }
    }

    private var isPlayingThisSession: Bool {
        // Check if any chunk from this session is currently playing
        guard let currentURL = coordinator.audioPlayback.currentlyPlayingURL else { return false }
        return session.chunks.contains { $0.fileURL == currentURL }
    }
    
    private var currentChunkIndex: Int? {
        // Get the index of the currently playing chunk
        guard let currentURL = coordinator.audioPlayback.currentlyPlayingURL else { return nil }
        return session.chunks.firstIndex { $0.fileURL == currentURL }
    }
    
    // Generate consistent waveform heights (seeded for consistency)
    private func waveformHeight(for index: Int) -> CGFloat {
        let seed = Double(index) * 0.12345
        let height = sin(seed) * sin(seed * 2.3) * sin(seed * 1.7)
        return 20 + abs(height) * 40
    }
    
    // Calculate total elapsed time across all chunks
    private var totalElapsedTime: TimeInterval {
        // Use forceUpdateTrigger to ensure UI updates
        _ = forceUpdateTrigger
        
        guard isPlayingThisSession,
              let currentURL = coordinator.audioPlayback.currentlyPlayingURL,
              let currentChunkIndex = session.chunks.firstIndex(where: { $0.fileURL == currentURL }) else {
            return 0
        }
        
        // Sum durations of all previous chunks
        var elapsed: TimeInterval = 0
        for i in 0..<currentChunkIndex {
            elapsed += session.chunks[i].duration
        }
        
        // Add current chunk's progress
        elapsed += coordinator.audioPlayback.currentTime
        
        return elapsed
    }
    
    // Calculate playback progress as percentage (0.0 to 1.0)
    private var playbackProgress: Double {
        // Use forceUpdateTrigger to ensure UI updates
        _ = forceUpdateTrigger
        
        guard session.totalDuration > 0 else { return 0 }
        
        if isPlayingThisSession {
            return totalElapsedTime / session.totalDuration
        } else {
            return 0
        }
    }
    
    // Seek to a specific time in the total session
    private func seekToTotalTime(_ targetTime: TimeInterval) {
        var remainingTime = targetTime
        
        // Find which chunk contains this time
        for (index, chunk) in session.chunks.enumerated() {
            if remainingTime <= chunk.duration {
                // Check if we're already in this chunk
                if let currentURL = coordinator.audioPlayback.currentlyPlayingURL,
                   session.chunks[index].fileURL == currentURL {
                    // Same chunk - just seek within it
                    coordinator.audioPlayback.seek(to: remainingTime)
                } else {
                    // Different chunk - restart playback from this chunk
                    let chunkURLs = session.chunks.map { $0.fileURL }
                    let wasPlaying = coordinator.audioPlayback.isPlaying
                    
                    Task {
                        try await coordinator.audioPlayback.playSequence(urls: Array(chunkURLs.dropFirst(index))) {
                            print("✅ [SessionDetailView] Session playback completed after seek")
                        }
                        
                        // Seek within this chunk immediately for smooth scrubbing
                        // Minimal delay to ensure player is initialized
                        try? await Task.sleep(for: .milliseconds(10))
                        coordinator.audioPlayback.seek(to: remainingTime)
                        
                        // If wasn't playing before, pause immediately after seeking
                        if !wasPlaying {
                            coordinator.audioPlayback.pause()
                        }
                    }
                }
                
                return
            }
            
            remainingTime -= chunk.duration
        }
    }
    
    // MARK: - AI Generation Overlay
    
    private var aiGenerationOverlay: some View {
        ZStack {
            // Adaptive blurred background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .blur(radius: 2)
            
            VStack(spacing: 24) {
                // CPU icon with animation
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.purple.opacity(0.3), AppTheme.magenta.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .scaleEffect(1.0 + generationProgress * 0.2)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: generationProgress)
                    
                    Image(systemName: "cpu")
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.purple, AppTheme.magenta],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(spacing: 12) {
                    Text(activeEngineForGeneration == .basic ? "Processing" : "AI Processing")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    // Progress bar
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 280, height: 8)
                        
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.purple, AppTheme.magenta],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 280 * generationProgress, height: 8)
                            .animation(.linear(duration: 0.3), value: generationProgress)
                    }
                    
                    // Percentage
                    Text("\(Int(generationProgress * 100))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    
                    // Current phase
                    Text(generationPhase)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 20)
                }
                
                // Info box with engine-specific message
                if let engineTier = activeEngineForGeneration {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(AppTheme.skyBlue)
                            Text(engineTier == .basic ? "What's happening?" : "Why does this take time?")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                        }
                        
                        // Engine-specific description
                        Group {
                            switch engineTier {
                            case .basic:
                                Text("Life Wrapped is creating a basic summary by extracting key information from your transcript. This is a simple, fast process that works offline.")
                            case .local:
                                Text("Life Wrapped is using Phi-3.5, a powerful local AI model running directly on your device. This provides high-quality summaries while keeping all your data private.")
                            case .apple:
                                Text("Life Wrapped performs a comprehensive analysis directly on your iPhone using Apple Intelligence. No data leaves your device — it's completely private.")
                            case .external:
                                let provider = UserDefaults.standard.string(forKey: "externalAPIProvider") ?? "OpenAI"
                                Text("Life Wrapped uses \(provider)'s advanced AI to perform intelligent processing and generate the best possible summary of your transcript. This provides the most comprehensive and insightful analysis.")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Once complete, future views of this session are instant!")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground).opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [AppTheme.purple.opacity(0.5), AppTheme.magenta.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 40)
        }
    }
    
    private func loadSessionSummary() async {
        summaryLoadError = nil
        do {
            sessionSummary = try await coordinator.fetchSessionSummary(sessionId: session.sessionId)
            if sessionSummary != nil {
                print("✨ [SessionDetailView] Loaded session summary")
            } else {
                print("ℹ️ [SessionDetailView] No session summary found (not yet generated)")
                summaryLoadError = "Summary not yet generated. Transcription must complete first."
            }
        } catch {
            print("❌ [SessionDetailView] Failed to load session summary: \(error)")
            summaryLoadError = error.localizedDescription
        }
    }
    
    private func loadTranscription() async {
        print("📄 [SessionDetailView] Loading transcription for session \(session.sessionId)")
        isLoading = true
        loadError = nil
        
        do {
            transcriptSegments = try await coordinator.fetchSessionTranscript(sessionId: session.sessionId)
            print("📄 [SessionDetailView] Loaded \(transcriptSegments.count) transcript segments")
            
            // Debug: Log which chunks have transcripts
            let chunksWithTranscripts = Set(transcriptSegments.map { $0.audioChunkID })
            for chunk in session.chunks {
                let hasTranscript = chunksWithTranscripts.contains(chunk.id)
                let isTranscribing = coordinator.transcribingChunkIds.contains(chunk.id)
                let isFailed = coordinator.failedChunkIds.contains(chunk.id)
                print("📄 [SessionDetailView] Chunk \(chunk.chunkIndex): hasTranscript=\(hasTranscript), transcribing=\(isTranscribing), failed=\(isFailed)")
            }
        } catch {
            print("❌ [SessionDetailView] Failed to load transcription: \(error)")
            loadError = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func refreshSession() async {
        print("🔄 [SessionDetailView] Manually refreshing session...")
        
        // Reload transcription
        await loadTranscription()
        
        // Force transcription status check
        checkTranscriptionStatus()
        
        // Check if any chunks need to be queued for transcription
        let chunksWithTranscripts = Set(transcriptSegments.map { $0.audioChunkID })
        
        print("📊 [SessionDetailView] Chunk analysis:")
        print("   - Total chunks in session: \(session.chunks.count)")
        print("   - Chunks with transcripts: \(chunksWithTranscripts.count)")
        print("   - Currently transcribing: \(coordinator.transcribingChunkIds.count)")
        print("   - Failed: \(coordinator.failedChunkIds.count)")
        
        for chunk in session.chunks {
            let hasTranscript = chunksWithTranscripts.contains(chunk.id)
            let isTranscribing = coordinator.transcribingChunkIds.contains(chunk.id)
            let isFailed = coordinator.failedChunkIds.contains(chunk.id)
            let isTranscribed = coordinator.transcribedChunkIds.contains(chunk.id)
            
            print("   - Chunk \(chunk.chunkIndex): transcript=\(hasTranscript), transcribing=\(isTranscribing), transcribed=\(isTranscribed), failed=\(isFailed)")
            
            if !hasTranscript && !isTranscribing && !isFailed {
                print("🚨 [SessionDetailView] Chunk \(chunk.chunkIndex) is ORPHANED - forcing into transcription queue")
                // Force this chunk into transcription by calling retry
                // This will add it to pendingTranscriptionIds and start processing
                await coordinator.retryTranscription(chunkId: chunk.id)
            }
        }
        
        // Wait a bit and reload again
        try? await Task.sleep(for: .seconds(1))
        await loadTranscription()
        checkTranscriptionStatus()
    }
    
    private func playSession() {
        // Trigger haptic feedback
        coordinator.triggerHaptic(.medium)
        
        if isPlayingThisSession {
            // Pause if playing
            if coordinator.audioPlayback.isPlaying {
                coordinator.audioPlayback.pause()
            } else {
                coordinator.audioPlayback.resume()
            }
        } else {
            // Start sequential playback of all chunks
            let chunkURLs = session.chunks.map { $0.fileURL }
            print("🎵 [SessionDetailView] Starting playback of \(chunkURLs.count) chunks")
            
            // If user has scrubbed before playing, seek to that position
            if scrubbedTime > 0 {
                Task {
                    try await coordinator.audioPlayback.playSequence(urls: chunkURLs) {
                        print("✅ [SessionDetailView] Session playback completed")
                    }
                    // Seek to scrubbed position after playback starts
                    try? await Task.sleep(for: .milliseconds(50))
                    seekToTotalTime(scrubbedTime)
                }
            } else {
                Task {
                    try await coordinator.audioPlayback.playSequence(urls: chunkURLs) {
                        print("✅ [SessionDetailView] Session playback completed")
                    }
                }
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
}
