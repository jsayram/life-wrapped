// =============================================================================
// ContentView — Main app interface
// =============================================================================

import SwiftUI
import SharedModels

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var selectedTab = 0
    
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
        .overlay {
            if !coordinator.isInitialized && coordinator.initializationError == nil {
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
        case .recording(let startTime): 
            let duration = Date().timeIntervalSince(startTime)
            return "Recording... \(formatDuration(duration))"
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
        Task {
            do {
                if coordinator.recordingState.isRecording {
                    _ = try await coordinator.stopRecording()
                } else if case .idle = coordinator.recordingState {
                    try await coordinator.startRecording()
                } else if case .completed = coordinator.recordingState {
                    coordinator.resetRecordingState()
                } else if case .failed = coordinator.recordingState {
                    coordinator.resetRecordingState()
                }
            } catch {
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
                            RecordingRow(recording: recording)
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
    
    var body: some View {
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
                    NavigationLink(destination: Text("Export")) {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                    
                    NavigationLink(destination: Text("Storage")) {
                        Label("Storage Usage", systemImage: "internaldrive")
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    NavigationLink(destination: Text("Privacy Policy")) {
                        Label("Privacy Policy", systemImage: "doc.text")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppCoordinator.preview())
}
