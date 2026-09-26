import SwiftUI
import SharedModels
import Security
import Summarization
import Storage

struct SettingsTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var activeEngineName: String = "Loading..."
    @State private var debugTapCount: Int = 0
    @State private var showDebugSection: Bool = false
    @State private var databasePath: String?
    @State private var navigateToAISettings: Bool = false
    @State private var fromYearWrap: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                // Main settings
                Section {
                    NavigationLink(destination: RecordingSettingsView()) {
                        SettingsRowLabel(icon: "mic", title: "Recording", value: chunkLabel)
                    }
                    NavigationLink(destination: AISettingsView()) {
                        SettingsRowLabel(icon: "sparkle", title: "AI & Summaries", value: activeEngineName)
                    }
                    NavigationLink(destination: StatisticsView()) {
                        SettingsRowLabel(icon: "chart.bar", title: "Statistics")
                    }
                    NavigationLink(destination: DataSettingsView()) {
                        SettingsRowLabel(icon: "cylinder", title: "Data", value: "Export, import")
                    }
                }

                // Purchases Section
                Section {
                    SettingsRowLabel(
                        icon: "cloud",
                        title: "Smartest",
                        value: coordinator.storeManager.isSmartestAIUnlocked
                            ? "Unlocked"
                            : (coordinator.storeManager.smartestAIProduct?.displayPrice ?? "Locked")
                    )

                    Button {
                        Task {
                            await coordinator.storeManager.restorePurchases()
                        }
                    } label: {
                        HStack {
                            SettingsRowLabel(icon: "arrow.clockwise", title: "Restore purchases")
                            if coordinator.storeManager.purchaseState == .restoring {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(coordinator.storeManager.purchaseState == .restoring)
                } header: {
                    Text("Purchases")
                }

                // About Section
                Section {
                    NavigationLink(destination: PrivacySettingsView()) {
                        SettingsRowLabel(icon: "shield", title: "Privacy policy")
                    }

                    SettingsRowLabel(icon: "info.circle", title: "Version", value: appVersion, monospacedValue: true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            debugTapCount += 1
                            if debugTapCount >= 5 {
                                showDebugSection = true
                                coordinator.showSuccess("Debug mode enabled")
                                debugTapCount = 0
                            }
                        }
                } header: {
                    Text("About")
                }
                
                // Debug Section (hidden by default)
                if showDebugSection {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Database Location")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let path = databasePath {
                                Text(path)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            } else {
                                Text("Loading...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        Button {
                            Task {
                                await coordinator.testSessionQueries()
                            }
                        } label: {
                            Label("Test Session Queries", systemImage: "testtube.2")
                        }
                        
                        #if DEBUG
                        Button {
                            Task {
                                guard let db = coordinator.getDatabaseManager() else { return }
                                do {
                                    try await ScreenshotSampleData.load(into: db)
                                    await coordinator.refreshStreak()
                                    await coordinator.refreshTodayStats()
                                    coordinator.showSuccess("Sample data loaded")
                                } catch {
                                    coordinator.showError("Sample data failed: \(error.localizedDescription)")
                                }
                            }
                        } label: {
                            Label("Load sample data (screenshots)", systemImage: "square.stack.3d.up")
                        }
                        #endif

                        Button(role: .destructive) {
                            showDebugSection = false
                        } label: {
                            Label("Hide Debug Section", systemImage: "eye.slash")
                        }
                    } header: {
                        Text("Debug")
                    }
                }
            }
            .themedScreen()
            .navigationTitle("Settings")
            .task {
                await loadActiveEngine()
                databasePath = await coordinator.getDatabasePath()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
                Task {
                    await loadActiveEngine()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToSmartestConfig"))) { _ in
                fromYearWrap = true
                navigateToAISettings = true
            }
            .navigationDestination(isPresented: $navigateToAISettings) {
                AISettingsView(fromYearWrap: fromYearWrap)
                    .onDisappear {
                        fromYearWrap = false
                    }
            }
        }
    }
    
    private var chunkLabel: String {
        let seconds = Int(UserDefaults.standard.autoChunkDuration)
        if seconds % 60 == 0 { return "\(seconds / 60) min parts" }
        return "\(seconds)s parts"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func loadActiveEngine() async {
        guard let summCoord = coordinator.summarizationCoordinator else {
            activeEngineName = "Not configured"
            return
        }
        
        let engine = await summCoord.getActiveEngine()
        activeEngineName = engine.displayName
    }
}

