import SwiftUI
import SharedModels


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

