import SwiftUI
import SharedModels
import Storage

// MARK: - ItemFilter Extensions for UI

extension ItemFilter: Identifiable {
    public var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .all: return "All Items"
        case .workOnly: return "Work Only"
        case .personalOnly: return "Personal Only"
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
    let yearWrap: Summary
    let coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var redactPeople = false
    @State private var redactPlaces = false
    @State private var pdfFilter: ItemFilter = .all
    @State private var parsedData: YearWrapData?
    @State private var totalSessions: Int = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var totalWords: Int = 0
    @State private var pdfData: Data?
    @State private var isGeneratingPDF = false
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero Section
                    heroSection
                    
                    // Stats Grid
                    statsSection
                    
                    // Insights Sections
                    if let data = parsedData {
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
                        Text(yearWrap.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                    
                    // Footer
                    footerSection
                }
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("PDF Content Filter") {
                            Picker("Filter Items", selection: $pdfFilter) {
                                ForEach(ItemFilter.allCases) { filter in
                                    Label(filter.displayName, systemImage: filter.icon)
                                        .tag(filter)
                                }
                            }
                        }
                        
                        Section("Privacy") {
                            Toggle(isOn: $redactPeople) {
                                Label("Redact People", systemImage: "person.slash")
                            }
                            
                            Toggle(isOn: $redactPlaces) {
                                Label("Redact Places", systemImage: "mappin.slash")
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
            LinearGradient(
                colors: [
                    YearWrapTheme.electricPurple,
                    YearWrapTheme.electricPurple.opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 16) {
                // Sparkles icon
                Text("✨")
                    .font(.system(size: 60))
                
                // Year title
                if let data = parsedData {
                    Text(data.yearTitle)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    // Year summary
                    Text(data.yearSummary)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
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
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    // MARK: - Insight Sections
    
    @ViewBuilder
    private func majorArcsSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "📖 Major Arcs",
            items: items,
            color: .cyan,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func biggestWinsSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "🏆 Biggest Wins",
            items: items,
            color: YearWrapTheme.winsColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func biggestLossesSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "💔 Biggest Losses",
            items: items,
            color: YearWrapTheme.lossesColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func biggestChallengesSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "⚡ Biggest Challenges",
            items: items,
            color: YearWrapTheme.challengesColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func finishedProjectsSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "✅ Finished Projects",
            items: items,
            color: YearWrapTheme.finishedProjectsColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func unfinishedProjectsSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "⏸️ Unfinished Projects",
            items: items,
            color: YearWrapTheme.unfinishedProjectsColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func topWorkedOnSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "🔨 Top Worked-On Topics",
            items: items,
            color: YearWrapTheme.topicsColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func topTalkedAboutSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "💬 Top Talked-About Things",
            items: items,
            color: YearWrapTheme.peopleColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func valuableActionsSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "💎 Valuable Actions Taken",
            items: items,
            color: YearWrapTheme.actionsColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func opportunitiesMissedSection(_ items: [ClassifiedItem]) -> some View {
        insightSection(
            title: "🎯 Opportunities Missed",
            items: items,
            color: YearWrapTheme.opportunitiesColor,
            emptyMessage: "None"
        )
    }
    
    @ViewBuilder
    private func peopleMentionedSection(_ people: [PersonMention]) -> some View {
        if people.isEmpty {
            insightSection(title: "👥 People Mentioned", items: [] as [ClassifiedItem], color: .blue, emptyMessage: "None")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("👥 People Mentioned")
                        .font(.headline)
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
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }
    
    @ViewBuilder
    private func placesVisitedSection(_ places: [PlaceVisit]) -> some View {
        if places.isEmpty {
            insightSection(title: "📍 Places Visited", items: [] as [ClassifiedItem], color: .purple, emptyMessage: "None")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("📍 Places Visited")
                        .font(.headline)
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
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.purple.opacity(0.1))
                        )
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }
    
    // Generic insight section builder
    @ViewBuilder
    private func insightSection(title: String, items: [ClassifiedItem], color: Color, emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
            }
            
            // Content
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(color)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.text)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                categoryBadge(for: item.category)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    // Category badge view
    @ViewBuilder
    private func categoryBadge(for category: ItemCategory) -> some View {
        HStack(spacing: 4) {
            switch category {
            case .work:
                Label("Work", systemImage: "briefcase.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .clipShape(Capsule())
            case .personal:
                Label("Personal", systemImage: "house.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .clipShape(Capsule())
            case .both:
                HStack(spacing: 4) {
                    Label("Work", systemImage: "briefcase.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .clipShape(Capsule())
                    
                    Label("Personal", systemImage: "house.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .clipShape(Capsule())
                }
            }
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
            return decoded
        } catch let newFormatError {
            // If new format fails, try parsing old format (string arrays) and convert
            print("⚠️ [YearWrapDetailView] New format decode failed, trying old format: \(newFormatError)")
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let yearTitle = json["year_title"] as? String,
                  let yearSummary = json["year_summary"] as? String else {
                print("❌ [YearWrapDetailView] Failed to parse old format")
                return nil
            }
            
            // Helper to convert old string arrays to ClassifiedItem arrays
            func parseStringArray(_ key: String) -> [ClassifiedItem] {
                guard let strings = json[key] as? [String] else { return [] }
                return strings.map { ClassifiedItem(text: $0, category: .both) }
            }
            
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
            let data = try await exporter.exportToPDF(year: year, redactPeople: redactPeople, redactPlaces: redactPlaces, filter: pdfFilter)
            
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