// MARK: - Settings Row

/// Settings row matching the graphite mockup: outline icon, title, optional trailing value.
struct SettingsRowLabel: View {
    let icon: String
    let title: String
    var value: String? = nil
    var monospacedValue: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(monospacedValue ? .system(.subheadline, design: .monospaced) : .subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Screenshot Sample Data (Debug builds only)

#if DEBUG
/// Fills the database with a small, fictional journal so the App Store and website
/// screenshots show real screens with realistic content. Only reachable from the hidden
/// debug section in Debug builds; never included in Release builds.
enum ScreenshotSampleData {
    private struct Entry {
        let daysAgo: Int
        let hour: Int
        let minute: Int
        let seconds: Int
        let category: SessionCategory
        let title: String
        let favorite: Bool
        let transcript: String
        let summary: String
    }

    private static let entries: [Entry] = [
        Entry(daysAgo: 0, hour: 9, minute: 12, seconds: 272, category: .work, title: "Planning the beta launch", favorite: true,
              transcript: "This morning I met Sarah at the coffee shop downtown to plan the product launch. We agreed the beta goes out on the fifteenth and she will handle the press email. I'm a bit stressed about the deadline, but excited because the early feedback on the new onboarding flow has been really positive. Next step is locking the release notes by Thursday.",
              summary: "Met Sarah downtown to plan the product launch. The beta ships on the fifteenth, and Sarah will send the press email. A little stressed about the deadline, but encouraged by early feedback on the new onboarding flow."),
        Entry(daysAgo: 0, hour: 12, minute: 40, seconds: 96, category: .personal, title: "Lunch walk thoughts", favorite: false,
              transcript: "Took a long walk at lunch instead of eating at my desk. The weather finally turned and the park was full of people. I want to keep doing this at least three times a week, it clears my head more than coffee does.",
              summary: "A lunch walk in the park cleared my head. Goal: walk at lunch at least three times a week."),
        Entry(daysAgo: 0, hour: 7, minute: 5, seconds: 125, category: .personal, title: "Morning run by the river", favorite: false,
              transcript: "Morning run by the river, about five kilometers. Legs felt heavy at the start but the last two kilometers were the best of the week. Thinking about signing up for the half marathon in October.",
              summary: "Felt lighter after a morning run by the river, and thinking seriously about the October half marathon."),
        Entry(daysAgo: 1, hour: 15, minute: 18, seconds: 407, category: .personal, title: "Garden with Dad", favorite: true,
              transcript: "Spent the afternoon in the garden planting tomatoes and basil with my dad. He showed me how to prune the old rose bush. We talked about building a small greenhouse next spring and made a list of supplies to buy at the hardware store.",
              summary: "Planted tomatoes and basil with Dad, learned to prune the roses, and started planning a small greenhouse for spring."),
        Entry(daysAgo: 2, hour: 11, minute: 2, seconds: 495, category: .work, title: "Design review notes", favorite: false,
              transcript: "Design review went well. The new onboarding tested well with five people, everyone understood the privacy screen. Two fixes before release: the permission copy is too long, and the empty state on history needs a clearer next step.",
              summary: "Onboarding tested well with five people. Two fixes before release: shorter permission copy and a clearer empty state in history."),
        Entry(daysAgo: 3, hour: 20, minute: 15, seconds: 318, category: .personal, title: "Call with Maya", favorite: false,
              transcript: "Long call with Maya tonight. She is moving to Denver in the spring and wants us to visit. We talked about her new job and about how fast this year is going. I should plan the trip before flights get expensive.",
              summary: "Caught up with Maya about her move to Denver and new job. Plan a visit before flights get expensive."),
        Entry(daysAgo: 4, hour: 10, minute: 30, seconds: 240, category: .work, title: "Pricing brainstorm", favorite: false,
              transcript: "Pricing brainstorm with the team. We keep the core app free and offer one optional upgrade. People liked a one-time purchase more than a subscription. I'll write up the tradeoffs for Friday.",
              summary: "Team leaned toward a free core app with one optional one-time upgrade. Write up the tradeoffs for Friday."),
        Entry(daysAgo: 5, hour: 9, minute: 5, seconds: 180, category: .personal, title: "Weekly reset", favorite: false,
              transcript: "Weekly reset. Cleaned the apartment, planned meals for the week and finally answered the emails I had been avoiding. Feeling calm and ready for the week.",
              summary: "A calm weekly reset: cleaning, meal planning and clearing the inbox."),
        Entry(daysAgo: 6, hour: 8, minute: 45, seconds: 150, category: .personal, title: "Farmers market", favorite: false,
              transcript: "Went to the farmers market early. Bought peaches, fresh bread and flowers for the kitchen. Ran into our old neighbors and they invited us for dinner next month.",
              summary: "Early trip to the farmers market and a dinner invitation from old neighbors."),
        Entry(daysAgo: 7, hour: 14, minute: 20, seconds: 360, category: .work, title: "Onboarding interviews", favorite: false,
              transcript: "Ran three onboarding interviews. The biggest confusion was the difference between the summary options. People want a simple default and the details later. Worth simplifying the settings screen.",
              summary: "Three onboarding interviews showed people want a simple default summary option, with details later."),
        Entry(daysAgo: 8, hour: 19, minute: 0, seconds: 120, category: .personal, title: "Quiet evening", favorite: false,
              transcript: "Quiet evening. Read for an hour and went to bed early. Grateful for a slow day after a busy week.",
              summary: "A slow, restful evening with a book after a busy week."),
        Entry(daysAgo: 9, hour: 13, minute: 10, seconds: 200, category: .work, title: "Release checklist", favorite: false,
              transcript: "Went through the release checklist. Screenshots, privacy labels and the review notes are done. Still need to test on an older iPhone.",
              summary: "Most of the release checklist is done; testing on an older iPhone remains."),
        Entry(daysAgo: 10, hour: 7, minute: 30, seconds: 90, category: .personal, title: "Morning run", favorite: false,
              transcript: "Short morning run before work. Cold but clear. Started a new playlist.",
              summary: "A short, cold and clear morning run before work."),
        Entry(daysAgo: 11, hour: 21, minute: 5, seconds: 140, category: .personal, title: "Weekend plans", favorite: false,
              transcript: "Thinking about the weekend. Maybe a hike if the weather holds, and dinner with Sam on Saturday.",
              summary: "Weekend plans: a hike if the weather holds and dinner with Sam on Saturday.")
    ]

    static func load(into db: DatabaseManager) async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for entry in entries {
            guard let day = calendar.date(byAdding: .day, value: -entry.daysAgo, to: today),
                  var start = calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: day) else { continue }
            // Keep today's entries in the past so nothing looks recorded in the future
            let latestStart = Date().addingTimeInterval(-TimeInterval(entry.seconds) - 60)
            if start > latestStart { start = latestStart }
            let sessionId = UUID()
            let chunk = AudioChunk(
                fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sample-\(sessionId.uuidString).m4a"),
                startTime: start,
                endTime: start.addingTimeInterval(TimeInterval(entry.seconds)),
                format: .m4a,
                sampleRate: 44100,
                createdAt: start,
                sessionId: sessionId,
                chunkIndex: 0
            )
            try await db.insertAudioChunk(chunk)
            try await db.insertTranscriptSegment(TranscriptSegment(
                audioChunkID: chunk.id,
                startTime: 0,
                endTime: TimeInterval(entry.seconds),
                text: entry.transcript,
                confidence: 0.96,
                languageCode: "en-US",
                createdAt: start,
                sentimentScore: entry.category == .personal ? 0.5 : 0.2
            ))
            try await db.upsertSessionMetadata(DatabaseManager.SessionMetadata(
                sessionId: sessionId,
                title: entry.title,
                isFavorite: entry.favorite,
                category: entry.category,
                createdAt: start,
                updatedAt: start
            ))
            try await db.insertSummary(Summary(
                periodType: .session,
                periodStart: start,
                periodEnd: start.addingTimeInterval(TimeInterval(entry.seconds)),
                text: entry.summary,
                createdAt: start,
                sessionId: sessionId,
                engineTier: "apple"
            ))
        }

        // Period summaries for the Overview tab
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        try await db.insertSummary(Summary(periodType: .day, periodStart: today, periodEnd: dayEnd,
            text: "An early run by the river, a launch-focused morning with Sarah and a clearing walk at lunch. Stress about the deadline eased as the day went on.", engineTier: "local"))
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2 // The app's weeks start on Monday
        if let week = weekCalendar.dateInterval(of: .weekOfYear, for: Date()) {
            try await db.insertSummary(Summary(periodType: .week, periodStart: week.start, periodEnd: week.end,
                text: "A launch-focused week. Most entries were about getting the beta ready, balanced by runs, a call with Maya and a slow afternoon in the garden. The mood lifted toward the weekend.", engineTier: "local"))
        }
        if let month = calendar.dateInterval(of: .month, for: Date()) {
            try await db.insertSummary(Summary(periodType: .month, periodStart: month.start, periodEnd: month.end,
                text: "This month was about shipping: design reviews, pricing and the release checklist. Outside work, running became a habit and weekends stayed slow and social.", engineTier: "local"))
        }

        // Year Wrap
        if let year = calendar.dateInterval(of: .year, for: Date()) {
            try await db.insertSummary(Summary(periodType: .year, periodStart: year.start, periodEnd: year.end,
                text: "A year of building. Work centered on launching the beta, from design reviews to pricing and the release checklist. Running turned into a habit, weekends stayed slow, and time with Dad in the garden became a favorite ritual.", engineTier: "local"))
            let wrap = """
            {"year_title": "A year of building and slowing down",
             "year_summary": "You shipped a product, ran more than ever, and kept coming back to the garden. Work was intense in the spring and calmer by the fall.",
             "major_arcs": [{"text": "Launched the beta after four months of work.", "category": "work"}, {"text": "Built a steady running habit.", "category": "personal"}],
             "biggest_wins": [{"text": "Beta launched on time with strong onboarding feedback.", "category": "work"}, {"text": "Ran more consistently than any year before.", "category": "personal"}],
             "biggest_losses": [],
             "biggest_challenges": [{"text": "Balancing launch pressure with rest.", "category": "both"}],
             "finished_projects": [{"text": "Planted the spring garden with Dad.", "category": "personal"}],
             "unfinished_projects": [{"text": "The greenhouse is still on the list.", "category": "personal"}],
             "top_worked_on_topics": [{"text": "Onboarding", "category": "work"}, {"text": "Pricing", "category": "work"}],
             "top_talked_about_things": [{"text": "Running", "category": "personal"}, {"text": "The launch", "category": "work"}],
             "valuable_actions_taken": [{"text": "Walking at lunch instead of eating at the desk.", "category": "personal"}],
             "opportunities_missed": [{"text": "Travel plans that kept slipping.", "category": "personal"}],
             "people_mentioned": [{"name": "Sarah", "relationship": "Coworker"}, {"name": "Dad", "relationship": "Family"}, {"name": "Maya", "relationship": "Friend"}],
             "places_visited": [{"name": "Downtown", "frequency": "Weekly"}, {"name": "The river trail", "frequency": "Most evenings"}, {"name": "Home garden", "frequency": "Weekends"}]}
            """
            try await db.insertSummary(Summary(periodType: .yearWrap, periodStart: year.start, periodEnd: year.end, text: wrap, engineTier: "local"))
        }
    }
}
#endif
