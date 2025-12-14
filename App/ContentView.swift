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
            .navigationTitle("Life Wrapped")
        }
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
    @State private var recordings: [AudioChunk] = []
    @State private var isLoading = true
    @State private var playbackError: String?
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading recordings...")
                } else if recordings.isEmpty {
                    ContentUnavailableView(
                        "No Recordings Yet",
                        systemImage: "mic.slash",
                        description: Text("Start recording to see your journal entries here.")
                    )
                } else {
                    List {
                        ForEach(recordings, id: \.id) { recording in
                            NavigationLink(destination: RecordingDetailView(recording: recording)) {
                                RecordingRow(
                                    recording: recording,
                                    isPlaying: coordinator.audioPlayback.currentlyPlayingURL == recording.fileURL && coordinator.audioPlayback.isPlaying,
                                    showPlayButton: false
                                )
                            }
                        }
                        .onDelete(perform: deleteRecording)
                    }
                }
            }
            .navigationTitle("History")
            .task {
                await loadRecordings()
            }
            .refreshable {
                await loadRecordings()
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
    
    private func loadRecordings() async {
        isLoading = true
        do {
            recordings = try await coordinator.fetchRecentRecordings(limit: 50)
        } catch {
            print("Failed to load recordings: \(error)")
        }
        isLoading = false
    }
    
    private func deleteRecording(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let recording = recordings[index]
                // Stop playback if this recording is playing
                if coordinator.audioPlayback.currentlyPlayingURL == recording.fileURL {
                    coordinator.audioPlayback.stop()
                }
                do {
                    try await coordinator.deleteRecording(recording.id)
                    recordings.remove(at: index)
                } catch {
                    print("Failed to delete recording: \(error)")
                }
            }
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
    
    var body: some View {
        NavigationStack {
            List {
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

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppCoordinator.previewInstance())
    }
}

