import SwiftUI
import SharedModels
import Storage

// MARK: - ItemFilter Extensions for UI

extension ItemFilter {
    var displayName: String {
        switch self {
        case .all: return "ALL"
        case .workOnly: return "WORK"
        case .personalOnly: return "PERSONAL"
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .workOnly: return "briefcase.fill"
        case .personalOnly: return "house.fill"
        }
    }
}

struct YearWrapDetailView: View {
    let yearWrap: Summary  // Initial combined summary
    let coordinator: AppCoordinator
    let initialFilter: ItemFilter
    @Environment(\.dismiss) private var dismiss
    @State private var redactPeople = false
    @State private var redactPlaces = false
    @State private var displayFilter: ItemFilter = .all
    @State private var parsedData: YearWrapData?
    @State private var totalSessions: Int = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var totalWords: Int = 0
    @State private var pdfData: Data?
    @State private var isGeneratingPDF = false
    @State private var showingShareSheet = false
    
    @State private var combinedSummary: Summary?
    @State private var isLoadingSummary = false
    
    init(yearWrap: Summary, coordinator: AppCoordinator, initialFilter: ItemFilter = .all) {
        self.yearWrap = yearWrap
        self.coordinator = coordinator
        self.initialFilter = initialFilter
        // Initialize displayFilter with initialFilter
        _displayFilter = State(initialValue: initialFilter)
    }
    
    /// One wrap for everything; Work and Personal filter its items by category
    private var activeSummary: Summary {
        combinedSummary ?? yearWrap
    }
    
