import SwiftUI
import SharedModels
import Summarization

struct HomeTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var shouldShowDownloadPrompt: Bool = false  // Controlled by engine tier + download status
    @State private var showDownloadCompleteBanner: Bool = false
    
    @State private var category: SessionCategory = .personal
    @State private var activeTier: EngineTier?
    /// The just-saved recording, opened from the confirmation
    @State private var openedRecording: RecordingSession?
    @State private var isDeletingSilentRecording = false
    /// Today's recordings, newest first
    @State private var todaySessions: [RecordingSession] = []
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The journal the current recording goes to, or nil when there's no recording in progress
    private var recordingJournal: SessionCategory? {
        switch coordinator.recordingState {
        case .recording, .processing, .completed:
            return coordinator.recordingCoordinator?.currentCategory ?? category
        case .idle, .failed:
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header: serif title with the streak pill (or a recording indicator)
                    HStack(alignment: .center) {
                        Text("Life Wrapped")
                            .scaledFont(size: 34, design: .serif)
                            .foregroundStyle(AppTheme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 12)
                        if coordinator.recordingState.isRecording {
                            RecordingIndicatorPill()
                        } else {
                            StreakDisplay(streak: coordinator.currentStreak)
                        }
                    }
                    .padding(.top, 8)

                    // Download in progress banner
                    if coordinator.isDownloadingLocalModel {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Downloading AI model")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1))
                    }

                    // Download complete banner
                    if showDownloadCompleteBanner {
                        Label("AI model ready", systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Category selector. While a recording is in progress, say plainly which journal it goes to.
                    if let journal = recordingJournal {
                        RecordingJournalLabel(journal: journal, state: coordinator.recordingState)
                    } else if coordinator.recordingCoordinator != nil {
                        GraphiteSegmentedControl(
                            options: [
                                .init(value: SessionCategory.work, title: "Work", systemImage: SessionCategory.work.outlineSymbol),
                                .init(value: SessionCategory.personal, title: "Personal", systemImage: SessionCategory.personal.outlineSymbol)
                            ],
                            selection: $category
                        )
                        .disabled(coordinator.recordingState != .idle)
                    }

                    // Recording button fills the middle of the screen
                    RecordingButton()
                        .frame(maxHeight: .infinity)

                    // Subtle Local AI reminder (only shows when on Basic tier and model not downloaded)
                    if shouldShowDownloadPrompt && !coordinator.isDownloadingLocalModel && !coordinator.recordingState.isRecording {
                        VStack(spacing: 6) {
                            Text("Summaries use Key Sentences. Download Offline AI (\(coordinator.expectedLocalModelSizeMB)) for smarter summaries.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    VStack(spacing: 10) {
                        // Today's recordings with the latest one tap away. Hidden right after a stop,
                        // when the saved banner already says where the recording went.
                        if !todaySessions.isEmpty && coordinator.lastSavedRecording == nil && !coordinator.recordingState.isRecording {
                            TodayCard(sessions: todaySessions) { openedRecording = $0 }
                                .transition(.opacity)
                        }

                        // What just happened to the recording that was stopped; replaces the engine card meanwhile
                        if let saved = coordinator.lastSavedRecording, !coordinator.recordingState.isRecording {
                            SavedRecordingBanner(
                                saved: saved,
                                isDeleting: isDeletingSilentRecording,
                                onOpen: { Task { await open(saved) } },
                                onDelete: { Task { await deleteSilent(saved) } },
                                onDismiss: { withAnimation { coordinator.dismissLastSavedRecording() } }
                            )
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            // A normal save confirmation fades after a while; a silent recording waits for an answer
                            .task(id: saved.sessionId) {
                                guard !saved.heardNothing else { return }
                                try? await Task.sleep(for: .seconds(15))
                                guard !Task.isCancelled, coordinator.lastSavedRecording == saved else { return }
                                withAnimation { coordinator.dismissLastSavedRecording() }
                            }
                        } else if let tier = activeTier, !coordinator.recordingState.isRecording {
                            NavigationLink(destination: AISettingsView()) {
                                SummaryEngineCard(tier: tier)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                // On iPad the controls stay together in a centered block instead of spanning the screen
                .readableColumn(640)
                .frame(maxHeight: sizeClass == .regular ? 900 : .infinity)
                .containerRelativeFrame(.vertical, alignment: sizeClass == .regular ? .center : .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear {
                if let recordingCoord = coordinator.recordingCoordinator {
                    category = recordingCoord.selectedCategory
                }
                Task { await loadActiveTier() }
                Task { await loadToday() }
            }
            // A new recording, or the saved banner going away, changes today's list
            .onChange(of: coordinator.lastSavedRecording) { _, _ in
                Task { await loadToday() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .recordingTitlesUpdated)) { _ in
                Task { await loadToday() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sessionMetadataChanged)) { _ in
                Task { await loadToday() }
            }
            .onChange(of: scenePhase) { _, phase in
                // Also catches the day changing while the app was in the background
                if phase == .active { Task { await loadToday() } }
            }
            .onChange(of: category) { _, newValue in
                coordinator.recordingCoordinator?.selectedCategory = newValue
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
                Task { await loadActiveTier() }
            }
            .task {
                // Check if should show Local AI download prompt
                // Only shows when on Basic tier and Local AI not downloaded
                shouldShowDownloadPrompt = await coordinator.shouldShowLocalAIDownloadPrompt()
            }
            .onChange(of: coordinator.isDownloadingLocalModel) { wasDownloading, isDownloading in
                // Show completion banner when download finishes
                if wasDownloading && !isDownloading {
                    Task {
                        // Re-check if we should show the prompt
                        let shouldShow = await coordinator.shouldShowLocalAIDownloadPrompt()
                        if !shouldShow {
                            withAnimation {
                                shouldShowDownloadPrompt = false
                                showDownloadCompleteBanner = true
                            }
                            // Auto-hide after 3 seconds
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            withAnimation {
                                showDownloadCompleteBanner = false
                            }
                        }
                    }
                }
            }
            .refreshable {
                await refreshStats()
            }
            .themedScreen()
            .navigationBarHidden(true)
            .navigationDestination(item: $openedRecording) { session in
                SessionDetailView(session: session)
            }
            .animation(.easeInOut(duration: 0.25), value: coordinator.lastSavedRecording)
        }
    }

    private func open(_ saved: AppCoordinator.SavedRecording) async {
        guard let session = try? await coordinator.fetchSessions(ids: [saved.sessionId]).first else {
            coordinator.showError("Couldn't open the recording")
            return
        }
        coordinator.dismissLastSavedRecording()
        openedRecording = session
    }

    private func deleteSilent(_ saved: AppCoordinator.SavedRecording) async {
        isDeletingSilentRecording = true
        defer { isDeletingSilentRecording = false }
        do {
            try await coordinator.deleteSession(saved.sessionId)
            withAnimation { coordinator.dismissLastSavedRecording() }
            coordinator.showSuccess("Recording deleted")
        } catch {
            coordinator.showError("Couldn't delete the recording")
        }
    }
    
    private func loadToday() async {
        guard let sessions = try? await coordinator.fetchTodaysSessions() else { return }
        withAnimation { todaySessions = sessions }
    }

    private func loadActiveTier() async {
        guard let summCoord = coordinator.summarizationCoordinator else { return }
        activeTier = await summCoord.getActiveEngine()
    }

    private func refreshStats() async {
        print("🔄 [HomeTab] Manual refresh triggered")
        await coordinator.refreshTodayStats()
        await coordinator.refreshStreak()
        print("✅ [HomeTab] Stats refreshed")
    }
}

// MARK: - Header Pills

private struct RecordingIndicatorPill: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppTheme.recording)
                .frame(width: 8, height: 8)
            Text("Recording")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1))
    }
}

/// After Stop: where the recording went and what happens next, or, when the mic heard nothing,
/// an offer to delete it.
private struct SavedRecordingBanner: View {
    let saved: AppCoordinator.SavedRecording
    let isDeleting: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: saved.heardNothing ? "mic.slash" : "checkmark.circle")
                    .font(.body.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(saved.heardNothing ? "The mic didn't pick up any speech" : "Saved to \(saved.journal.displayName)")
                        .font(.subheadline.weight(.semibold))
                    Text(saved.heardNothing
                         ? "Delete it, or keep it in case it caught something."
                         : "The transcript and summary are on the way.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if !saved.heardNothing {
                    Button("View", action: onOpen)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(AppTheme.textPrimary)
                }
            }

            if saved.heardNothing {
                HStack(spacing: 10) {
                    Button(role: .destructive, action: onDelete) {
                        if isDeleting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Delete")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.destructive)
                    .disabled(isDeleting)

                    Button("Keep", action: onDismiss)
                        .buttonStyle(.bordered)
                        .tint(AppTheme.textPrimary)
                        .disabled(isDeleting)
                }
                .controlSize(.small)
            }
        }
        .foregroundStyle(AppTheme.textPrimary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

/// Takes the category switch's place during a recording: which journal it's going to.
private struct RecordingJournalLabel: View {
    let journal: SessionCategory
    let state: RecordingState

    private var verb: String {
        switch state {
        case .recording: return "Recording to"
        case .processing: return "Saving to"
        default: return "Saved to"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: journal.systemImage)
                .font(.body.weight(.semibold))
            (Text(verb + " ").foregroundStyle(AppTheme.textSecondary)
                + Text(journal.displayName).fontWeight(.semibold))
                .font(.body)
        }
        .foregroundStyle(AppTheme.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Record screen: how much was recorded today, with the latest recording one tap away.
private struct TodayCard: View {
    /// Newest first; never empty
    let sessions: [RecordingSession]
    let onOpen: (RecordingSession) -> Void

    private var totals: String {
        let count = sessions.count == 1 ? "1 recording" : "\(sessions.count) recordings"
        let seconds = sessions.reduce(0) { $0 + $1.totalDuration }
        let length = seconds < 60 ? "\(Int(seconds)) sec" : "\(Int((seconds / 60).rounded())) min"
        return "\(count) · \(length)"
    }

    var body: some View {
        let latest = sessions[0]
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer(minLength: 8)
                Text(totals)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Button { onOpen(latest) } label: {
                HStack(spacing: 12) {
                    Image(systemName: latest.journal.outlineSymbol)
                        .scaledFont(size: 17, weight: .regular)
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(latest.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        Text("Latest · \(latest.startTime.formatted(date: .omitted, time: .shortened)) · \(latest.totalDuration.formattedClock)")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the latest recording")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.card)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }
}

private extension TimeInterval {
    /// 1:36, or 1:02:05 past an hour
    var formattedClock: String {
        let total = Int(self.rounded())
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Bottom card on the Record screen showing which summary engine is active.
private struct SummaryEngineCard: View {
    let tier: EngineTier

    private var detail: String {
        switch tier {
        case .basic: return "On-device · Offline"
        case .local: return "Downloaded model · On-device"
        case .apple: return "Built in · On-device"
        case .external: return "\(ExternalModelSettings.provider().rawValue) · Cloud"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle")
                .scaledFont(size: 18, weight: .regular)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Summaries: \(tier.displayName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.card)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens AI and summary settings")
    }
}
