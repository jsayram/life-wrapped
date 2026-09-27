import SwiftUI
import SharedModels
import Summarization


struct SessionSummaryCard: View {
    let summary: Summary
    let coordinator: AppCoordinator
    let onSessionTap: ((RecordingSession) -> Void)?
    @Environment(\.colorScheme) var colorScheme
    @State private var isLoadingSession = false
    @State private var showSessionNotFoundAlert = false
    
    /// Whether this card is for a session that can be navigated to
    private var isNavigable: Bool {
        summary.sessionId != nil
    }
    
    var body: some View {
        cardContent
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
        VStack(alignment: .leading, spacing: 8) {
            // Header: day and time, with copy
            HStack(spacing: 8) {
                Text(headerString)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = summary.text
                    coordinator.showSuccess("Summary copied")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy summary")
            }

            Text(cleanedSummaryText)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .graphiteCard(padding: 16, radius: 16)
        .overlay {
            if isLoadingSession {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.3))
                ProgressView()
                    .tint(.white)
            }
        }
    }

    /// "Thu, Sep 25 · 9:12 AM" for sessions; "Week of Sep 21", "September 2026" or "2026" for rollups
    private var headerString: String {
        let calendar = Calendar.current
        let start = summary.periodStart
        switch summary.periodType {
        case .day:
            return start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week:
            return "Week of " + start.formatted(.dateTime.month(.abbreviated).day())
        case .month, .monthDigest:
            return start.formatted(.dateTime.month(.wide).year())
        case .quarter:
            return start.formatted(.dateTime.quarter().year())
        case .year, .yearWrap, .yearWrapWork, .yearWrapPersonal:
            return start.formatted(.dateTime.year())
        case .session, .hour:
            break
        }
        let time = summary.periodStart.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(summary.periodStart) { return "Today · \(time)" }
        if calendar.isDateInYesterday(summary.periodStart) { return "Yesterday · \(time)" }
        return summary.periodStart.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " · " + time
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
        var text = summary.text.withoutSummaryTitlePrefix
        
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
                        isLoadingSession = false
                        onSessionTap?(session)
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

