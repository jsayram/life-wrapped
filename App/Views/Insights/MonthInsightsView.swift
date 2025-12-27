import SwiftUI
import SharedModels


struct MonthInsightsView: View {
    let year: Int
    let month: Int
    let monthName: String
    
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var sessions: [RecordingSession] = []
    @State private var isLoading = true
    @State private var totalDuration: TimeInterval = 0
    @State private var totalWordCount: Int = 0
    
    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading \(monthName) sessions...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } else if sessions.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No recordings found for \(monthName) \(String(year)).")
                    )
                }
            } else {
                // Stats section
                Section {
                    HStack(spacing: 20) {
                        StatCard(
                            icon: "mic.circle.fill",
                            value: "\(sessions.count)",
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
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)
                } header: {
                    Text("Overview")
                }
                
                // Sessions list
                Section {
                    ForEach(sessions, id: \.sessionId) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            SessionRowView(session: session)
                        }
                    }
                } header: {
                    Text("Sessions")
                }
            }
        }
        .navigationTitle("\(monthName) \(String(year))")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMonthData()
        }
    }
    
    private func loadMonthData() async {
        isLoading = true
        defer { isLoading = false }
        
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            return
        }
        
        do {
            // Fetch all sessions and filter by month
            let allSessions = try await coordinator.fetchRecentSessions(limit: 100000)
            sessions = allSessions.filter { $0.startTime >= startOfMonth && $0.startTime < endOfMonth }
                .sorted { $0.startTime > $1.startTime }
            
            totalDuration = sessions.reduce(0) { $0 + $1.totalDuration }
            
            // Calculate word count
            if let dbManager = coordinator.getDatabaseManager() {
                var wordCount = 0
                for session in sessions {
                    let count = try await dbManager.fetchSessionWordCount(sessionId: session.sessionId)
                    wordCount += count
                }
                totalWordCount = wordCount
            }
            
        } catch {
            print("❌ [MonthInsightsView] Failed to load month data: \(error)")
            coordinator.showError("Failed to load month data")
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

// MARK: - Session Row View for Month

