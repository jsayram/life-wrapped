// =============================================================================
// ContentView — Main app interface
// =============================================================================

import SwiftUI
import SharedModels

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var selectedTab = 0
    
    init() {
        print("🖼️ [ContentView] Initializing ContentView")
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTab()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            HistoryTab()
                .tabItem {
                    Label("History", systemImage: "list.bullet")
                }
                .tag(1)
            
            InsightsTab()
                .tabItem {
                    Label("Insights", systemImage: "chart.bar.fill")
                }
                .tag(2)
            
            SettingsTab()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .sheet(isPresented: $coordinator.needsPermissions) {
            PermissionsView()
                .interactiveDismissDisabled()
        }
        .toast($coordinator.currentToast)
        .overlay {
            if !coordinator.isInitialized && coordinator.initializationError == nil && !coordinator.needsPermissions {
                LoadingOverlay()
            }
        }
        .alert("Initialization Error", isPresented: .constant(coordinator.initializationError != nil)) {
            Button("Retry") {
                Task {
                    await coordinator.initialize()
                }
            }
        } message: {
            if let error = coordinator.initializationError {
                Text(error.localizedDescription)
            }
        }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                
                Text("Loading Life Wrapped...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Home Tab

struct HomeTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Streak Card
                    StreakCard(streak: coordinator.currentStreak)
                    
                    // Recording Button
                    RecordingButton()
                    
                    // Today's Stats
                    TodayStatsCard(stats: coordinator.todayStats)
                    
                    Spacer()
                }
                .padding()
            }
            .refreshable {
                await refreshStats()
            }
            .navigationTitle("Life Wrapped")
        }
    }
    
    private func refreshStats() async {
        print("🔄 [HomeTab] Manual refresh triggered")
        await coordinator.refreshTodayStats()
        await coordinator.refreshStreak()
        print("✅ [HomeTab] Stats refreshed")
    }
}

// MARK: - Streak Card

struct StreakCard: View {
    let streak: Int
    
    var body: some View {
        HStack(spacing: 16) {
            Text("🔥")
                .font(.system(size: 40))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(streak) Day Streak")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(streakMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var streakMessage: String {
        if streak == 0 {
            return "Start journaling to begin!"
        } else if streak == 1 {
            return "Great start! Keep it going!"
        } else if streak < 7 {
            return "Building momentum!"
        } else if streak < 30 {
            return "Amazing consistency!"
        } else {
            return "Incredible dedication!"
        }
    }
}

// MARK: - Recording Button

struct RecordingButton: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var recordingDuration: TimeInterval = 0
    
