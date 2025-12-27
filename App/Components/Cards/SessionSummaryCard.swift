import SwiftUI
import SharedModels
import Summarization


struct SessionSummaryCard: View {
    let summary: Summary
    let coordinator: AppCoordinator
    @Environment(\.colorScheme) var colorScheme
    @State private var isLoadingSession = false
    @State private var showSessionNotFoundAlert = false
    @State private var fetchedSession: RecordingSession?
    @State private var shouldNavigate = false
    
    /// Whether this card is for a session that can be navigated to
    private var isNavigable: Bool {
        summary.sessionId != nil
    }
    
    var body: some View {
        cardContent
            .navigationDestination(isPresented: $shouldNavigate) {
                destinationView
            }
            .alert("Session Not Found", isPresented: $showSessionNotFoundAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The recording session for this summary could not be found.")
            }
    }
    
    @ViewBuilder
    private var cardContent: some View {
        if isNavigable {
            Button {
                loadSessionAndNavigate()
            } label: {
                cardBody
            }
            .buttonStyle(.plain)
        } else {
            cardBody
        }
    }
    
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary text (scrollable with max height)
            ScrollView {
                Text(cleanedSummaryText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 450)
                
                // Footer with time and copy button
                HStack(spacing: 12) {
                    // Time display (relative + absolute)
                    // Only show relative time for individual sessions, not rollups
                    VStack(alignment: .leading, spacing: 2) {
                        if summary.sessionId != nil {
                            Text(relativeTimeString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(absoluteTimeString)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    Spacer()
                    
                    // Copy button
                    Button {
                        UIPasteboard.general.string = summary.text
                        coordinator.showSuccess("Summary copied")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.body)
                            .foregroundStyle(AppTheme.skyBlue)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(AppTheme.skyBlue.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        LinearGradient(
                                            colors: [AppTheme.skyBlue.opacity(0.4), AppTheme.purple.opacity(0.3)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.cardGradient(for: colorScheme))
                    .allowsHitTesting(false)
            )
            .cornerRadius(12)
            .overlay {
                if isLoadingSession {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.3))
                    ProgressView()
                        .tint(.white)
                }
            }
        }

    @ViewBuilder
    private var destinationView: some View {
        if let session = fetchedSession {
            SessionDetailView(session: session)
        } else {
            EmptyView()
        }
    }
    
    private var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: summary.periodStart, relativeTo: Date())
    }
    
    private var absoluteTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: summary.periodStart)
    }
    
    // Clean up any stray timestamps from the summary text
    private var cleanedSummaryText: String {
        var text = summary.text
        
        // Remove multiple consecutive timestamps (the main problem)
        let multiTimestampPattern = #"([•●]?\s*[A-Za-z]+\s+\d{1,2},\s+\d{4}\s+\d{1,2}:\d{2}\s+[AP]M:\s*)+"#
        text = text.replacingOccurrences(of: multiTimestampPattern, with: "", options: .regularExpression)
        
        // Remove any remaining single timestamps
        let singleTimestampPattern = #"[•●]?\s*[A-Za-z]+\s+\d{1,2},\s+\d{4}\s+\d{1,2}:\d{2}\s+[AP]M:\s*"#
        while text.range(of: singleTimestampPattern, options: .regularExpression) != nil {
            text = text.replacingOccurrences(of: singleTimestampPattern, with: "", options: .regularExpression)
        }
        
        // Remove any leading bullets or whitespace
        text = text.replacingOccurrences(of: #"^[•●\s]+"#, with: "", options: .regularExpression)
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func loadSessionAndNavigate() {
        guard let sessionId = summary.sessionId else {
            showSessionNotFoundAlert = true
            return
        }
        
        isLoadingSession = true
        
        Task {
            do {
                if let dbManager = coordinator.getDatabaseManager() {
                    // Fetch chunks for this session
                    let chunks = try await dbManager.fetchChunksBySession(sessionId: sessionId)
                    
                    guard !chunks.isEmpty else {
                        await MainActor.run {
                            showSessionNotFoundAlert = true
                            isLoadingSession = false
                        }
                        return
                    }
                    
                    // Fetch metadata
                    let metadata = try? await dbManager.fetchSessionMetadata(sessionId: sessionId)
                    
                    // Build RecordingSession
                    let session = RecordingSession(
                        sessionId: sessionId,
                        chunks: chunks,
                        title: metadata?.title,
                        notes: metadata?.notes,
                        isFavorite: metadata?.isFavorite ?? false
                    )
                    
                    await MainActor.run {
                        fetchedSession = session
                        shouldNavigate = true
                        isLoadingSession = false
                    }
                } else {
                    await MainActor.run {
                        showSessionNotFoundAlert = true
                        isLoadingSession = false
                    }
                }
            } catch {
                print("❌ [SessionSummaryCard] Failed to load session: \(error)")
                await MainActor.run {
                    showSessionNotFoundAlert = true
                    isLoadingSession = false
                }
            }
        }
    }
}

// MARK: - Local Period Summary Card