    /// Title for the current filter
    private var filterTitle: String {
        switch displayFilter {
        case .all:
            return "Year Wrap"
        case .workOnly:
            return "Work Year Wrap"
        case .personalOnly:
            return "Personal Year Wrap"
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero Section
                    heroSection
                    
                    // Stats Grid
                    statsSection
                    
                    // Loading state
                    if isLoadingSummary {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading \(filterTitle)...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else if let data = parsedData {
                        // Insights Sections
                        VStack(spacing: 24) {
                            majorArcsSection(data.majorArcs)
                            biggestWinsSection(data.biggestWins)
                            biggestLossesSection(data.biggestLosses)
                            biggestChallengesSection(data.biggestChallenges)
                            finishedProjectsSection(data.finishedProjects)
                            unfinishedProjectsSection(data.unfinishedProjects)
                            topWorkedOnSection(data.topWorkedOnTopics)
                            topTalkedAboutSection(data.topTalkedAboutThings)
                            valuableActionsSection(data.valuableActionsTaken)
                            opportunitiesMissedSection(data.opportunitiesMissed)
                            peopleMentionedSection(data.peopleMentioned)
                            placesVisitedSection(data.placesVisited)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    } else {
                        // Fallback: show raw text if parsing fails
                        Text(activeSummary.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                    
                    // Footer
                    footerSection
                }
            }
            .background(AppTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Display Filter") {
                            Picker("Filter Items", selection: $displayFilter) {
                                ForEach(ItemFilter.allCases) { filter in
                                    Label(filter.displayName, systemImage: filter.icon)
                                        .tag(filter)
                                }
                            }
                        }
                        
                        Section("Privacy") {
                            Toggle(isOn: $redactPeople) {
                                Label("Redact people", systemImage: "person.slash")
                            }
                            
                            Toggle(isOn: $redactPlaces) {
                                Label("Redact places", systemImage: "mappin.slash")
                            }
                        }
                        
                        Divider()
                        
                        Button {
                            Task {
                                await generatePDF()
                            }
                        } label: {
                            if isGeneratingPDF {
                                Label("Generating PDF...", systemImage: "doc.circle")
                            } else {
                                Label("Export PDF", systemImage: "square.and.arrow.up")
                            }
                        }
                        .disabled(isGeneratingPDF)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let data = pdfData {
                ActivityViewController(activityItems: [data])
            }
        }
        .onAppear {
            combinedSummary = yearWrap
            parsedData = parseYearWrapJSON(from: yearWrap.text)
            Task {
                await loadYearStats()
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadYearStats() async {
        guard let dbManager = coordinator.getDatabaseManager() else { return }
        
        let calendar = Calendar.current
        let year = calendar.component(.year, from: yearWrap.periodStart)
        
        // Fetch sessions for the year
        do {
            let yearlyData = try await dbManager.fetchSessionsByYear()
            if let yearData = yearlyData.first(where: { $0.year == year }) {
                totalSessions = yearData.count
                
                // Calculate total duration and words
                var duration: TimeInterval = 0
                var words: Int = 0
                
                for sessionId in yearData.sessionIds {
                    let chunks = try? await dbManager.fetchChunksBySession(sessionId: sessionId)
                    duration += chunks?.reduce(0) { $0 + $1.duration } ?? 0
                    
                    let wordCount = try? await dbManager.fetchSessionWordCount(sessionId: sessionId)
                    words += wordCount ?? 0
                }
                
                await MainActor.run {
                    totalDuration = duration
                    totalWords = words
                }
            }
        } catch {
            print("❌ Failed to load year stats: \(error)")
        }
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        ZStack {
            // Background gradient
            YearWrapTheme.electricPurple
            
            VStack(spacing: 16) {
                // Sparkles icon
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(AppTheme.onAccent)
                
                // Year title
                if let data = parsedData {
                    Text(data.yearTitle)
                        .font(AppTheme.titleFont(size: 30))
                        .foregroundStyle(AppTheme.onAccent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    // Year summary
                    Text(data.yearSummary)
                        .font(.body)
                        .foregroundStyle(AppTheme.onAccent.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                }
            }
            .padding(.vertical, 40)
        }
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        HStack(spacing: 16) {
            statCard(title: "Sessions", value: "\(totalSessions)", icon: "mic.fill", color: YearWrapTheme.spotifyGreen)
            statCard(title: "Hours", value: String(format: "%.1f", totalDuration / 3600), icon: "clock.fill", color: YearWrapTheme.hotPink)
            statCard(title: "Words", value: formatNumber(totalWords), icon: "text.bubble.fill", color: YearWrapTheme.vibrantOrange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.card).stroke(AppTheme.hairline, lineWidth: 1)
        )
    }
    
    // MARK: - Insight Sections
    
    @ViewBuilder
    private func majorArcsSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "Major arcs",
            icon: "book",
            items: items,
            color: AppTheme.accent,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func biggestWinsSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "Biggest wins",
            icon: "trophy",
            items: items,
            color: YearWrapTheme.winsColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func biggestLossesSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "Biggest losses",
            icon: "heart.slash",
            items: items,
            color: YearWrapTheme.lossesColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func biggestChallengesSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "Biggest challenges",
            icon: "bolt",
            items: items,
            color: YearWrapTheme.challengesColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func finishedProjectsSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "Finished projects",
            icon: "checkmark.circle",
            items: items,
            color: YearWrapTheme.finishedProjectsColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func unfinishedProjectsSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "Unfinished projects",
            icon: "pause.circle",
            items: items,
            color: YearWrapTheme.unfinishedProjectsColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func topWorkedOnSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "Top worked-on topics",
            icon: "hammer",
            items: items,
            color: YearWrapTheme.topicsColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func topTalkedAboutSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "Top talked-about things",
            icon: "bubble.left",
            items: items,
            color: YearWrapTheme.peopleColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func valuableActionsSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "Valuable actions taken",
            icon: "diamond",
            items: items,
            color: YearWrapTheme.actionsColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func opportunitiesMissedSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "Opportunities missed",
            icon: "scope",
            items: items,
            color: YearWrapTheme.opportunitiesColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func peopleMentionedSection(_ people: [PersonMention]) -> some View {
        if people.isEmpty {
            insightSection(title: "People mentioned", icon: "person.2", items: [] as [ClassifiedItem], color: AppTheme.accent, emptyMessage: "None")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    sectionHeader("People mentioned", icon: "person.2")
                    Spacer()
                }
                
                // People list
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(people, id: \.name) { person in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(redactPeople ? "[Person]" : person.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            if let relationship = person.relationship {
                                Text(relationship)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let impact = person.impact {
                                Text(impact)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }
                            
                            if let sessionIds = person.sessionIds, !sessionIds.isEmpty {
                                recordingsLink(title: redactPeople ? "Person" : person.name, sessionIds: sessionIds)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppTheme.accent.opacity(0.1))
                        )
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.card).stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
    }
    
    @ViewBuilder
    private func placesVisitedSection(_ places: [PlaceVisit]) -> some View {
        if places.isEmpty {
            insightSection(title: "Places visited", icon: "mappin.and.ellipse", items: [] as [ClassifiedItem], color: AppTheme.accent, emptyMessage: "None")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    sectionHeader("Places visited", icon: "mappin.and.ellipse")
                    Spacer()
                }
                
                // Places list
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(places, id: \.name) { place in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(redactPlaces ? "[Location]" : place.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            if let frequency = place.frequency {
                                Text(frequency)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let context = place.context {
                                Text(context)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }
                            
                            if let sessionIds = place.sessionIds, !sessionIds.isEmpty {
                                recordingsLink(title: redactPlaces ? "Place" : place.name, sessionIds: sessionIds)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppTheme.accent.opacity(0.1))
                        )
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.card).stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
    }
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label {
            Text(title)
                .font(AppTheme.titleFont(size: 20))
                .foregroundStyle(AppTheme.textPrimary)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // Generic insight section builder
    @ViewBuilder
    private func insightSection(title: String, icon: String, items: [ClassifiedItem], color: Color, emptyMessage: String) -> some View {
        let filteredItems = filterItems(items, by: displayFilter)
        
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                sectionHeader(title, icon: icon)
                Spacer()
            }
            
            // Content
            if filteredItems.isEmpty {
                Text(emptyMessage)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(filteredItems.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(color)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.text)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                HStack(spacing: 8) {
                                    categoryBadge(for: item.category)
                                    if let sessionIds = item.sessionIds, !sessionIds.isEmpty {
                                        recordingsLink(title: item.text, sessionIds: sessionIds)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.card).stroke(AppTheme.hairline, lineWidth: 1)
        )
    }
    
    /// "3 recordings ›", opening the recordings an item came from
    private func recordingsLink(title: String, sessionIds: [UUID]) -> some View {
        NavigationLink {
            FilteredSessionsView(title: title, sessionIds: sessionIds)
                .environmentObject(coordinator)
        } label: {
            HStack(spacing: 2) {
                Text(sessionIds.count == 1 ? "1 recording" : "\(sessionIds.count) recordings")
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityHint("Shows the recordings this came from")
    }
    
    // Category badge view
    @ViewBuilder
    private func categoryBadge(for category: ItemCategory) -> some View {
        HStack(spacing: 4) {
            switch category {
            case .work:
                Label("Work", systemImage: "briefcase.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.onAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
            case .personal:
                Label("Personal", systemImage: "house.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.onAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
            case .both:
                HStack(spacing: 4) {
                    Label("Work", systemImage: "briefcase.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent)
                        .clipShape(Capsule())
                    
                    Label("Personal", systemImage: "house.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent)
                        .clipShape(Capsule())
                }
            }
        }
    }
    
    // MARK: - Filtering Helper
    
    private func filterItems(_ items: [ClassifiedItem], by filter: ItemFilter) -> [ClassifiedItem] {
        switch filter {
        case .all:
            return items
        case .workOnly:
            // Include items that are work OR both (since both applies to work too)
            return items.filter { $0.category == .work || $0.category == .both }
        case .personalOnly:
            // Include items that are personal OR both (since both applies to personal too)
            return items.filter { $0.category == .personal || $0.category == .both }
        }
    }
    
    // MARK: - Footer
    
    private var footerSection: some View {
        Text("Showing high-confidence entities (≥70%)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.vertical, 16)
            .padding(.horizontal, 32)
    }
    
    // MARK: - Helpers
    
    private func parseYearWrapJSON(from text: String) -> YearWrapData? {
        guard let data = text.data(using: .utf8) else {
            print("❌ [YearWrapDetailView] Failed to convert text to data")
            return nil
        }
        
        do {
            // Try new format first (ClassifiedItem arrays)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let decoded = try decoder.decode(YearWrapData.self, from: data)
            print("✅ [YearWrapDetailView] Successfully parsed Year Wrap data (new format)")
            
            // Debug: Log category distribution
            let allItems = decoded.majorArcs + decoded.biggestWins + decoded.biggestLosses + 
                          decoded.biggestChallenges + decoded.finishedProjects + decoded.unfinishedProjects +
                          decoded.topWorkedOnTopics + decoded.topTalkedAboutThings + 
                          decoded.valuableActionsTaken + decoded.opportunitiesMissed
            let workCount = allItems.filter { $0.category == .work }.count
            let personalCount = allItems.filter { $0.category == .personal }.count
            let bothCount = allItems.filter { $0.category == .both }.count
            print("📊 [YearWrapDetailView] Category distribution: \(workCount) work, \(personalCount) personal, \(bothCount) both (total: \(allItems.count))")
            
            return decoded
        } catch let newFormatError {
            // If new format fails, try parsing old format (string arrays) and convert
            print("⚠️ [YearWrapDetailView] New format decode failed, trying old format: \(newFormatError)")
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ [YearWrapDetailView] Failed to parse as JSON object")
                return nil
            }
            
            // Check for year_summary - required field for all formats
            guard let yearSummary = json["year_summary"] as? String else {
                print("❌ [YearWrapDetailView] No year_summary field found")
                return nil
            }
            
            let yearTitle = json["year_title"] as? String ?? "Year in Review"
            
            // Helper to convert old string arrays to ClassifiedItem arrays
            func parseStringArray(_ key: String) -> [ClassifiedItem] {
                guard let strings = json[key] as? [String] else { return [] }
                return strings.map { ClassifiedItem(text: $0, category: .both) }
            }
            
            // Check if this is simplified Local AI format (has top_highlights instead of detailed fields)
            let isSimplifiedFormat = json["top_highlights"] != nil
            
            if isSimplifiedFormat {
                print("🤖 [YearWrapDetailView] Detected simplified Local AI format")
                
                // Parse Local AI simplified format
                let topHighlights = parseStringArray("top_highlights")
                let challenges = parseStringArray("biggest_challenges")
                let topics = parseStringArray("top_topics")
                
                // Create Year Wrap with available data, using highlights as wins
                let yearWrap = YearWrapData(
                    yearTitle: yearTitle,
                    yearSummary: yearSummary,
                    majorArcs: [],
                    biggestWins: topHighlights,
                    biggestLosses: [],
                    biggestChallenges: challenges,
                    finishedProjects: [],
                    unfinishedProjects: [],
                    topWorkedOnTopics: topics,
                    topTalkedAboutThings: [],
                    valuableActionsTaken: [],
                    opportunitiesMissed: [],
                    peopleMentioned: [],
                    placesVisited: []
                )
                
                print("✅ [YearWrapDetailView] Successfully parsed Year Wrap data (Local AI simplified format)")
                return yearWrap
            }
            
            // Standard old format with detailed fields
            let yearWrap = YearWrapData(
                yearTitle: yearTitle,
                yearSummary: yearSummary,
                majorArcs: parseStringArray("major_arcs"),
                biggestWins: parseStringArray("biggest_wins"),
                biggestLosses: parseStringArray("biggest_losses"),
                biggestChallenges: parseStringArray("biggest_challenges"),
                finishedProjects: parseStringArray("finished_projects"),
                unfinishedProjects: parseStringArray("unfinished_projects"),
                topWorkedOnTopics: parseStringArray("top_worked_on_topics"),
                topTalkedAboutThings: parseStringArray("top_talked_about_things"),
                valuableActionsTaken: parseStringArray("valuable_actions_taken"),
                opportunitiesMissed: parseStringArray("opportunities_missed"),
                peopleMentioned: (json["people_mentioned"] as? [[String: String]] ?? []).compactMap { dict in
                    guard let name = dict["name"] else { return nil }
                    return PersonMention(name: name, relationship: dict["relationship"], impact: dict["impact"])
                },
                placesVisited: (json["places_visited"] as? [[String: String]] ?? []).compactMap { dict in
                    guard let name = dict["name"] else { return nil }
                    return PlaceVisit(name: name, frequency: dict["frequency"], context: dict["context"])
                }
            )
            
            print("✅ [YearWrapDetailView] Successfully parsed Year Wrap data (old format, converted)")
            return yearWrap
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1000 {
            return String(format: "%.1fK", Double(number) / 1000)
        }
        return "\(number)"
    }
    
    private func generatePDF() async {
        isGeneratingPDF = true
        defer { isGeneratingPDF = false }
        
        guard let dbManager = coordinator.getDatabaseManager() else {
            coordinator.showError("Failed to access database")
            return
        }
        
        do {
            let calendar = Calendar.current
            let year = calendar.component(.year, from: yearWrap.periodStart)
            
            let exporter = DataExporter(databaseManager: dbManager)
            let data = try await exporter.exportToPDF(year: year, redactPeople: redactPeople, redactPlaces: redactPlaces, filter: displayFilter)
            
            await MainActor.run {
                pdfData = data
                showingShareSheet = true
            }
        } catch {
            coordinator.showError("Failed to generate PDF: \(error.localizedDescription)")
        }
    }
}

// MARK: - Helper Types

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // Add completion handler to dismiss sheet when done
        controller.completionWithItemsHandler = { _, _, _, _ in
            dismiss()
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
