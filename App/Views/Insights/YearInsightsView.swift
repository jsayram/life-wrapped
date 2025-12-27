import SwiftUI
import SharedModels


struct YearInsightsView: View {
    let year: Int
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var sessions: [RecordingSession] = []
    @State private var sessionCount: Int = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var totalWordCount: Int = 0
    @State private var isLoading = true
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var exportURL: URL?
    @State private var showDeleteAlert = false
    @State private var monthlyBreakdown: [(monthNumber: Int, monthName: String, count: Int, duration: TimeInterval)] = []
    
    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading \(String(year)) insights...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } else if sessions.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Data for \(String(year))",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No recordings found for this year.")
                    )
                }
            } else {
                // Overview section
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        // Year header
                        HStack {
                            Text(String(year))
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Image(systemName: "calendar")
                                .font(.title)
                                .foregroundStyle(.blue)
                        }
                        
                        // Stats grid
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            StatCard(
                                icon: "mic.circle.fill",
                                value: "\(sessionCount)",
                                label: "Sessions",
                                color: .blue
                            )
                            
                            StatCard(
                                icon: "timer",
                                value: formatDuration(totalDuration),
                                label: "Total Time",
                                color: .green
                            )
                            
                            StatCard(
                                icon: "text.word.spacing",
                                value: formatWordCount(totalWordCount),
                                label: "Words",
                                color: .purple
                            )
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Overview")
                }
                
                // Monthly breakdown
                if !monthlyBreakdown.isEmpty {
                    Section {
                        ForEach(monthlyBreakdown, id: \.monthNumber) { item in
                            NavigationLink(destination: MonthInsightsView(year: year, month: item.monthNumber, monthName: item.monthName)) {
                                HStack {
                                    Text(item.monthName)
                                        .font(.subheadline)
                                    
                                    Spacer()
                                    
                                    Text("\(item.count) sessions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    
                                    Text(formatDuration(item.duration))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Monthly Breakdown")
                    }
                }
                
                // Export section
                Section {
                    Button {
                        exportYearData()
                    } label: {
                        HStack {
                            Label("Export \(String(year)) Data", systemImage: "square.and.arrow.up")
                            
                            Spacer()
                            
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isExporting)
                } header: {
                    Text("Export")
                } footer: {
                    Text("Export all recordings and transcripts from \(String(year)) as a JSON file.")
                }
                
                // Delete section
                Section {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete All \(String(year)) Data", systemImage: "trash")
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("Permanently delete all recordings and data from \(String(year)). This cannot be undone.")
                }
            }
        }
        .navigationTitle(String(year))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadYearData()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Delete \(String(year)) Data?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteYearData()
            }
        } message: {
            Text("This will permanently delete all \(sessionCount) recordings from \(String(year)). This action cannot be undone.")
        }
    }
    
    private func loadYearData() async {
        isLoading = true
        defer { isLoading = false }
        
        let calendar = Calendar.current
        guard let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let endOfYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return
        }
        
        do {
            // Fetch all sessions for this year
            let allSessions = try await coordinator.fetchRecentSessions(limit: 100000)
            sessions = allSessions.filter { $0.startTime >= startOfYear && $0.startTime < endOfYear }
            
            sessionCount = sessions.count
            totalDuration = sessions.reduce(0) { $0 + $1.totalDuration }
            
            // Calculate word count from database
            if let dbManager = coordinator.getDatabaseManager() {
                var wordCount = 0
                for session in sessions {
                    let count = try await dbManager.fetchSessionWordCount(sessionId: session.sessionId)
                    wordCount += count
                }
                totalWordCount = wordCount
            }
            
            // Calculate monthly breakdown
            var monthlyData: [Int: (count: Int, duration: TimeInterval)] = [:]
            for session in sessions {
                let month = calendar.component(.month, from: session.startTime)
                let existing = monthlyData[month] ?? (count: 0, duration: 0)
                monthlyData[month] = (count: existing.count + 1, duration: existing.duration + session.totalDuration)
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMMM"
            
            monthlyBreakdown = monthlyData.keys.sorted().compactMap { month -> (monthNumber: Int, monthName: String, count: Int, duration: TimeInterval)? in
                guard let data = monthlyData[month],
                      let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
                    return nil
                }
                return (monthNumber: month, monthName: dateFormatter.string(from: date), count: data.count, duration: data.duration)
            }
            
        } catch {
            print("❌ [YearInsightsView] Failed to load year data: \(error)")
            coordinator.showError("Failed to load year data")
        }
    }
    
    private func exportYearData() {
        isExporting = true
        
        Task {
            do {
                guard let dbManager = coordinator.getDatabaseManager() else {
                    throw NSError(domain: "YearInsightsView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not available"])
                }
                
                // Build export data for this year
                var exportData: [[String: Any]] = []
                
                for session in sessions {
                    // Fetch chunks for this session
                    let chunks = try await dbManager.fetchChunksBySession(sessionId: session.sessionId)
                    
                    var sessionData: [String: Any] = [
                        "sessionId": session.sessionId.uuidString,
                        "startTime": ISO8601DateFormatter().string(from: session.startTime),
                        "duration": session.totalDuration,
                        "chunkCount": chunks.count
                    ]
                    
                    // Fetch transcripts for each chunk
                    var transcripts: [[String: Any]] = []
                    for chunk in chunks {
                        let segments = try await dbManager.fetchTranscriptSegments(audioChunkID: chunk.id)
                        let text = segments.map { $0.text }.joined(separator: " ")
                        if !text.isEmpty {
                            transcripts.append([
                                "chunkIndex": chunk.chunkIndex,
                                "text": text,
                                "wordCount": segments.reduce(0) { $0 + $1.wordCount }
                            ])
                        }
                    }
                    sessionData["transcripts"] = transcripts
                    
                    // Fetch session summary if available
                    if let summary = try await dbManager.fetchSummaryForSession(sessionId: session.sessionId) {
                        sessionData["summary"] = summary.text
                    }
                    
                    exportData.append(sessionData)
                }
                
                // Create export JSON
                let exportDict: [String: Any] = [
                    "exportDate": ISO8601DateFormatter().string(from: Date()),
                    "year": year,
                    "sessionCount": sessionCount,
                    "totalDurationSeconds": totalDuration,
                    "totalWordCount": totalWordCount,
                    "sessions": exportData
                ]
                
                let jsonData = try JSONSerialization.data(withJSONObject: exportDict, options: [.prettyPrinted, .sortedKeys])
                
                let filename = "lifewrapped-\(year)-export.json"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try jsonData.write(to: tempURL)
                
                await MainActor.run {
                    exportURL = tempURL
                    showShareSheet = true
                    isExporting = false
                    coordinator.showSuccess("Exported \(sessionCount) sessions from \(year)")
                }
                
            } catch {
                await MainActor.run {
                    isExporting = false
                    coordinator.showError("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func deleteYearData() {
        Task {
            for session in sessions {
                try? await coordinator.deleteSession(session.sessionId)
            }
            
            await MainActor.run {
                coordinator.showSuccess("\(year) data deleted successfully")
            }
            
            // Reload to show empty state
            await loadYearData()
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatWordCount(_ count: Int) -> String {
        if count >= 1000 {
            let formatted = Double(count) / 1000.0
            return String(format: "%.1fK", formatted)
        }
        return "\(count)"
    }
}

// MARK: - Stat Card Component