    // Timer that fires every 0.1 seconds to update the recording duration
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 16) {
            Button(action: handleRecordingAction) {
                ZStack {
                    Circle()
                        .fill(buttonColor)
                        .frame(width: 120, height: 120)
                    
                    if coordinator.recordingState.isProcessing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                    } else {
                        Image(systemName: buttonIcon)
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(coordinator.recordingState.isProcessing)
            .scaleEffect(coordinator.recordingState.isRecording ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), 
                      value: coordinator.recordingState.isRecording)
            
            Text(statusText)
                .font(.headline)
                .foregroundStyle(.secondary)
                .monospacedDigit() // Makes numbers consistent width for smooth timer display
        }
        .onReceive(timer) { _ in
            // Update recording duration every 0.1 seconds when recording
            if case .recording(let startTime) = coordinator.recordingState {
                recordingDuration = Date().timeIntervalSince(startTime)
            } else {
                recordingDuration = 0
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {
                coordinator.resetRecordingState()
            }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: coordinator.recordingState) { _, newState in
            if case .failed(let message) = newState {
                errorMessage = message
                showError = true
            }
        }
    }
    
    private var buttonColor: Color {
        switch coordinator.recordingState {
        case .idle: return .blue
        case .recording: return .red
        case .processing: return .orange
        case .completed: return .green
        case .failed: return .gray
        }
    }
    
    private var buttonIcon: String {
        switch coordinator.recordingState {
        case .idle: return "mic.fill"
        case .recording: return "stop.fill"
        case .processing: return "waveform"
        case .completed: return "checkmark"
        case .failed: return "xmark"
        }
    }
    
    private var statusText: String {
        switch coordinator.recordingState {
        case .idle: return "Tap to start recording"
        case .recording: 
            return "Recording... \(formatDuration(recordingDuration))"
        case .processing: return "Processing..."
        case .completed: return "Saved!"
        case .failed(let message): return message
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func handleRecordingAction() {
        print("🔘 [RecordingButton] Button tapped, current state: \(coordinator.recordingState)")
        
        // Haptic feedback on tap
        coordinator.triggerHaptic(.medium)
        
        Task {
            do {
                if coordinator.recordingState.isRecording {
                    print("⏹️ [RecordingButton] Stopping recording...")
                    _ = try await coordinator.stopRecording()
                    print("✅ [RecordingButton] Recording stopped")
                    coordinator.showSuccess("Recording saved successfully!")
                } else if case .idle = coordinator.recordingState {
                    print("▶️ [RecordingButton] Starting recording...")
                    try await coordinator.startRecording()
                    print("✅ [RecordingButton] Recording started")
                    coordinator.showInfo("Recording started")
                }
            } catch {
                print("❌ [RecordingButton] Action failed: \(error.localizedDescription)")
                coordinator.showError(error.localizedDescription)
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Today Stats Card

struct TodayStatsCard: View {
    let stats: DayStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 24) {
                StatItem(
                    icon: "doc.text.fill",
                    value: "\(stats.segmentCount)",
                    label: "Entries"
                )
                
                StatItem(
                    icon: "textformat.abc",
                    value: "\(stats.wordCount)",
                    label: "Words"
                )
                
                StatItem(
                    icon: "clock.fill",
                    value: "\(stats.totalMinutes)",
                    label: "Minutes"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - History Tab

struct HistoryTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var sessions: [RecordingSession] = []
    @State private var sessionWordCounts: [UUID: Int] = [:] // Cache word counts
    @State private var isLoading = true
    @State private var playbackError: String?
    
    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("History")
                .task {
                    await loadSessions()
                }
                .refreshable {
                    await loadSessions()
                }
                .alert("Playback Error", isPresented: .constant(playbackError != nil)) {
                    Button("OK") {
                        playbackError = nil
                    }
                } message: {
                    if let error = playbackError {
                        Text(error)
                    }
                }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if isLoading {
            ProgressView("Loading sessions...")
        } else if sessions.isEmpty {
            ContentUnavailableView(
                "No Recordings Yet",
                systemImage: "mic.slash",
                description: Text("Start recording to see your journal entries here.")
            )
        } else {
            sessionsList
        }
    }
    
    private var sessionsList: some View {
        List {
            ForEach(sortedDates, id: \.self) { date in
                Section(header: Text(formatSectionDate(date))) {
                    ForEach(groupedSessions[date] ?? [], id: \.id) { session in
                        NavigationLink(destination: sessionDetailView(for: session)) {
                            SessionRow(
                                session: session,
                                wordCount: sessionWordCounts[session.sessionId]
                            )
                        }
                    }
                    .onDelete { offsets in
                        deleteSession(at: offsets, in: date)
                    }
                }
            }
        }
    }
    
    private func sessionDetailView(for session: RecordingSession) -> some View {
        SessionDetailView(session: session)
    }
    
    /// Group sessions by date
    private var groupedSessions: [Date: [RecordingSession]] {
        Dictionary(grouping: sessions) { session in
            Calendar.current.startOfDay(for: session.startTime)
        }
    }
    
    /// Sorted dates (most recent first)
    private var sortedDates: [Date] {
        Array(groupedSessions.keys).sorted(by: >)
    }
    
    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
    
    private func loadSessions() async {
        isLoading = true
        do {
            sessions = try await coordinator.fetchRecentSessions(limit: 50)
            print("✅ [HistoryTab] Loaded \(sessions.count) sessions")
            
            // Load word counts in parallel for all sessions
            guard let dbManager = coordinator.getDatabaseManager() else { return }
            await withTaskGroup(of: (UUID, Int).self) { group in
                for session in sessions {
                    group.addTask {
                        let count = (try? await dbManager.fetchSessionWordCount(sessionId: session.sessionId)) ?? 0
                        return (session.sessionId, count)
                    }
                }
                
                for await (sessionId, wordCount) in group {
                    sessionWordCounts[sessionId] = wordCount
                }
            }
            print("✅ [HistoryTab] Loaded word counts for \(sessionWordCounts.count) sessions")
        } catch {
            print("❌ [HistoryTab] Failed to load sessions: \(error)")
        }
        isLoading = false
    }
    
    private func deleteSession(at offsets: IndexSet, in date: Date) {
        guard let sessionsForDate = groupedSessions[date] else { return }
        
        Task {
            for index in offsets {
                let session = sessionsForDate[index]
                // Stop playback if any chunk from this session is playing
                for chunk in session.chunks {
                    if coordinator.audioPlayback.currentlyPlayingURL == chunk.fileURL {
                        coordinator.audioPlayback.stop()
                        break
                    }
                }
                do {
                    try await coordinator.deleteSession(session.sessionId)
                    sessions.removeAll { $0.sessionId == session.sessionId }
                    sessionWordCounts.removeValue(forKey: session.sessionId)
                } catch {
                    print("Failed to delete session: \(error)")
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: RecordingSession
    let wordCount: Int?
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: session.chunkCount > 1 ? "waveform.circle.fill" : "waveform.circle")
                .font(.title2)
                .foregroundStyle(session.chunkCount > 1 ? .blue : .gray)
            
            VStack(alignment: .leading, spacing: 6) {
                // Time
                Text(session.startTime, style: .time)
                    .font(.headline)
                
                // Stats row
                HStack(spacing: 16) {
                    // Duration
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(formatDuration(session.totalDuration))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    
                    // Word count (if available)
                    if let words = wordCount, words > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "text.word.spacing")
                            Text("\(words) words")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    
                    // Chunk count (if multi-chunk)
                    if session.chunkCount > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "square.stack.3d.up")
                            Text("\(session.chunkCount) parts")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
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
}

struct RecordingRow: View {
    let recording: AudioChunk
    let isPlaying: Bool
    var showPlayButton: Bool = true
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(recording.startTime, style: .date)
                    .font(.headline)
                
                HStack(spacing: 16) {
                    Text(recording.startTime, style: .time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(formatDuration(recording.duration))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Play/Pause button (optional)
            if showPlayButton {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
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
}

// MARK: - Insights Tab

struct InsightsTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var summaries: [Summary] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading insights...")
                } else if summaries.isEmpty {
                    ContentUnavailableView(
                        "No Insights Yet",
                        systemImage: "chart.bar",
                        description: Text("Record more journal entries to unlock insights.")
                    )
                } else {
                    List(summaries, id: \.id) { summary in
                        SummaryRow(summary: summary)
                    }
                }
            }
            .navigationTitle("Insights")
            .task {
                await loadSummaries()
            }
            .refreshable {
                await loadSummaries()
            }
        }
    }
    
    private func loadSummaries() async {
        isLoading = true
        do {
            summaries = try await coordinator.fetchRecentSummaries(limit: 20)
        } catch {
            print("Failed to load summaries: \(error)")
        }
        isLoading = false
    }
}

struct SummaryRow: View {
    let summary: Summary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.periodType.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
                
                Spacer()
                
                Text(summary.periodStart, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(summary.text)
                .font(.body)
                .lineLimit(4)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    @State private var showDataManagement = false
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var databasePath: String?
    @State private var chunkDuration: Double = 180 // Default 3 minutes
    
    var body: some View {
        NavigationStack {
            List {
                Section("Recording") {
                    VStack(alignment: .leading, spacing: 8) {
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
                        .onChange(of: chunkDuration) { oldValue, newValue in
                            coordinator.audioCapture.autoChunkDuration = newValue
                        }
                        
                        Text("Recordings are automatically split into chunks of this duration for better processing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Preferences") {
                    NavigationLink(destination: Text("Audio Settings")) {
                        Label("Audio Quality", systemImage: "waveform")
                    }
                    
                    NavigationLink(destination: Text("Privacy Settings")) {
                        Label("Privacy", systemImage: "lock.shield")
                    }
                }
                
                Section("Data") {
                    Button {
                        showDataManagement = true
                    } label: {
                        Label("Data Management", systemImage: "externaldrive")
                    }
                    .foregroundColor(.primary)
                }
                
                Section("Debug") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Database Location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let path = databasePath {
                            Text(path)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        } else {
                            Text("Loading...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Button {
                        Task {
                            await coordinator.testSessionQueries()
                        }
                    } label: {
                        Label("Test Session Queries", systemImage: "testtube.2")
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    NavigationLink(destination: PrivacyPolicyView()) {
                        Label("Privacy Policy", systemImage: "doc.text")
                    }
                    
                    HStack {
                        Text("On-Device Processing")
                        Spacer()
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showDataManagement) {
                DataManagementView()
            }
            .task {
                databasePath = await coordinator.getDatabasePath()
                chunkDuration = coordinator.audioCapture.autoChunkDuration
            }
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy First")
                    .font(.title.bold())
                
                VStack(alignment: .leading, spacing: 12) {
                    PrivacyPoint(
                        icon: "lock.shield.fill",
                        title: "100% On-Device",
                        description: "All audio processing and transcription happens on your device."
                    )
                    
                    PrivacyPoint(
                        icon: "wifi.slash",
                        title: "Zero Network Calls",
                        description: "Life Wrapped never sends your data to any server."
                    )
                    
                    PrivacyPoint(
                        icon: "eye.slash.fill",
                        title: "No Tracking",
                        description: "We don't collect analytics, telemetry, or usage data."
                    )
                    
                    PrivacyPoint(
                        icon: "square.and.arrow.up",
                        title: "Your Data, Your Control",
                        description: "Export or delete your data anytime."
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyPoint: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Recording Detail View

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
                    InfoRow(label: "Format", value: "\(recording.sampleRate) Hz")
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
                try coordinator.audioPlayback.playSingle(url: recording.fileURL)
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

// MARK: - Session Detail View

struct SessionDetailView: View {
    @EnvironmentObject var coordinator: AppCoordinator
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
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Transcription Processing Banner
                if !isTranscriptionComplete {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Processing Transcription...")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Some chunks are still being transcribed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // Session Info Card
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
                .cornerRadius(12)
                
                // Playback Controls
                VStack(spacing: 16) {
                    // Waveform/Progress visualization
                    VStack(spacing: 12) {
                        // Progress bar with scrubbing
                        ZStack {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background waveform
                                    HStack(spacing: 2) {
                                        ForEach(0..<50, id: \.self) { index in
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.gray.opacity(0.3))
                                                .frame(height: waveformHeight(for: index))
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    .background(Color(.tertiarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    // Playhead indicator (white line)
                                    let progress = session.totalDuration > 0
                                        ? totalElapsedTime / session.totalDuration
                                        : 0
                                    
                                    if isPlayingThisSession {
                                        Rectangle()
                                            .fill(Color.white)
                                            .frame(width: 3, height: 60)
                                            .shadow(color: .black.opacity(0.5), radius: 3)
                                            .offset(x: geometry.size.width * progress)
                                            .animation(.linear(duration: 0.1), value: progress)
                                    }
                                }
                            }
                            .frame(height: 60)
                        }
                        
                        // Slider for scrubbing across entire session
                        Slider(
                            value: Binding(
                                get: { totalElapsedTime },
                                set: { seekToTotalTime($0) }
                            ),
                            in: 0...session.totalDuration
                        )
                        .tint(.blue)
                        .disabled(!isPlayingThisSession)
                        
                        // Time display
                        HStack {
                            Text(formatTime(totalElapsedTime))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            
                            Spacer()
                            
                            // Show current chunk in session
                            if isPlayingThisSession, let currentURL = coordinator.audioPlayback.currentlyPlayingURL,
                               let currentChunkIndex = session.chunks.firstIndex(where: { $0.fileURL == currentURL }) {
                                Text("Part \(currentChunkIndex + 1) of \(session.chunkCount)")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                            
                            Text(formatTime(session.totalDuration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    
                    // Play/Pause button
                    Button {
                        playSession()
                    } label: {
                        HStack(spacing: 12) {
                            let isCurrentlyPlaying = isPlayingThisSession && coordinator.audioPlayback.isPlaying
                            Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                if isCurrentlyPlaying {
                                    Text("Pause")
                                        .font(.headline)
                                } else if isPlayingThisSession {
                                    Text("Resume")
                                        .font(.headline)
                                } else {
                                    Text(session.chunkCount > 1 ? "Play All \(session.chunkCount) Parts" : "Play Recording")
                                        .font(.headline)
                                }
                            }
                            
                            Spacer()
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
                            .font(.subheadline)
                            .padding()
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(groupedByChunk, id: \.chunkIndex) { group in
                                let isCurrentChunk = isPlayingThisSession && currentChunkIndex == group.chunkIndex
                                let chunkId = session.chunks[safe: group.chunkIndex]?.id
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    if session.chunkCount > 1 {
                                        // Show chunk marker for multi-chunk sessions with status indicator
                                        HStack(spacing: 8) {
                                            Divider()
                                                .frame(width: 40)
                                            
                                            HStack(spacing: 6) {
                                                Text("Part \(group.chunkIndex + 1)")
                                                    .font(.caption)
                                                    .foregroundStyle(isCurrentChunk ? .blue : .secondary)
                                                    .fontWeight(isCurrentChunk ? .semibold : .regular)
                                                
                                                // Transcription status badge
                                                if let chunkId = chunkId {
                                                    if coordinator.transcribingChunkIds.contains(chunkId) {
                                                        HStack(spacing: 4) {
                                                            ProgressView()
                                                                .scaleEffect(0.6)
                                                            Text("Transcribing...")
                                                                .font(.caption2)
                                                                .foregroundStyle(.blue)
                                                        }
                                                    } else if coordinator.transcribedChunkIds.contains(chunkId) {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .font(.caption)
                                                            .foregroundColor(.green)
                                                    } else if coordinator.failedChunkIds.contains(chunkId) {
                                                        Image(systemName: "exclamationmark.triangle.fill")
                                                            .font(.caption)
                                                            .foregroundColor(.orange)
                                                    }
                                                }
                                            }
                                            
                                            Divider()
                                        }
                                    }
                                    
                                    Text(group.text)
                                        .font(.body)
                                        .foregroundStyle(isCurrentChunk ? .primary : .secondary)
                                }
                                .padding(12)
                                .background(isCurrentChunk ? Color.blue.opacity(0.1) : Color.clear)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isCurrentChunk ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
                                )
                                .animation(.easeInOut(duration: 0.3), value: isCurrentChunk)
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
        .onAppear {
            startPlaybackUpdateTimer()
            startTranscriptionCheckTimer()
        }
        .onDisappear {
            stopPlaybackUpdateTimer()
            stopTranscriptionCheckTimer()
            // Stop playback when leaving this view
            if isPlayingThisSession {
                coordinator.audioPlayback.stop()
            }
        }
    }
    
    private func startPlaybackUpdateTimer() {
        stopPlaybackUpdateTimer()
        // Update at 20fps for smooth visual feedback
        playbackUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                self.forceUpdateTrigger.toggle()
            }
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
                    
                    coordinator.audioPlayback.playSequence(urls: Array(chunkURLs.dropFirst(index))) {
                        print("✅ [SessionDetailView] Session playback completed after seek")
                    }
                    
                    // Seek within this chunk immediately for smooth scrubbing
                    Task {
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
    
    private func loadSessionSummary() async {
        do {
            sessionSummary = try await coordinator.fetchSessionSummary(sessionId: session.sessionId)
            if sessionSummary != nil {
                print("✨ [SessionDetailView] Loaded session summary")
            }
        } catch {
            print("❌ [SessionDetailView] Failed to load session summary: \(error)")
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
        
        isLoading = false
    }
    
    private func playSession() {
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
            coordinator.audioPlayback.playSequence(urls: chunkURLs) {
                print("✅ [SessionDetailView] Session playback completed")
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

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppCoordinator.previewInstance())
    }
}

