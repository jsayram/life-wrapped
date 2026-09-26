import SwiftUI
import SharedModels

struct HistoryTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var sessions: [RecordingSession] = []
    @State private var sessionWordCounts: [UUID: Int] = [:]
    @State private var sessionHasSummary: [UUID: Bool] = [:]
    @State private var isLoading = true
    @State private var playbackError: String?
    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @State private var categoryFilter: SessionCategory? = nil
    @State private var transcriptMatchingSessionIds: Set<UUID> = []
    @State private var isSearchingTranscripts = false
    @State private var searchDebounceTask: Task<Void, Never>?
    
    private var filteredSessions: [RecordingSession] {
        var result = sessions
        
        // Filter by favorites if enabled
        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }
        
        // Filter by category if selected
        if let category = categoryFilter {
            result = result.filter { $0.category == category }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            
            result = result.filter { session in
                // Search in title
                if let title = session.title, title.lowercased().contains(query) {
                    return true
                }
                // Search in notes
                if let notes = session.notes, notes.lowercased().contains(query) {
                    return true
                }
                // Search in date
                let dateString = formatter.string(from: session.startTime).lowercased()
                if dateString.contains(query) {
                    return true
                }
                // Search in transcripts (from cached results)
                return transcriptMatchingSessionIds.contains(session.sessionId)
            }
        }
        
        return result
    }
    
    var body: some View {
        NavigationStack {
            contentView
                .themedScreen()
                .navigationTitle("History")
                .searchable(text: $searchText, prompt: "Search recordings")
                .onChange(of: searchText) { _, newValue in
                    // Debounce transcript search
                    searchDebounceTask?.cancel()
                    if newValue.count >= 2 {
                        searchDebounceTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            await searchTranscripts(query: newValue)
                        }
                    } else {
                        transcriptMatchingSessionIds = []
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            if isSearchingTranscripts {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            
                            Button {
                                showFavoritesOnly.toggle()
                            } label: {
                                Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                                    .foregroundStyle(showFavoritesOnly ? AppTheme.textSecondary : .secondary)
                            }
                        }
                    }
                }
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
            LoadingView(size: .medium)
        } else if sessions.isEmpty {
            GraphiteEmptyState(
                "No recordings yet",
                systemImage: "mic.slash",
                description: Text("Tap the record button on the Record tab to start your first entry.")
            )
        } else if filteredSessions.isEmpty && !searchText.isEmpty {
            GraphiteEmptyState(
                "No results",
                systemImage: "magnifyingglass",
                description: Text("No recordings match '\(searchText)'")
            )
        } else {
            sessionsList
        }
    }
    
    private var sessionsList: some View {
        List {
            // Category filter chips
            Section {
                categoryChips
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            .listSectionSpacing(8)

            // Empty filter result (chips stay visible so the filter can be changed)
            if filteredSessions.isEmpty {
                Section {
                    Text(showFavoritesOnly ? "No favorites in this filter." : "No recordings in this filter.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                }
            }

            // Stats summary at top
            if !searchText.isEmpty {
                Section {
                    Text("\(filteredSessions.count) recording\(filteredSessions.count == 1 ? "" : "s") found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            ForEach(sortedDates, id: \.self) { date in
                Section {
                    ForEach(sessionsForDate(date), id: \.id) { session in
                        NavigationLink(destination: sessionDetailView(for: session)) {
                            SessionRowClean(
                                session: session,
                                wordCount: sessionWordCounts[session.sessionId],
                                hasSummary: sessionHasSummary[session.sessionId] ?? false
                            )
                        }
                        .hidesNavigationChevron()
                    }
                    .onDelete { offsets in
                        deleteSession(at: offsets, in: date)
                    }
                } header: {
                    HStack {
                        Text(formatSectionDate(date))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text("\(sessionsForDate(date).count) recording\(sessionsForDate(date).count == 1 ? "" : "s")")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private var categoryChips: some View {
        HStack(spacing: 8) {
            FilterChip(title: "All", isSelected: categoryFilter == nil) { categoryFilter = nil }
            ForEach(SessionCategory.allCases, id: \.self) { category in
                FilterChip(title: category.displayName, isSelected: categoryFilter == category) {
                    categoryFilter = categoryFilter == category ? nil : category
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func sessionDetailView(for session: RecordingSession) -> some View {
        SessionDetailView(session: session)
    }
    
    private func sessionsForDate(_ date: Date) -> [RecordingSession] {
        filteredSessions.filter { session in
            Calendar.current.isDate(session.startTime, inSameDayAs: date)
        }
    }
    
    /// Group sessions by date
    private var groupedSessions: [Date: [RecordingSession]] {
        Dictionary(grouping: filteredSessions) { session in
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
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Day name like "Monday"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
    
    private func loadSessions() async {
        isLoading = true
        do {
            sessions = try await coordinator.fetchRecentSessions(limit: 100)
            print("✅ [HistoryTab] Loaded \(sessions.count) sessions")
            
            // Load word counts and summary status in parallel
            guard let dbManager = coordinator.getDatabaseManager() else { return }
            await withTaskGroup(of: (UUID, Int, Bool).self) { group in
                for session in sessions {
                    group.addTask {
                        let count = (try? await dbManager.fetchSessionWordCount(sessionId: session.sessionId)) ?? 0
                        let hasSummary = await ((try? dbManager.fetchSummaryForSession(sessionId: session.sessionId)) != nil)
                        return (session.sessionId, count, hasSummary)
                    }
                }
                
                for await (sessionId, wordCount, hasSummary) in group {
                    sessionWordCounts[sessionId] = wordCount
                    sessionHasSummary[sessionId] = hasSummary
                }
            }
        } catch {
            print("❌ [HistoryTab] Failed to load sessions: \(error)")
        }
        isLoading = false
    }
    
    private func searchTranscripts(query: String) async {
        guard query.count >= 2 else {
            transcriptMatchingSessionIds = []
            return
        }
        
        isSearchingTranscripts = true
        do {
            transcriptMatchingSessionIds = try await coordinator.searchSessionsByTranscript(query: query)
            print("🔍 [HistoryTab] Found \(transcriptMatchingSessionIds.count) sessions matching '\(query)' in transcripts")
        } catch {
            print("❌ [HistoryTab] Transcript search failed: \(error)")
            transcriptMatchingSessionIds = []
        }
        isSearchingTranscripts = false
    }
    
    private func deleteSession(at offsets: IndexSet, in date: Date) {
        let sessionsForDate = self.sessionsForDate(date)
        
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
                    sessionHasSummary.removeValue(forKey: session.sessionId)
                } catch {
                    print("Failed to delete session: \(error)")
                }
            }
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(
                    Capsule()
                        .fill(isSelected ? AppTheme.accent : AppTheme.card)
                        .stroke(isSelected ? Color.clear : AppTheme.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
