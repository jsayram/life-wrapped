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
    /// Set once the user dismisses the note about older recordings filed under Personal
    @AppStorage("uncategorizedNoticeDismissed") private var uncategorizedNoticeDismissed = false
    @State private var transcriptMatchingSessionIds: Set<UUID> = []
    @State private var isSearchingTranscripts = false
    @State private var searchDebounceTask: Task<Void, Never>?
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The recording shown beside the list on iPad
    @State private var selectedSessionId: UUID?
    
    private var filteredSessions: [RecordingSession] {
        var result = sessions
        
        // Filter by favorites if enabled
        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }
        
        // Filter by category if selected
        if let category = categoryFilter {
            result = result.filter { $0.journal == category }
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
    
    /// iPad (regular width): list on the left, the chosen recording on the right
    private var usesSplitView: Bool { sizeClass == .regular }

    private var selectedSession: RecordingSession? {
        sessions.first { $0.sessionId == selectedSessionId }
    }

    var body: some View {
        if usesSplitView {
            NavigationSplitView {
                listScreen
                    .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
            } detail: {
                NavigationStack {
                    if let session = selectedSession {
                        SessionDetailView(session: session)
                            .id(session.sessionId)
                    } else {
                        GraphiteEmptyState(
                            "No recording selected",
                            systemImage: "waveform",
                            description: Text("Choose a recording to read its summary and transcript.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .themedScreen()
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack {
                listScreen
            }
        }
    }

    private var listScreen: some View {
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
                .onReceive(NotificationCenter.default.publisher(for: .recordingTitlesUpdated)) { _ in
                    Task { await loadSessions() }
                }
                // Keep the row in step with edits made in the recording (side by side on iPad)
                .onReceive(NotificationCenter.default.publisher(for: .sessionMetadataChanged)) { note in
                    guard let id = note.object as? UUID else { return }
                    Task { await refreshSession(id) }
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

            // Recordings from before categories existed count as Personal; say so once
            let uncategorized = sessions.filter { $0.category == nil }.count
            if uncategorized > 0 && !uncategorizedNoticeDismissed {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "house")
                            .foregroundStyle(AppTheme.textSecondary)
                            .accessibilityHidden(true)
                        Text(uncategorized == 1
                             ? "1 older recording was made before Work and Personal existed, so it's in Personal. Open it to move it to Work."
                             : "\(uncategorized) older recordings were made before Work and Personal existed, so they're in Personal. Open one to move it to Work.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button {
                            uncategorizedNoticeDismissed = true
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss")
                    }
                }
            }

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
                        sessionRow(session)
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

    /// iPhone pushes the recording; iPad selects it and shows it beside the list
    @ViewBuilder
    private func sessionRow(_ session: RecordingSession) -> some View {
        let row = SessionRowClean(
            session: session,
            wordCount: sessionWordCounts[session.sessionId],
            hasSummary: sessionHasSummary[session.sessionId] ?? false
        )
        if usesSplitView {
            let isSelected = selectedSessionId == session.sessionId
            Button {
                selectedSessionId = session.sessionId
            } label: {
                row.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // White rows with the chosen one in grey; the sidebar's default row color hides the selection
            .listRowBackground(isSelected ? AppTheme.fill : AppTheme.card)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            NavigationLink(destination: SessionDetailView(session: session)) {
                row
            }
            .hidesNavigationChevron()
        }
    }

    /// Reload one recording after its title, notes, star or journal changed
    private func refreshSession(_ id: UUID) async {
        guard let index = sessions.firstIndex(where: { $0.sessionId == id }),
              let updated = try? await coordinator.fetchSessions(ids: [id]).first else { return }
        sessions[index] = updated
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
        // Only the first load shows the spinner; later reloads update the list in place
        if sessions.isEmpty { isLoading = true }
        do {
            sessions = try await coordinator.fetchRecentSessions(limit: 100)
            print("✅ [HistoryTab] Loaded \(sessions.count) sessions")

            // On iPad, open the newest recording so the right side isn't empty
            if usesSplitView && selectedSession == nil {
                selectedSessionId = sessions.max(by: { $0.startTime < $1.startTime })?.sessionId
            }

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
                    if selectedSessionId == session.sessionId { selectedSessionId = nil }
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
