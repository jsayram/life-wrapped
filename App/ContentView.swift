// =============================================================================
// ContentView — Main app interface
// =============================================================================

import SwiftUI
import SharedModels
import Charts
import Transcription
import Storage

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
    @State private var sessionSentiments: [UUID: Double] = [:] // Cache sentiments
    @State private var sessionLanguages: [UUID: String] = [:] // Cache languages
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
                                wordCount: sessionWordCounts[session.sessionId],
                                sentiment: sessionSentiments[session.sessionId],
                                language: sessionLanguages[session.sessionId]
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
            
            // Load word counts, sentiments, and languages in parallel for all sessions
            guard let dbManager = coordinator.getDatabaseManager() else { return }
            await withTaskGroup(of: (UUID, Int, Double?, String?).self) { group in
                for session in sessions {
                    group.addTask {
                        let count = (try? await dbManager.fetchSessionWordCount(sessionId: session.sessionId)) ?? 0
                        let sentiment = try? await dbManager.fetchSessionSentiment(sessionId: session.sessionId)
                        let language = try? await dbManager.fetchSessionLanguage(sessionId: session.sessionId)
                        return (session.sessionId, count, sentiment, language)
                    }
                }
                
                for await (sessionId, wordCount, sentiment, language) in group {
                    sessionWordCounts[sessionId] = wordCount
                    if let sentiment = sentiment {
                        sessionSentiments[sessionId] = sentiment
                    }
                    if let language = language {
                        sessionLanguages[sessionId] = language
                    }
                }
            }
            print("✅ [HistoryTab] Loaded word counts for \(sessionWordCounts.count) sessions, \(sessionSentiments.count) sentiments, and \(sessionLanguages.count) languages")
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
    let sentiment: Double?
    let language: String?
    
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
            
            HStack(spacing: 8) {
                // Language flag
                if let language = language {
                    Text(LanguageDetector.flagEmoji(for: language))
                        .font(.title3)
                }
                
                // Sentiment badge
                if let sentiment = sentiment {
                    Text(sentimentEmoji(sentiment))
                        .font(.title3)
                }
            }
            
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
    
    private func sentimentEmoji(_ score: Double) -> String {
        switch score {
        case ..<(-0.5): return "😢"
        case -0.5..<(-0.2): return "😔"
        case -0.2..<0.2: return "😐"
        case 0.2..<0.5: return "🙂"
        default: return "😊"
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

enum TimeRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
    case allTime = "All"
    
    var id: String { rawValue }
    
    var fullName: String {
        switch self {
        case .today: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        case .allTime: return "All Time"
        }
    }
}

// MARK: - Word Frequency Analysis

struct WordFrequency: Identifiable {
    let id = UUID()
    let word: String
    let count: Int
}

class WordAnalyzer {
    // Use comprehensive stopwords from constants file (single source of truth)
    static let stopwords = StopWords.all
    
    static func analyzeWords(from texts: [String], limit: Int = 20, customExcludedWords: Set<String> = []) -> [WordFrequency] {
        // Combine built-in and custom stopwords
        let allStopwords = stopwords.union(customExcludedWords)
        var wordCounts: [String: Int] = [:]
        
        // Process all texts
        for text in texts {
            // Normalize: lowercase and split into words
            let words = text.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { word in
                    // Remove punctuation from edges
                    word.trimmingCharacters(in: .punctuationCharacters)
                }
                .filter { word in
                    // Filter: non-empty, at least 2 chars, not a stopword, not a number
                    !word.isEmpty &&
                    word.count >= 2 &&
                    !allStopwords.contains(word) &&
                    !word.allSatisfy { $0.isNumber }
                }
            
            // Count occurrences
            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }
        
        // Sort by frequency and take top N
        return wordCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { WordFrequency(word: $0.key, count: $0.value) }
    }
}

struct InsightsTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var periodSummary: Summary?
    @State private var sessionCount: Int = 0
    @State private var sessionsInPeriod: [RecordingSession] = []
    @State private var sessionsByHour: [(hour: Int, count: Int, sessionIds: [UUID])] = []
    @State private var sessionsByDayOfWeek: [(dayOfWeek: Int, count: Int, sessionIds: [UUID])] = []
    @State private var longestSession: (sessionId: UUID, duration: TimeInterval, date: Date)?
    @State private var mostActiveMonth: (year: Int, month: Int, count: Int, sessionIds: [UUID])?
    @State private var topWords: [WordFrequency] = []
    @State private var dailySentiment: [(date: Date, sentiment: Double)] = []
    @State private var languageDistribution: [(language: String, wordCount: Int)] = []
    @State private var isLoading = true
    @State private var selectedTimeRange: TimeRange = .allTime
    @State private var wordLimit: Int = 20
    
    private let wordLimitKey = "insightsWordLimit"
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading insights...")
                } else if periodSummary == nil && sessionsByHour.isEmpty {
                    ContentUnavailableView(
                        "No Insights Yet",
                        systemImage: "chart.bar",
                        description: Text("Record more journal entries to unlock insights.")
                    )
                } else {
                    List {
                        // Key Statistics section
                        Section("Key Statistics") {
                            // Longest session
                            if let longest = longestSession {
                                NavigationLink {
                                    FilteredSessionsView(
                                        title: "Longest Session",
                                        sessionIds: [longest.sessionId]
                                    )
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "timer")
                                            .font(.title2)
                                            .foregroundStyle(.orange.gradient)
                                            .frame(width: 40, height: 40)
                                            .background(.orange.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Longest Session")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            HStack {
                                                Text(formatDuration(longest.duration))
                                                    .font(.title3)
                                                    .fontWeight(.semibold)
                                                Spacer()
                                                Text(longest.date.formatted(date: .abbreviated, time: .omitted))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            
                            // Most active month
                            if let mostActive = mostActiveMonth {
                                NavigationLink {
                                    FilteredSessionsView(
                                        title: formatMonth(year: mostActive.year, month: mostActive.month),
                                        sessionIds: mostActive.sessionIds
                                    )
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "calendar.badge.plus")
                                            .font(.title2)
                                            .foregroundStyle(.purple.gradient)
                                            .frame(width: 40, height: 40)
                                            .background(.purple.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Most Active Month")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            HStack {
                                                Text(formatMonth(year: mostActive.year, month: mostActive.month))
                                                    .font(.title3)
                                                    .fontWeight(.semibold)
                                                Spacer()
                                                Text("\(mostActive.count) session\(mostActive.count == 1 ? "" : "s")")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        
                        // Sessions by Hour section with chart
                        if !sessionsByHour.isEmpty {
                            Section {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Sessions by Time of Day")
                                        .font(.headline)
                                        .padding(.bottom, 4)
                                    
                                    // Bar chart
                                    Chart(sessionsByHour, id: \.hour) { data in
                                        BarMark(
                                            x: .value("Hour", data.hour),
                                            y: .value("Sessions", data.count),
                                            width: .fixed(20)
                                        )
                                        .foregroundStyle(.blue.gradient)
                                    }
                                    .chartXAxis {
                                        AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                                            if let hour = value.as(Int.self) {
                                                AxisValueLabel {
                                                    Text(formatHourShort(hour))
                                                        .font(.caption2)
                                                }
                                            }
                                        }
                                    }
                                    .chartYAxis {
                                        AxisMarks { value in
                                            AxisGridLine()
                                            AxisValueLabel()
                                        }
                                    }
                                    .frame(minHeight: 200, maxHeight: 200)
                                    
                                    Divider()
                                        .padding(.vertical, 4)
                                    
                                    Text("Tap an hour to view sessions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom, 4)
                                    
                                    // Scrollable list of all hours
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(sessionsByHour.sorted(by: { $0.hour < $1.hour }), id: \.hour) { data in
                                                NavigationLink {
                                                    FilteredSessionsView(
                                                        title: formatHour(data.hour),
                                                        sessionIds: data.sessionIds
                                                    )
                                                } label: {
                                                    VStack(spacing: 4) {
                                                        Text(formatHourShort(data.hour))
                                                            .font(.caption)
                                                            .fontWeight(.semibold)
                                                            .foregroundStyle(.blue)
                                                        Text("\(data.count)")
                                                            .font(.title3)
                                                            .fontWeight(.bold)
                                                        Text(data.count == 1 ? "session" : "sessions")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    .frame(width: 70)
                                                    .padding(.vertical, 8)
                                                    .background(.blue.opacity(0.1))
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal, 4)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        
                        // Sessions by Day of Week section with chart
                        if !sessionsByDayOfWeek.isEmpty {
                            Section {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Sessions by Day of Week")
                                        .font(.headline)
                                        .padding(.bottom, 4)
                                    
                                    // Bar chart
                                    Chart(sessionsByDayOfWeek, id: \.dayOfWeek) { data in
                                        BarMark(
                                            x: .value("Day", formatDayOfWeek(data.dayOfWeek)),
                                            y: .value("Sessions", data.count),
                                            width: .fixed(40)
                                        )
                                        .foregroundStyle(.green.gradient)
                                    }
                                    .chartXAxis {
                                        AxisMarks { value in
                                            AxisValueLabel {
                                                if let day = value.as(String.self) {
                                                    Text(day)
                                                        .font(.caption2)
                                                }
                                            }
                                        }
                                    }
                                    .chartYAxis {
                                        AxisMarks { value in
                                            AxisGridLine()
                                            AxisValueLabel()
                                        }
                                    }
                                    .frame(minHeight: 180, maxHeight: 180)
                                    
                                    Divider()
                                        .padding(.vertical, 4)
                                    
                                    Text("Tap a day to view sessions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom, 4)
                                    
                                    // Scrollable list of all days
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(sessionsByDayOfWeek.sorted(by: { $0.dayOfWeek < $1.dayOfWeek }), id: \.dayOfWeek) { data in
                                                NavigationLink {
                                                    FilteredSessionsView(
                                                        title: formatDayOfWeekFull(data.dayOfWeek),
                                                        sessionIds: data.sessionIds
                                                    )
                                                } label: {
                                                    VStack(spacing: 4) {
                                                        Text(formatDayOfWeek(data.dayOfWeek))
                                                            .font(.caption)
                                                            .fontWeight(.semibold)
                                                            .foregroundStyle(.green)
                                                        Text("\(data.count)")
                                                            .font(.title3)
                                                            .fontWeight(.bold)
                                                        Text(data.count == 1 ? "session" : "sessions")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    .frame(width: 70)
                                                    .padding(.vertical, 8)
                                                    .background(.green.opacity(0.1))
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal, 4)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        
                        // Most Used Words section
                        if !topWords.isEmpty {
                            Section {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Most Used Words")
                                            .font(.headline)
                                        Spacer()
                                        Text("Top \(topWords.count)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.bottom, 4)
                                    
                                    Text("Meaningful words from your transcripts")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom, 8)
                                    
                                    // Scrollable word cloud grid with fixed height
                                    ScrollView(.vertical, showsIndicators: true) {
                                        LazyVGrid(columns: [
                                            GridItem(.flexible()),
                                            GridItem(.flexible())
                                        ], spacing: 12) {
                                            ForEach(Array(topWords.enumerated()), id: \.element.id) { index, wordFreq in
                                                VStack(spacing: 6) {
                                                    // Word
                                                    Text(wordFreq.word.capitalized)
                                                        .font(.system(size: fontSizeForRank(index), weight: .bold))
                                                        .foregroundStyle(colorForRank(index))
                                                        .lineLimit(1)
                                                        .minimumScaleFactor(0.7)
                                                    
                                                    // Count badge
                                                    Text("\(wordFreq.count)")
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                        .foregroundStyle(.white)
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 4)
                                                        .background(colorForRank(index).gradient)
                                                        .clipShape(Capsule())
                                                }
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(colorForRank(index).opacity(0.08))
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                            }
                                        }
                                        .padding(.horizontal, 2)
                                    }
                                    .frame(height: 400) // Fixed height for scrolling
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        
                        // Emotional Trends section
                        if !dailySentiment.isEmpty {
                            Section {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Emotional Trends")
                                        .font(.headline)
                                        .padding(.bottom, 4)
                                    
                                    Text("Daily sentiment analysis from your journal entries")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom, 8)
                                    
                                    // Line chart showing sentiment over time
                                    Chart(dailySentiment, id: \.date) { data in
                                        LineMark(
                                            x: .value("Date", data.date),
                                            y: .value("Sentiment", data.sentiment)
                                        )
                                        .foregroundStyle(sentimentColor(data.sentiment).gradient)
                                        .interpolationMethod(.catmullRom)
                                        
                                        PointMark(
                                            x: .value("Date", data.date),
                                            y: .value("Sentiment", data.sentiment)
                                        )
                                        .foregroundStyle(sentimentColor(data.sentiment))
                                    }
                                    .chartYScale(domain: -1...1)
                                    .chartYAxis {
                                        AxisMarks(values: [-1, -0.5, 0, 0.5, 1]) { value in
                                            AxisGridLine()
                                            AxisValueLabel {
                                                if let score = value.as(Double.self) {
                                                    Text(sentimentLabel(score))
                                                        .font(.caption2)
                                                }
                                            }
                                        }
                                    }
                                    .chartXAxis {
                                        AxisMarks { value in
                                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                        }
                                    }
                                    .frame(minHeight: 200, maxHeight: 200)
                                    
                                    // Summary stats
                                    HStack(spacing: 16) {
                                        sentimentStatBox(
                                            label: "Positive",
                                            count: dailySentiment.filter { $0.sentiment > 0.3 }.count,
                                            color: .green
                                        )
                                        sentimentStatBox(
                                            label: "Neutral",
                                            count: dailySentiment.filter { abs($0.sentiment) <= 0.3 }.count,
                                            color: .gray
                                        )
                                        sentimentStatBox(
                                            label: "Negative",
                                            count: dailySentiment.filter { $0.sentiment < -0.3 }.count,
                                            color: .red
                                        )
                                    }
                                    .padding(.top, 8)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        
                        // Languages Spoken section
                        if !languageDistribution.isEmpty {
                            Section {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Languages Spoken")
                                        .font(.headline)
                                        .padding(.bottom, 4)
                                    
                                    Text("Distribution of languages in your recordings")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom, 8)
                                    
                                    let totalWords = languageDistribution.reduce(0) { $0 + $1.wordCount }
                                    
                                    ForEach(languageDistribution.prefix(5), id: \.language) { item in
                                        let percentage = totalWords > 0 ? (Double(item.wordCount) / Double(totalWords)) * 100 : 0
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(LanguageDetector.displayName(for: item.language))
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                Spacer()
                                                Text("\(Int(percentage))%")
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .monospacedDigit()
                                            }
                                            
                                            GeometryReader { geometry in
                                                ZStack(alignment: .leading) {
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .fill(Color.secondary.opacity(0.2))
                                                    
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .fill(languageColor(index: languageDistribution.firstIndex(where: { $0.language == item.language }) ?? 0))
                                                        .frame(width: geometry.size.width * (percentage / 100))
                                                }
                                            }
                                            .frame(height: 8)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    
                                    if languageDistribution.count > 1 {
                                        Text("You speak \(languageDistribution.count) language\(languageDistribution.count == 1 ? "" : "s") in your recordings")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 8)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        
                        // Period Summary section
                        if let summary = periodSummary {
                            Section {
                                VStack(alignment: .leading, spacing: 12) {
                                    // Header
                                    HStack {
                                        Text("📝 \(periodTitle)")
                                            .font(.headline)
                                        Spacer()
                                        Text("Based on \(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    // Summary text
                                    Text(summary.text)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .padding(.vertical, 4)
                                    
                                    // Collapsible session details
                                    if !sessionsInPeriod.isEmpty {
                                        DisclosureGroup {
                                            ForEach(sessionsInPeriod, id: \.sessionId) { session in
                                                NavigationLink {
                                                    SessionDetailView(session: session)
                                                } label: {
                                                    HStack {
                                                        VStack(alignment: .leading, spacing: 4) {
                                                            Text(session.startTime, style: .time)
                                                                .font(.subheadline)
                                                                .fontWeight(.medium)
                                                            Text("\(Int(session.totalDuration / 60)) min • \(session.chunkCount) part\(session.chunkCount == 1 ? "" : "s")")
                                                                .font(.caption)
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        Spacer()
                                                    }
                                                }
                                                .padding(.vertical, 2)
                                            }
                                        } label: {
                                            Text("Show individual sessions (\(sessionsInPeriod.count))")
                                                .font(.subheadline)
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                }
            }
            .task {
                // Load word limit from UserDefaults
                wordLimit = UserDefaults.standard.integer(forKey: wordLimitKey)
                if wordLimit == 0 {
                    wordLimit = 20 // Default if not set
                }
                await loadInsights()
            }
            .refreshable {
                await loadInsights()
            }
            .onChange(of: selectedTimeRange) { oldValue, newValue in
                Task {
                    await loadInsights()
                }
            }
        }
    }
    
    private func loadInsights() async {
        isLoading = true
        do {
            // Get date range for filtering
            let dateRange = getDateRange(for: selectedTimeRange)
            
            // Load key statistics (filtered)
            let allLongest = try await coordinator.fetchLongestSession()
            longestSession = filterSession(allLongest, in: dateRange)
            
            let allMostActive = try await coordinator.fetchMostActiveMonth()
            mostActiveMonth = filterMonth(allMostActive, in: dateRange)
            
            // Load sessions by hour (filtered)
            let allByHour = try await coordinator.fetchSessionsByHour()
            sessionsByHour = await filterSessionsByHour(allByHour, in: dateRange)
            
            // Load sessions by day of week (filtered)
            let allByDayOfWeek = try await coordinator.fetchSessionsByDayOfWeek()
            sessionsByDayOfWeek = await filterSessionsByDayOfWeek(allByDayOfWeek, in: dateRange)
            
            // Load word frequency analysis
            let transcriptTexts = try await coordinator.fetchTranscriptText(
                startDate: dateRange.start,
                endDate: dateRange.end
            )
            
            // Load custom excluded words from UserDefaults
            let customExcludedWords: Set<String> = {
                if let savedWords = UserDefaults.standard.stringArray(forKey: "customExcludedWords") {
                    return Set(savedWords)
                }
                return []
            }()
            
            topWords = WordAnalyzer.analyzeWords(
                from: transcriptTexts,
                limit: wordLimit,
                customExcludedWords: customExcludedWords
            )
            
            // Load daily sentiment data
            let (startDate, endDate) = getDateRange(for: selectedTimeRange)
            dailySentiment = try await coordinator.fetchDailySentiment(from: startDate, to: endDate)
            
            // Load language distribution
            languageDistribution = try await coordinator.fetchLanguageDistribution()
            
            // Load period summary based on selected time range
            let periodType: PeriodType = {
                switch selectedTimeRange {
                case .today: return .day
                case .week: return .week
                case .month: return .month
                case .allTime: return .month // Show most recent month for all-time
                }
            }()
            
            // Load sessions in this period first
            if let dbManager = coordinator.getDatabaseManager() {
                if selectedTimeRange == .today {
                    sessionsInPeriod = (try? await dbManager.fetchSessionsByDate(date: startDate)) ?? []
                } else {
                    // For week/month/all, fetch ALL sessions and filter by date range
                    let allSessions = try? await coordinator.fetchRecentSessions(limit: 10000)
                    sessionsInPeriod = allSessions?.filter { session in
                        session.startTime >= startDate && session.startTime < endDate
                    } ?? []
                }
                sessionCount = sessionsInPeriod.count
            }
            
            // Try to fetch existing period summary, or generate if missing
            periodSummary = try? await coordinator.fetchPeriodSummary(type: periodType, date: startDate)
            
            // If no period summary exists but we have sessions with summaries, generate one now
            if periodSummary == nil && !sessionsInPeriod.isEmpty {
                print("ℹ️ [InsightsTab] No \(periodType) summary found for \(startDate.formatted()), generating...")
                
                switch periodType {
                case .day:
                    await coordinator.updateDailySummary(date: startDate)
                case .week:
                    await coordinator.updateWeeklySummary(date: startDate)
                case .month:
                    await coordinator.updateMonthlySummary(date: startDate)
                default:
                    break
                }
                
                // Fetch again after generation
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1s
                periodSummary = try? await coordinator.fetchPeriodSummary(type: periodType, date: startDate)
                
                if periodSummary != nil {
                    print("✅ [InsightsTab] Successfully generated \(periodType) summary")
                } else {
                    print("⚠️ [InsightsTab] Failed to generate \(periodType) summary")
                }
            }
        } catch {
            print("❌ [InsightsTab] Failed to load insights: \(error)")
        }
        isLoading = false
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
    
    private func formatHourShort(_ hour: Int) -> String {
        if hour == 0 {
            return "12 AM"
        } else if hour < 12 {
            return "\(hour) AM"
        } else if hour == 12 {
            return "12 PM"
        } else {
            return "\(hour - 12) PM"
        }
    }
    
    private func formatDayOfWeek(_ dayOfWeek: Int) -> String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return days[dayOfWeek]
    }
    
    private func formatDayOfWeekFull(_ dayOfWeek: Int) -> String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[dayOfWeek]
    }
    
    private func getDateRange(for timeRange: TimeRange) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch timeRange {
        case .today:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .month:
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return (start, now)
        case .allTime:
            return (Date.distantPast, Date.distantFuture)
        }
    }
    
    private func filterSession(_ session: (sessionId: UUID, duration: TimeInterval, date: Date)?, in range: (start: Date, end: Date)) -> (sessionId: UUID, duration: TimeInterval, date: Date)? {
        guard let session = session else { return nil }
        return session.date >= range.start && session.date <= range.end ? session : nil
    }
    
    private func filterMonth(_ month: (year: Int, month: Int, count: Int, sessionIds: [UUID])?, in range: (start: Date, end: Date)) -> (year: Int, month: Int, count: Int, sessionIds: [UUID])? {
        guard let month = month else { return nil }
        let calendar = Calendar.current
        guard let monthDate = calendar.date(from: DateComponents(year: month.year, month: month.month)) else { return nil }
        return monthDate >= range.start && monthDate <= range.end ? month : nil
    }
    
    private func filterSessionsByHour(_ sessions: [(hour: Int, count: Int, sessionIds: [UUID])], in range: (start: Date, end: Date)) async -> [(hour: Int, count: Int, sessionIds: [UUID])] {
        if range.start == Date.distantPast { return sessions }
        
        var filtered: [Int: [UUID]] = [:]
        
        for hourData in sessions {
            for sessionId in hourData.sessionIds {
                if let session = try? await coordinator.fetchSessions(ids: [sessionId]).first,
                   session.startTime >= range.start && session.startTime <= range.end {
                    filtered[hourData.hour, default: []].append(sessionId)
                }
            }
        }
        
        return filtered.map { (hour: $0.key, count: $0.value.count, sessionIds: $0.value) }
    }
    
    private func filterSessionsByDayOfWeek(_ sessions: [(dayOfWeek: Int, count: Int, sessionIds: [UUID])], in range: (start: Date, end: Date)) async -> [(dayOfWeek: Int, count: Int, sessionIds: [UUID])] {
        if range.start == Date.distantPast { return sessions }
        
        var filtered: [Int: [UUID]] = [:]
        
        for dayData in sessions {
            for sessionId in dayData.sessionIds {
                if let session = try? await coordinator.fetchSessions(ids: [sessionId]).first,
                   session.startTime >= range.start && session.startTime <= range.end {
                    filtered[dayData.dayOfWeek, default: []].append(sessionId)
                }
            }
        }
        
        return filtered.map { (dayOfWeek: $0.key, count: $0.value.count, sessionIds: $0.value) }
    }
    
    private func formatMonth(year: Int, month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: year, month: month)) ?? Date()
        return formatter.string(from: date)
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
    
    // MARK: - Word Cloud Styling Helpers
    
    private func fontSizeForRank(_ rank: Int) -> CGFloat {
        // Top words get larger fonts
        switch rank {
        case 0...2: return 22  // Top 3
        case 3...5: return 20  // 4-6
        case 6...9: return 18  // 7-10
        default: return 16     // 11-20
        }
    }
    
    private func colorForRank(_ rank: Int) -> Color {
        // Gradient of colors from most to least frequent
        switch rank {
        case 0...2: return .purple    // Top 3
        case 3...5: return .indigo    // 4-6
        case 6...9: return .blue      // 7-10
        case 10...14: return .teal    // 11-15
        default: return .cyan         // 16-20
        }
    }
    
    // MARK: - Sentiment Helpers
    
    private func sentimentColor(_ score: Double) -> Color {
        switch score {
        case ..<(-0.3): return .red
        case -0.3..<0.3: return .gray
        default: return .green
        }
    }
    
    private func sentimentLabel(_ score: Double) -> String {
        switch score {
        case ..<(-0.5): return "😢"
        case -0.5..<(-0.2): return "😔"
        case -0.2..<0.2: return "😐"
        case 0.2..<0.5: return "🙂"
        default: return "😊"
        }
    }
    
    @ViewBuilder
    private func sentimentStatBox(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func languageColor(index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .cyan]
        return colors[index % colors.count]
    }
    
    private var periodTitle: String {
        switch selectedTimeRange {
        case .today: return "Today's Summary"
        case .week: return "This Week's Summary"
        case .month: return "This Month's Summary"
        case .allTime: return "Overall Summary"
        }
    }
}

// MARK: - FilteredSessionsView

struct FilteredSessionsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let title: String
    let sessionIds: [UUID]
    
    @State private var sessions: [RecordingSession] = []
    @State private var sessionWordCounts: [UUID: Int] = [:]
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading sessions...")
            } else if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "waveform",
                    description: Text("No sessions found for this filter.")
                )
            } else {
                List {
                    ForEach(sessions, id: \.sessionId) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                                        .font(.headline)
                                    Spacer()
                                    if let wordCount = sessionWordCounts[session.sessionId] {
                                        Text("\(wordCount) words")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                HStack {
                                    Text("\(session.chunkCount) chunk\(session.chunkCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text(formatDuration(session.totalDuration))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .task {
            await loadSessions()
        }
    }
    
    private func loadSessions() async {
        isLoading = true
        
        do {
            // Load sessions for these IDs
            sessions = try await coordinator.fetchSessions(ids: sessionIds)
            
            // Load word counts in parallel
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
            
            // Sort by start time descending
            sessions.sort { $0.startTime > $1.startTime }
            
        } catch {
            print("❌ [FilteredSessionsView] Failed to load sessions: \(error)")
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
}

extension Array where Element: Hashable {
    var uniqueCount: Int {
        return Set(self).count
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
    @State private var wordLimit: Double = 20 // Default 20 words
    
    private let wordLimitKey = "insightsWordLimit"
    
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
                            coordinator.showSuccess("Chunk duration updated to \(Int(newValue))s")
                        }
                        
                        Text("Recordings are automatically split into chunks of this duration for better processing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Insights") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Word Cloud Limit")
                            Spacer()
                            Text("\(Int(wordLimit))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        
                        Slider(value: $wordLimit, in: 10...200, step: 10) {
                            Text("Word Limit")
                        }
                        .onChange(of: wordLimit) { oldValue, newValue in
                            UserDefaults.standard.set(Int(newValue), forKey: wordLimitKey)
                            coordinator.showSuccess("Word limit updated to \(Int(newValue))")
                        }
                        
                        Text("Number of most-used words to display in the Insights tab.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    NavigationLink(destination: ExcludedWordsView()) {
                        Label("Excluded Words", systemImage: "text.badge.xmark")
                    }
                }
                
                Section {
                    NavigationLink(destination: LanguageSettingsView()) {
                        Label("Languages", systemImage: "globe")
                    }
                } header: {
                    Text("Languages")
                } footer: {
                    Text("Manage which languages Life Wrapped can detect in your recordings. Detected languages are stored locally and used for insights.")
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
                
                // Load word limit from UserDefaults
                wordLimit = Double(UserDefaults.standard.integer(forKey: wordLimitKey))
                if wordLimit == 0 {
                    wordLimit = 20 // Default if not set
                    UserDefaults.standard.set(20, forKey: wordLimitKey)
                }
            }
        }
    }
}

struct ExcludedWordsView: View {
    @Environment(\.dismiss) private var dismiss
    private let excludedWords = Array(StopWords.all).sorted()
    @State private var customWordsText: String = ""
    @State private var customWords: Set<String> = []
    @State private var savedCustomWordsText: String = "" // Track saved state
    @State private var showUnsavedAlert = false
    @FocusState private var isTextFieldFocused: Bool
    
    private let customWordsKey = "customExcludedWords"
    
    private var hasUnsavedChanges: Bool {
        // Check if text field has content that differs from saved state
        let currentText = customWordsText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !currentText.isEmpty && currentText != savedCustomWordsText
    }
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Common words that are filtered out from the word frequency analysis to focus on meaningful content.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("\(excludedWords.count) words excluded")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("About Excluded Words")
            }
            
            Section {
                ForEach(categoryGroups, id: \.category) { group in
                    DisclosureGroup {
                        FlowLayout(spacing: 8) {
                            ForEach(group.words, id: \.self) { word in
                                Text(word)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.gray.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 8)
                    } label: {
                        HStack {
                            Image(systemName: group.icon)
                                .foregroundStyle(group.color)
                                .frame(width: 24)
                            Text(group.category)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(group.words.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Word Categories")
            }
            
            // Display saved custom words
            if !customWords.isEmpty {
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(customWords).sorted(), id: \.self) { word in
                            HStack(spacing: 6) {
                                Text(word)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Button {
                                    withAnimation {
                                        removeCustomWord(word)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.purple.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    HStack {
                        Text("Your Custom Words")
                        Spacer()
                        Text("\(customWords.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Tap the X to remove a custom word")
                        .font(.caption2)
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add your own words to exclude")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("Enter words separated by commas", text: $customWordsText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTextFieldFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    Button("Save Custom Words") {
                        // Dismiss keyboard first, then save after a brief delay
                        isTextFieldFocused = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            saveCustomWords()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customWordsText.isEmpty)
                    
                    Text("Words will be converted to lowercase and trimmed. Separate multiple words with commas.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Add Custom Words")
            }
        }
        .navigationTitle("Excluded Words")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasUnsavedChanges)
        .toolbar {
            if hasUnsavedChanges {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showUnsavedAlert = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
            }
        }
        .alert("Unsaved Custom Words", isPresented: $showUnsavedAlert) {
            Button("Save and Go Back", role: .none) {
                saveCustomWords()
                dismiss()
            }
            Button("Discard", role: .destructive) {
                customWordsText = savedCustomWordsText
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved words in the text field. Do you want to save them before going back?")
        }
        .onAppear {
            loadCustomWords()
        }
    }
    
    private func loadCustomWords() {
        if let savedWords = UserDefaults.standard.stringArray(forKey: customWordsKey) {
            customWords = Set(savedWords)
            // Keep track of saved state but don't populate text field
            savedCustomWordsText = savedWords.sorted().joined(separator: ", ")
        }
    }
    
    private func saveCustomWords() {
        // Parse comma-separated words
        let newWords = customWordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0.count >= 2 }
        
        // Add new words to existing set (don't replace)
        customWords.formUnion(newWords)
        
        // Save to UserDefaults
        UserDefaults.standard.set(Array(customWords), forKey: customWordsKey)
        
        // Update saved state and clear text field
        savedCustomWordsText = Array(customWords).sorted().joined(separator: ", ")
        customWordsText = ""
    }
    
    private func removeCustomWord(_ word: String) {
        customWords.remove(word)
        UserDefaults.standard.set(Array(customWords), forKey: customWordsKey)
        // Update saved state (text field should remain empty)
        savedCustomWordsText = Array(customWords).sorted().joined(separator: ", ")
    }
    
    private var categoryGroups: [WordCategory] {
        // Use categories from constants file (single source of truth)
        StopWords.categories.map { category in
            WordCategory(
                category: category.name,
                icon: category.icon,
                color: category.color,
                words: Array(category.words).sorted()
            )
        }
    }
}

struct WordCategory {
    let category: String
    let icon: String
    let color: Color
    let words: [String]
}

// Simple flow layout for wrapping words
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
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
    @State private var scrubbedTime: TimeInterval = 0
    
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
                            Text("\(session.chunkCount - transcriptSegments.map({ $0.audioChunkID }).uniqueCount) of \(session.chunkCount) chunks pending")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            Task {
                                await refreshSession()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.body)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.borderless)
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
                                get: { 
                                    isPlayingThisSession ? totalElapsedTime : scrubbedTime 
                                },
                                set: { newValue in
                                    if isPlayingThisSession {
                                        seekToTotalTime(newValue)
                                    } else {
                                        scrubbedTime = newValue
                                    }
                                }
                            ),
                            in: 0...session.totalDuration
                        )
                        .tint(.blue)
                        
                        // Time display
                        HStack {
                            Text(formatTime(isPlayingThisSession ? totalElapsedTime : scrubbedTime))
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
                        // Empty state with different messages based on transcription status
                        let chunkIds = Set(session.chunks.map { $0.id })
                        let hasTranscribing = !chunkIds.isDisjoint(with: coordinator.transcribingChunkIds)
                        let hasFailed = !chunkIds.isDisjoint(with: coordinator.failedChunkIds)
                        
                        if hasTranscribing {
                            ContentUnavailableView(
                                "Transcribing Audio...",
                                systemImage: "waveform.path",
                                description: Text("Your audio is being processed. This may take a moment.")
                            )
                            .padding()
                        } else if hasFailed {
                            ContentUnavailableView(
                                "Transcription Failed",
                                systemImage: "exclamationmark.triangle",
                                description: Text("Unable to transcribe this recording. Try recording again.")
                            )
                            .padding()
                        } else {
                            ContentUnavailableView(
                                "No Transcript",
                                systemImage: "doc.text.slash",
                                description: Text("No transcription available for this recording.")
                            )
                            .padding()
                        }
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
                                    
                                    // Show text or retry button for failed chunks
                                    if let chunkId = chunkId, coordinator.failedChunkIds.contains(chunkId) {
                                        VStack(spacing: 12) {
                                            Text("Transcription failed for this part")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                            
                                            Button {
                                                Task {
                                                    await coordinator.retryTranscription(chunkId: chunkId)
                                                }
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "arrow.clockwise")
                                                    Text("Retry Transcription")
                                                }
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.orange)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                    } else {
                                        Text(group.text)
                                            .font(.body)
                                            .foregroundStyle(isCurrentChunk ? .primary : .secondary)
                                    }
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
            // Check status immediately after loading transcription
            checkTranscriptionStatus()
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
                coordinator.audioPlayback.playSequence(urls: chunkURLs) {
                    print("✅ [SessionDetailView] Session playback completed")
                }
                // Seek to scrubbed position after playback starts
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    seekToTotalTime(scrubbedTime)
                }
            } else {
                coordinator.audioPlayback.playSequence(urls: chunkURLs) {
                    print("✅ [SessionDetailView] Session playback completed")
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

// MARK: - Language Settings View

struct LanguageSettingsView: View {
    @State private var enabledLanguages: Set<String> = []
    @State private var allLanguages: [String] = []
    @EnvironmentObject var coordinator: AppCoordinator
    
    private let enabledLanguagesKey = "enabledLanguages"
    
    var body: some View {
        List {
            Section {
                Text("Select which languages Life Wrapped should detect in your recordings. All processing happens on-device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            Section("Supported Languages (\(allLanguages.count))") {
                ForEach(allLanguages, id: \.self) { languageCode in
                    Toggle(isOn: Binding(
                        get: { enabledLanguages.contains(languageCode) },
                        set: { isEnabled in
                            if isEnabled {
                                enabledLanguages.insert(languageCode)
                            } else {
                                enabledLanguages.remove(languageCode)
                            }
                            saveEnabledLanguages()
                        }
                    )) {
                        HStack {
                            Text(LanguageDetector.flagEmoji(for: languageCode))
                                .font(.title3)
                            Text(LanguageDetector.displayName(for: languageCode))
                            Spacer()
                            Text(languageCode)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("Languages")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadLanguages()
        }
    }
    
    private func loadLanguages() {
        allLanguages = LanguageDetector.supportedLanguages()
        
        if let savedLanguages = UserDefaults.standard.array(forKey: enabledLanguagesKey) as? [String] {
            enabledLanguages = Set(savedLanguages)
        } else {
            // Default to English and Spanish only
            let defaultLanguages = ["en", "es"]
            enabledLanguages = Set(defaultLanguages.filter { allLanguages.contains($0) })
            saveEnabledLanguages()
        }
    }
    
    private func saveEnabledLanguages() {
        UserDefaults.standard.set(Array(enabledLanguages), forKey: enabledLanguagesKey)
        coordinator.showSuccess("Language preferences saved")
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

