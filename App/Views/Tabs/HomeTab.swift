import SwiftUI
import SharedModels
import Summarization

struct HomeTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var shouldShowDownloadPrompt: Bool = false  // Controlled by engine tier + download status
    @State private var showDownloadCompleteBanner: Bool = false
    
    @State private var category: SessionCategory = .personal
    @State private var activeTier: EngineTier?

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
                            .font(AppTheme.titleFont(size: 34))
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
                            Text("Summaries use Basic mode. Download the AI model (\(coordinator.expectedLocalModelSizeMB)) for smarter summaries.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    // Current summary engine
                    if let tier = activeTier, !coordinator.recordingState.isRecording {
                        NavigationLink(destination: AISettingsView()) {
                            SummaryEngineCard(tier: tier)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .containerRelativeFrame(.vertical, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear {
                if let recordingCoord = coordinator.recordingCoordinator {
                    category = recordingCoord.selectedCategory
                }
                Task { await loadActiveTier() }
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
        }
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

/// Bottom card on the Record screen showing which summary engine is active.
private struct SummaryEngineCard: View {
    let tier: EngineTier

    private var detail: String {
        switch tier {
        case .basic: return "Key sentences · On-device"
        case .local: return "Local model · On-device"
        case .apple: return "Apple Intelligence · On-device"
        case .external: return "\(ExternalModelSettings.provider().rawValue) · Cloud"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .regular))
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
                .font(.system(size: 13, weight: .semibold))
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
