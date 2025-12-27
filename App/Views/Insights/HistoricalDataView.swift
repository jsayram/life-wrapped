import SwiftUI
import SharedModels


struct HistoricalDataView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var yearlyData: [(year: Int, sessionCount: Int, totalDuration: TimeInterval)] = []
    @State private var isLoading = true
    @State private var showDeleteAlert = false
    @State private var selectedYear: Int?
    
    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading historical data...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } else if yearlyData.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Historical Data",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Start recording to build your history.")
                    )
                }
            } else {
                Section {
                    Text("View insights from previous years or delete old data to free up space.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                ForEach(yearlyData, id: \.year) { data in
                    Section {
                        NavigationLink(destination: YearInsightsView(year: data.year)) {
                            HStack(spacing: 16) {
                                // Year icon
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.blue.opacity(0.1))
                                        .frame(width: 50, height: 50)
                                    
                                    Text(String(data.year))
                                        .font(.headline)
                                        .foregroundStyle(.blue)
                                }
                                
                                // Stats
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(data.year)")
                                        .font(.headline)
                                    
                                    HStack(spacing: 12) {
                                        Label("\(data.sessionCount)", systemImage: "mic.circle")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        Label(formatDuration(data.totalDuration), systemImage: "timer")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                selectedYear = data.year
                                showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Historical Data")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadYearlyData()
        }
        .refreshable {
            await loadYearlyData()
        }
        .alert("Delete \(selectedYear ?? 0) Data?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let year = selectedYear {
                    deleteYear(year)
                }
            }
        } message: {
            if let year = selectedYear {
                Text("This will permanently delete all recordings and data from \(year). This action cannot be undone.")
            }
        }
    }
    
    private func loadYearlyData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Fetch all sessions
            let allSessions = try await coordinator.fetchRecentSessions(limit: 100000)
            
            // Group by year
            let calendar = Calendar.current
            var yearlyStats: [Int: (sessionCount: Int, totalDuration: TimeInterval)] = [:]
            
            for session in allSessions {
                let year = calendar.component(.year, from: session.startTime)
                let existing = yearlyStats[year] ?? (sessionCount: 0, totalDuration: 0)
                yearlyStats[year] = (
                    sessionCount: existing.sessionCount + 1,
                    totalDuration: existing.totalDuration + session.totalDuration
                )
            }
            
            // Convert to array and sort by year descending
            yearlyData = yearlyStats.map { (year: $0.key, sessionCount: $0.value.sessionCount, totalDuration: $0.value.totalDuration) }
                .sorted { $0.year > $1.year }
            
        } catch {
            print("❌ [HistoricalDataView] Failed to load yearly data: \(error)")
            coordinator.showError("Failed to load historical data")
        }
    }
    
    private func deleteYear(_ year: Int) {
        Task {
            do {
                // Fetch all sessions for this year
                let allSessions = try await coordinator.fetchRecentSessions(limit: 100000)
                let calendar = Calendar.current
                let sessionsToDelete = allSessions.filter { calendar.component(.year, from: $0.startTime) == year }
                
                // Delete each session using coordinator's delete method (handles cascading)
                for session in sessionsToDelete {
                    try? await coordinator.deleteSession(session.sessionId)
                }
                
                await MainActor.run {
                    coordinator.showSuccess("\(year) data deleted successfully")
                }
                
                // Reload data
                await loadYearlyData()
                
            } catch {
                await MainActor.run {
                    coordinator.showError("Failed to delete \(year) data: \(error.localizedDescription)")
                }
            }
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
}

// MARK: - Year Insights View

