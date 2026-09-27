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
    /// This year's wraps by filter. All is always there; Work and Personal when they had recordings.
    let wraps: [ItemFilter: Summary]
    let coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var redactPeople = false
    @State private var redactPlaces = false
    @State private var displayFilter: ItemFilter
    @State private var parsedWraps: [ItemFilter: YearWrapData] = [:]
    /// Counted from the database, only for older wraps that don't carry their own stats
    @State private var countedStats: (sessions: Int, duration: TimeInterval, words: Int)?
    @State private var pdfData: Data?
    @State private var isGeneratingPDF = false
    @State private var showingShareSheet = false
    
    init(wraps: [ItemFilter: Summary], coordinator: AppCoordinator, initialFilter: ItemFilter = .all) {
        self.wraps = wraps
        self.coordinator = coordinator
        _displayFilter = State(initialValue: initialFilter)
    }
    
    /// True when the chosen filter has a wrap of its own. Older years only have the All wrap;
    /// Work and Personal then show its items for that category.
    private var hasOwnWrap: Bool {
        wraps[displayFilter] != nil
    }
    
    private var activeSummary: Summary? {
        wraps[displayFilter] ?? wraps[.all]
    }
    
    private var year: Int {
        let start = activeSummary?.periodStart ?? wraps.values.first?.periodStart ?? Date()
        return Calendar.current.component(.year, from: start)
    }
    
    private var parsedData: YearWrapData? {
        parsedWraps[displayFilter] ?? parsedWraps[.all]
    }
    
    /// The parsed wrap with any redaction applied
    private var displayData: YearWrapData? {
        parsedData?.redacted(people: redactPeople, places: redactPlaces)
    }
    
    /// Sheet width, to show the sections two-up when there's room (iPad)
    @State private var contentWidth: CGFloat = 0
    private var sectionsTwoUp: Bool { contentWidth >= 760 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    heroSection
                    statsSection
                    
                    if let data = displayData {
                        // Wide sheet (iPad): sections side by side instead of one long column
                        sectionCards(data, twoUp: sectionsTwoUp)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                    } else if let activeSummary {
                        // Fallback: show raw text if parsing fails
                        Text(activeSummary.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                }
            }
            .onWidthChange { contentWidth = $0 }
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
                                Label("Hide top people", systemImage: "person.slash")
                            }
                            
                            Toggle(isOn: $redactPlaces) {
                                Label("Hide top places", systemImage: "mappin.slash")
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
        .task {
            // .task runs once per presentation, not again when coming back from a recordings list
            guard parsedWraps.isEmpty else { return }
            parsedWraps = wraps.compactMapValues { YearWrapData.parse($0.text) }
            if parsedWraps[.all]?.stats == nil {
                await countYearStats()
            }
        }
    }
    
    // MARK: - Data Loading
    
    /// Totals for wraps made before stats were stored with the wrap
    private func countYearStats() async {
        guard let dbManager = coordinator.getDatabaseManager() else { return }
        do {
            let yearlyData = try await dbManager.fetchSessionsByYear()
            guard let yearData = yearlyData.first(where: { $0.year == year }) else { return }
            var duration: TimeInterval = 0
            var words = 0
            for sessionId in yearData.sessionIds {
                let chunks = try? await dbManager.fetchChunksBySession(sessionId: sessionId)
                duration += chunks?.reduce(0) { $0 + $1.duration } ?? 0
                words += (try? await dbManager.fetchSessionWordCount(sessionId: sessionId)) ?? 0
            }
            countedStats = (yearData.count, duration, words)
        } catch {
            print("❌ Failed to load year stats: \(error)")
        }
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        ZStack {
            YearWrapTheme.electricPurple
            
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .scaledFont(size: 44, weight: .light)
                    .foregroundStyle(AppTheme.onAccent)
                    .accessibilityHidden(true)
                
                Text(displayFilter == .all ? String(year) : "\(year) · \(displayFilter.displayName.capitalized)")
                    .font(.caption)
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.onAccent.opacity(0.7))
                
                if let data = displayData, let journals = data.journals, !journals.isEmpty {
                    // All: each journal's own story, one after the other
                    ForEach(journals, id: \.category) { journal in
                        VStack(spacing: 8) {
                            Label(journal.category.displayName.uppercased(), systemImage: journal.category == .work ? "briefcase.fill" : "house.fill")
                                .font(.caption)
                                .tracking(0.8)
                                .foregroundStyle(AppTheme.onAccent.opacity(0.7))
                            Text(journal.title)
                                .scaledFont(size: 26, design: .serif)
                                .foregroundStyle(AppTheme.onAccent)
                                .multilineTextAlignment(.center)
                                .accessibilityAddTraits(.isHeader)
                            Text(journal.summary)
                                .font(.body)
                                .foregroundStyle(AppTheme.onAccent.opacity(0.9))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 8)
                    }
                } else if let data = displayData {
                    Text(data.yearTitle)
                        .scaledFont(size: 30, design: .serif)
                        .foregroundStyle(AppTheme.onAccent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .accessibilityAddTraits(.isHeader)
                    
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
    
    @ViewBuilder
    private var statsSection: some View {
        VStack(spacing: 12) {
            if let stats = parsedData?.stats {
                // A wrap's own stats already cover just its category
                switch hasOwnWrap ? .all : displayFilter {
                case .all:
                    HStack(spacing: 16) {
                        statCard(title: "Recordings", value: "\(stats.sessionCount)", icon: "mic.fill")
                        statCard(title: "Hours", value: String(format: "%.1f", Double(stats.totalMinutes) / 60), icon: "clock.fill")
                        statCard(title: "Words", value: formatNumber(stats.wordCount), icon: "text.bubble.fill")
                    }
                    if let line = activityLine(stats) {
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                case .workOnly, .personalOnly:
                    let isWork = displayFilter == .workOnly
                    let count = isWork ? stats.workCount : stats.personalCount
                    let share = stats.sessionCount > 0 ? Int((Double(count) / Double(stats.sessionCount) * 100).rounded()) : 0
                    HStack(spacing: 16) {
                        statCard(title: isWork ? "Work recordings" : "Personal recordings", value: "\(count)", icon: isWork ? "briefcase.fill" : "house.fill")
                        statCard(title: "Of all recordings", value: "\(share)%", icon: "chart.pie.fill")
                    }
                }
            } else if let counted = countedStats {
                HStack(spacing: 16) {
                    statCard(title: "Recordings", value: "\(counted.sessions)", icon: "mic.fill")
                    statCard(title: "Hours", value: String(format: "%.1f", counted.duration / 3600), icon: "clock.fill")
                    statCard(title: "Words", value: formatNumber(counted.words), icon: "text.bubble.fill")
                }
                if displayFilter != .all {
                    Text("Totals cover all recordings. Regenerate the wrap to see work and personal counts.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
    
    /// "Recorded on 143 days · Busiest month: March"
    private func activityLine(_ stats: YearWrapStats) -> String? {
        var parts: [String] = []
        if stats.activeDays > 0 {
            parts.append(stats.activeDays == 1 ? "Recorded on 1 day" : "Recorded on \(stats.activeDays) days")
        }
        if let month = stats.busiestMonth, (1...12).contains(month) {
            parts.append("Busiest month: \(Calendar.current.monthSymbols[month - 1])")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    
    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            
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
        .accessibilityElement(children: .combine)
    }
    
    // MARK: - Insight Sections
    
    private struct InsightSection {
        let title: String
        let icon: String
        let color: Color
        let items: [ClassifiedItem]
    }
    
    private func sections(_ data: YearWrapData) -> [InsightSection] {
        [
            InsightSection(title: "Major arcs", icon: "book", color: AppTheme.accent, items: data.majorArcs),
            InsightSection(title: "Biggest wins", icon: "trophy", color: YearWrapTheme.winsColor, items: data.biggestWins),
            InsightSection(title: "Biggest losses", icon: "heart.slash", color: YearWrapTheme.lossesColor, items: data.biggestLosses),
            InsightSection(title: "Biggest challenges", icon: "bolt", color: YearWrapTheme.challengesColor, items: data.biggestChallenges),
            InsightSection(title: "Finished projects", icon: "checkmark.circle", color: YearWrapTheme.finishedProjectsColor, items: data.finishedProjects),
            InsightSection(title: "Unfinished projects", icon: "pause.circle", color: YearWrapTheme.unfinishedProjectsColor, items: data.unfinishedProjects),
            InsightSection(title: "Top worked-on topics", icon: "hammer", color: YearWrapTheme.topicsColor, items: data.topWorkedOnTopics),
            InsightSection(title: "Top talked-about things", icon: "bubble.left", color: YearWrapTheme.peopleColor, items: data.topTalkedAboutThings),
            InsightSection(title: "Valuable actions taken", icon: "diamond", color: YearWrapTheme.actionsColor, items: data.valuableActionsTaken),
            InsightSection(title: "Opportunities missed", icon: "scope", color: YearWrapTheme.opportunitiesColor, items: data.opportunitiesMissed),
        ]
    }
    
    /// Sections with something to show under the current filter. Empty ones are left out,
    /// like in the PDF export.
    private func visibleSections(_ data: YearWrapData) -> [InsightSection] {
        sections(data).compactMap { section -> InsightSection? in
            let items = filterItems(section.items, by: displayFilter)
            return items.isEmpty ? nil : InsightSection(title: section.title, icon: section.icon, color: section.color, items: items)
        }
    }

    /// One card in the list of sections
    private enum WrapCard: Identifiable {
        case insight(InsightSection)
        case people([PersonMention])
        case places([PlaceVisit])

        var id: String {
            switch self {
            case .insight(let section): return section.title
            case .people: return "people"
            case .places: return "places"
            }
        }
    }

    private func wrapCards(_ data: YearWrapData) -> [WrapCard] {
        var cards = visibleSections(data).map(WrapCard.insight)
        if !data.peopleMentioned.isEmpty { cards.append(.people(data.peopleMentioned)) }
        if !data.placesVisited.isEmpty { cards.append(.places(data.placesVisited)) }
        return cards
    }

    @ViewBuilder
    private func wrapCard(_ card: WrapCard) -> some View {
        switch card {
        case .insight(let section): insightSection(section)
        case .people(let people): peopleMentionedSection(people)
        case .places(let places): placesVisitedSection(places)
        }
    }

    /// The sections as cards: one column, or two-up with each pair sharing a row height
    @ViewBuilder
    private func sectionCards(_ data: YearWrapData, twoUp: Bool) -> some View {
        let cards = wrapCards(data)
        VStack(spacing: 24) {
            if visibleSections(data).isEmpty {
                Text(displayFilter == .all ? "Nothing to show for this year yet." : "Nothing tagged \(displayFilter.displayName.lowercased()) this year.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
            if twoUp {
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { index in
                        GridRow(alignment: .top) {
                            wrapCard(cards[index])
                            if index + 1 < cards.count {
                                wrapCard(cards[index + 1])
                            } else {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            }
                        }
                    }
                }
            } else {
                ForEach(cards) { wrapCard($0) }
            }
        }
    }
    
    @ViewBuilder
    private func peopleMentionedSection(_ people: [PersonMention]) -> some View {
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("People mentioned", icon: "person.2")
                
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(person.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if let category = person.category {
                                    categoryBadge(for: category)
                                }
                            }
                            
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
                                recordingsLink(title: person.name, sessionIds: sessionIds)
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
            // maxHeight lets paired cards in the iPad grid share their row's height
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.card).stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
    }
    
    @ViewBuilder
    private func placesVisitedSection(_ places: [PlaceVisit]) -> some View {
        if !places.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Places visited", icon: "mappin.and.ellipse")
                
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(place.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if let category = place.category {
                                    categoryBadge(for: category)
                                }
                            }
                            
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
                                recordingsLink(title: place.name, sessionIds: sessionIds)
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
            // maxHeight lets paired cards in the iPad grid share their row's height
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.card).stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
    }
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label {
            Text(title)
                .scaledFont(size: 20, design: .serif)
                .foregroundStyle(AppTheme.textPrimary)
        } icon: {
            Image(systemName: icon)
                .scaledFont(size: 16, weight: .regular)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func insightSection(_ section: InsightSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(section.title, icon: section.icon)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(section.color)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                            .accessibilityHidden(true)
                        
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
        .padding(16)
        // maxHeight lets paired cards in the iPad grid share their row's height
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    
    private func categoryBadge(for category: ItemCategory) -> some View {
        HStack(spacing: 4) {
            if category != .personal {
                badge("Work", icon: "briefcase.fill")
            }
            if category != .work {
                badge("Personal", icon: "house.fill")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category == .both ? "Work and personal" : (category == .work ? "Work" : "Personal"))
    }
    
    private func badge(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .foregroundStyle(AppTheme.onAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.accent)
            .clipShape(Capsule())
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
    
    // MARK: - Helpers
    
    /// 850, 12.4K, 1.2M
    private func formatNumber(_ number: Int) -> String {
        number.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
    
    private func generatePDF() async {
        isGeneratingPDF = true
        defer { isGeneratingPDF = false }
        
        guard let dbManager = coordinator.getDatabaseManager() else {
            coordinator.showError("Failed to access database")
            return
        }
        
        do {
            let exporter = DataExporter(databaseManager: dbManager)
            let data = try await exporter.exportToPDF(year: year, redactPeople: redactPeople, redactPlaces: redactPlaces, filter: displayFilter)
            pdfData = data
            showingShareSheet = true
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
