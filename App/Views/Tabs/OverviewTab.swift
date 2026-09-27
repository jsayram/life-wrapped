import SwiftUI
import SharedModels
import Summarization

struct OverviewTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.colorScheme) var colorScheme
    @State private var sessionCount: Int = 0
    @State private var sessionsInPeriod: [RecordingSession] = []
    /// This year's wraps: All, Work and Personal each have their own
    @State private var yearWraps: [ItemFilter: Summary] = [:]
    /// All / Work / Personal, shared by Month and Year so the choice carries between them
    @State private var categoryFilter: ItemFilter = .all
    @State private var monthDigest: MonthDigest?
    /// The shown month still comes from a digest saved before work and personal were separate
    @State private var monthDigestIsOld = false
    /// First day of the month the Month view shows; starts on the current month
    @State private var selectedMonth: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    /// Months with recordings, newest first, for the month switcher
    @State private var availableMonths: [Date] = []
    @State private var isUpdatingMonthDigest = false
    @State private var isLoading = true
    @State private var selectedTimeRange: TimeRange = .allTime
    @State private var showYearWrapConfirmation = false
    @State private var showPurchaseSheet = false
    
    // Session summaries for Today/Yesterday feed
    @State private var sessionSummaries: [Summary] = []
    /// Journal of each recording in the Today/Yesterday feed, from its saved category
    @State private var sessionJournals: [UUID: SessionCategory] = [:]
    
    // Navigation state for session detail
    @State private var selectedSession: RecordingSession?
    @State private var showSessionDetail = false
    
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Time Range Picker - ALWAYS show so users can switch periods
                GraphiteSegmentedControl(
                    options: TimeRange.allCases.map { .init(value: $0, title: $0.rawValue) },
                    selection: $selectedTimeRange
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .disabled(isLoading)
                
                // Which journal: one switch for every range, so the choice carries between them
                GraphiteSegmentedControl(
                    options: ItemFilter.allCases.map { .init(value: $0, title: $0.displayName.capitalized) },
                    selection: $categoryFilter
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Content area
                Group {
                    if isLoading {
                        LoadingView(size: .medium)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if sessionsInPeriod.isEmpty && yearWraps.isEmpty {
                        GraphiteEmptyState(
                            "No overview yet",
                            systemImage: "doc.text",
                            description: Text("Record more journal entries to generate summaries.")
                        )
                    } else {
                        // Copy All button
                        if !visibleSessionSummaries.isEmpty {
                            HStack {
                                Spacer()
                                Button {
                                    copyAllSummaries()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption)
                                        Text("Copy \(visibleSessionSummaries.count)")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.card).stroke(AppTheme.hairline, lineWidth: 1))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }
                        
                        // New Feed Layout
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                if selectedTimeRange == .month {
                                    monthSwitcher
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                }
                                
                                // Month digest while it's being built for the first time
                                if selectedTimeRange == .month && monthDigest == nil && isUpdatingMonthDigest {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("Building the \(selectedMonth.formatted(.dateTime.month(.wide))) digest…")
                                            .font(.footnote)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 8)
                                }
                                
                                // The month's digest: both journals, or the one chosen above
                                if selectedTimeRange == .month, let monthDigest {
                                    MonthDigestCard(
                                        digest: monthDigest,
                                        filter: categoryFilter,
                                        isUpdating: isUpdatingMonthDigest,
                                        isSplitting: monthDigestIsOld && isUpdatingMonthDigest,
                                        onCopy: {
                                            UIPasteboard.general.string = monthDigest.plainText(filter: categoryFilter)
                                            coordinator.showSuccess("Month copied")
                                        },
                                        onRegenerate: {
                                            Task { await refreshMonthDigest(force: true) }
                                            }
                                        )
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                }
                                
                                // Year Wrapped Summary (only show for Year timerange)
                                if selectedTimeRange == .allTime {
                                    yearWrapSection
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                        .animation(.easeInOut, value: coordinator.isGeneratingYearWrap)
                                }
                            }
                            
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                // Only buckets with summaries; empty hours add noise
                                let timeBuckets = groupSessionsByTimeBucket().filter { !$0.isEmpty }
                                
                                if timeBuckets.isEmpty && [.today, .yesterday].contains(selectedTimeRange) {
                                    // Today and Yesterday list session summaries; the other ranges already
                                    // show their summary card, a generate card or the Year Wrap above
                                    GraphiteEmptyState(
                                        categoryFilter == .all ? "No summaries yet" : "No \(categoryFilter.displayName.lowercased()) recordings",
                                        systemImage: "doc.text",
                                        description: Text(categoryFilter == .all
                                            ? "Session summaries will appear here once recordings are summarized."
                                            : "Recordings you make as \(categoryFilter.displayName.capitalized) will appear here.")
                                    )
                                    .padding(.top, 60)
                                } else {
                                    ForEach(timeBuckets) { bucket in
                                        Section {
                                            if bucket.isEmpty {
                                                // Empty bucket - show grayed out message
                                                Text("No recordings")
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                                    .italic()
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 8)
                                            } else {
                                                // Summaries in this bucket
                                                ForEach(bucket.summaries) { summary in
                                                    SessionSummaryCard(summary: summary, coordinator: coordinator) { session in
                                                        selectedSession = session
                                                        showSessionDetail = true
                                                    }
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 6)
                                                }
                                            }
                                        } header: {
                                            // Time bucket header
                                            HStack {
                                                Text(bucket.header)
                                                    .font(.footnote.weight(.semibold))
                                                    .foregroundStyle(AppTheme.textPrimary)
                                                
                                                Spacer()
                                                
                                                if !bucket.isEmpty {
                                                    Text("\(bucket.summaries.count) summar\(bucket.summaries.count == 1 ? "y" : "ies")")
                                                        .font(.footnote)
                                                        .foregroundStyle(AppTheme.textSecondary)
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(AppTheme.background)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .background(AppTheme.background)
            .themedScreen()
            .navigationTitle("Overview")
            .navigationDestination(isPresented: $showSessionDetail) {
                if let session = selectedSession {
                    SessionDetailView(session: session)
                }
            }
            .task {
                await loadInsights()
            }
            .refreshable {
                await loadInsights()
            }
            .onReceive(NotificationCenter.default.publisher(for: .periodSummariesUpdated)) { _ in
                Task {
                    await loadInsights()
                }
            }
            .onChange(of: selectedMonth) { _, _ in
                monthDigest = nil
                Task {
                    await loadInsights()
                }
            }
            .onChange(of: selectedTimeRange) { oldValue, newValue in
                Task {
                    await loadInsights()
                }
            }
            .sheet(isPresented: $showYearWrapConfirmation) {
                YearWrapGenerationSheet(
                    isSmartestAIUnlocked: coordinator.storeManager.isSmartestAIUnlocked,
                    smartestAIPrice: coordinator.storeManager.smartestAIProduct?.displayPrice,
                    isPurchasing: coordinator.storeManager.purchaseState == .purchasing,
                    onGenerate: { engine in
                        showYearWrapConfirmation = false
                        coordinator.startYearWrap(engine: engine)
                    },
                    onPurchaseSmartestAI: {
                        // Close this sheet and show purchase sheet
                        showYearWrapConfirmation = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showPurchaseSheet = true
                        }
                    },
                    onCancel: {
                        showYearWrapConfirmation = false
                    }
                )
                .environmentObject(coordinator)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPurchaseSheet) {
                SmartestPurchaseSheet(
                    price: coordinator.storeManager.smartestAIProduct?.displayPrice,
                    isPurchasing: coordinator.storeManager.purchaseState == .purchasing,
                    isRestoring: coordinator.storeManager.purchaseState == .restoring,
                    onPurchase: {
                        Task {
                            let success = await coordinator.storeManager.purchaseSmartestAI()
                            if success {
                                showPurchaseSheet = false
                                coordinator.showSuccess("Smartest AI unlocked! Configure your API key in Settings.")
                            }
                        }
                    },
                    onRestore: {
                        Task {
                            await coordinator.storeManager.restorePurchases()
                            if coordinator.storeManager.isSmartestAIUnlocked {
                                showPurchaseSheet = false
                                coordinator.showSuccess("Purchases restored!")
                            }
                        }
                    },
                    onRedeem: {
                        Task {
                            await coordinator.storeManager.presentRedeemCode()
                            if coordinator.storeManager.isSmartestAIUnlocked {
                                showPurchaseSheet = false
                                coordinator.showSuccess("Code redeemed!")
                            }
                        }
                    },
                    onCancel: {
                        showPurchaseSheet = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
    
    private func loadInsights() async {
        isLoading = true
        
        // Get date range for filtering
        let dateRange = getDateRange(for: selectedTimeRange)
        
        // Clear previous data to avoid stale counts when DB is unavailable
        sessionsInPeriod = []
        sessionCount = 0
        sessionSummaries = []
        
        // Load sessions in this period first
        if let dbManager = coordinator.getDatabaseManager() {
            if selectedTimeRange == .today || selectedTimeRange == .yesterday {
                sessionsInPeriod = (try? await dbManager.fetchSessionsByDate(date: dateRange.start)) ?? []
            } else {
                // For month/year, fetch ALL sessions and filter by date range
                let allSessions = try? await coordinator.fetchRecentSessions(limit: 10000)
                sessionsInPeriod = allSessions?.filter { session in
                    session.startTime >= dateRange.start && session.startTime < dateRange.end
                } ?? []
            }
            sessionCount = sessionsInPeriod.count
            
            // Load summaries based on time range
            switch selectedTimeRange {
            case .today, .yesterday:
                // Load session summaries for individual sessions
                let summaries = (try? await dbManager.fetchSessionSummariesInDateRange(
                    from: dateRange.start,
                    to: dateRange.end
                )) ?? []
                let ids = summaries.compactMap { $0.sessionId }
                // A deleted recording's summary can outlive it; only list recordings that still exist
                let existing = (try? await dbManager.existingSessionIds(among: ids)) ?? Set(ids)
                sessionSummaries = summaries.filter { $0.sessionId.map(existing.contains) ?? false }
                let metadata = (try? await dbManager.fetchSessionMetadataBatch(sessionIds: ids)) ?? [:]
                sessionJournals = metadata.compactMapValues { $0.category }
                print("✅ [OverviewTab] Loaded \(sessionSummaries.count) session summaries")
                
            case .month, .allTime:
                // Month digests and Year Wraps are loaded below
                break
            }
        }
        
        // Year Wraps are for the current year
        let dateForFetch = Date()

        if selectedTimeRange == .month {
            availableMonths = await coordinator.monthsWithRecordings()
            let status = await coordinator.fetchMonthDigestStatus(date: selectedMonth)
            monthDigest = status?.digest
            monthDigestIsOld = status?.usesLegacy ?? false
            // Build or refresh in the background; returns right away when nothing changed
            if !sessionsInPeriod.isEmpty || monthDigest == nil {
                Task { await refreshMonthDigest(force: false) }
            }
        } else {
            monthDigest = nil
        }

        if selectedTimeRange == .allTime {
            var wraps: [ItemFilter: Summary] = [:]
            for filter in ItemFilter.allCases {
                wraps[filter] = await coordinator.fetchYearWrap(for: filter, date: dateForFetch)
            }
            yearWraps = wraps
            
            // Staleness is measured against the All wrap, which every run writes
            if let yearWrap = wraps[.all] {
                let year = Calendar.current.component(.year, from: dateForFetch)
                if let newCount = try? await coordinator.getNewSessionsSinceYearWrap(yearWrap: yearWrap, year: year) {
                    coordinator.updateYearWrapNewSessionCount(newCount)
                }
            } else {
                coordinator.updateYearWrapNewSessionCount(0)
            }
        } else {
            yearWraps = [:]
            // Reset staleness count when not viewing Year
            coordinator.updateYearWrapNewSessionCount(0)
        }
        
        isLoading = false
    }
    
    private func refreshMonthDigest(force: Bool) async {
        guard !isUpdatingMonthDigest else { return }
        isUpdatingMonthDigest = true
        defer { isUpdatingMonthDigest = false }
        let month = selectedMonth
        let digest = await coordinator.updateMonthDigest(date: month, forceRegenerate: force)
        // Ignore a result for a month the user has already moved away from
        if selectedTimeRange == .month, month == selectedMonth, let digest {
            monthDigest = digest
            monthDigestIsOld = false
        }
    }
    
    /// The Year view's wrap for the chosen filter, its progress while generating, or a way to make one
    @ViewBuilder
    private var yearWrapSection: some View {
        let year = Calendar.current.component(.year, from: Date())
        if coordinator.isGeneratingYearWrap {
            YearWrapProgressCard(year: year, progress: coordinator.yearWrapProgress)
                .transition(.opacity)
        } else if let wrap = yearWraps[categoryFilter] {
            YearWrappedCard(
                summary: wrap,
                wraps: yearWraps,
                coordinator: coordinator,
                filter: categoryFilter,
                onRegenerate: { showYearWrapConfirmation = true }
            )
            .transition(.opacity)
        } else if yearWraps[.all] != nil {
            MissingCategoryWrapCard(filter: categoryFilter) {
                showYearWrapConfirmation = true
            }
        } else if !sessionsInPeriod.isEmpty {
            GenerateYearWrapCard {
                showYearWrapConfirmation = true
            }
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
    
    private func formatHourShort(_ hour: Int) -> String {
        if hour == 0 {
            return "12 AM"
        } else if hour < 12 {
            return "\(hour) AM"
        } else if hour == 12 {
            return "12 PM"
        } else {
            return "\(hour - 12) PM"
        }
    }
    
    private func formatDayOfWeek(_ dayOfWeek: Int) -> String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return days[dayOfWeek]
    }
    
    private func formatDayOfWeekFull(_ dayOfWeek: Int) -> String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[dayOfWeek]
    }
    
    // MARK: - Month switcher
    
    /// Current month plus every month with recordings, newest first
    private var switchableMonths: [Date] {
        let current = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        return Array(Set(availableMonths + [current, selectedMonth])).sorted(by: >)
    }
    
    /// ‹ September 2026 › — steps through months with recordings; tap the name to jump to any of them
    private var monthSwitcher: some View {
        let months = switchableMonths
        let index = months.firstIndex(of: selectedMonth)
        let older = index.flatMap { months.indices.contains($0 + 1) ? months[$0 + 1] : nil }
        let newer = index.flatMap { $0 > 0 ? months[$0 - 1] : nil }
        return HStack {
            Button {
                if let older { selectedMonth = older }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(older == nil ? AppTheme.hairline : AppTheme.textPrimary)
            }
            .disabled(older == nil)
            .accessibilityLabel("Previous month")
            
            Spacer()
            
            Menu {
                ForEach(months, id: \.self) { month in
                    Button(month.formatted(.dateTime.month(.wide).year())) { selectedMonth = month }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(AppTheme.textPrimary)
            }
            .accessibilityLabel("Choose month, \(selectedMonth.formatted(.dateTime.month(.wide).year()))")
            
            Spacer()
            
            Button {
                if let newer { selectedMonth = newer }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(newer == nil ? AppTheme.hairline : AppTheme.textPrimary)
            }
            .disabled(newer == nil)
            .accessibilityLabel("Next month")
        }
    }
    
    private func getDateRange(for timeRange: TimeRange) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch timeRange {
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let start = calendar.startOfDay(for: yesterday)
            // Use end-of-day so hourly buckets cover the full 24 hours
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? now
            return (start, end)
        case .today:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .month:
            // The month picked in the switcher: 1st of month to end of month
            let components = calendar.dateComponents([.year, .month], from: selectedMonth)
            let startOfMonth = calendar.date(from: components) ?? now
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1), to: startOfMonth) ?? now
            return (startOfMonth, endOfMonth)
        case .allTime:
            // Show only current year (e.g., 2025) up to today
            let currentYear = calendar.component(.year, from: now)
            let startOfYear = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1)) ?? now
            let endOfYear = calendar.date(from: DateComponents(year: currentYear + 1, month: 1, day: 1)) ?? now
            return (startOfYear, endOfYear)
        }
    }

    private func filterSession(_ session: (sessionId: UUID, duration: TimeInterval, date: Date)?, in range: (start: Date, end: Date)) -> (sessionId: UUID, duration: TimeInterval, date: Date)? {
        guard let session = session else { return nil }
        return session.date >= range.start && session.date <= range.end ? session : nil
    }
    
    private func filterMonth(_ month: (year: Int, month: Int, count: Int, sessionIds: [UUID])?, in range: (start: Date, end: Date)) -> (year: Int, month: Int, count: Int, sessionIds: [UUID])? {
        guard let month = month else { return nil }
        let calendar = Calendar.current
        guard let monthDate = calendar.date(from: DateComponents(year: month.year, month: month.month)) else { return nil }
        return monthDate >= range.start && monthDate <= range.end ? month : nil
    }
    
    private func filterSessionsByHour(_ sessions: [(hour: Int, count: Int, sessionIds: [UUID])], in range: (start: Date, end: Date)) async -> [(hour: Int, count: Int, sessionIds: [UUID])] {
        if range.start == Date.distantPast { return sessions }
        
        var filtered: [Int: [UUID]] = [:]
        
        for hourData in sessions {
            for sessionId in hourData.sessionIds {
                if let session = try? await coordinator.fetchSessions(ids: [sessionId]).first,
                   session.startTime >= range.start && session.startTime <= range.end {
                    filtered[hourData.hour, default: []].append(sessionId)
                }
            }
        }
        
        return filtered.map { (hour: $0.key, count: $0.value.count, sessionIds: $0.value) }
    }
    
    private func filterSessionsByDayOfWeek(_ sessions: [(dayOfWeek: Int, count: Int, sessionIds: [UUID])], in range: (start: Date, end: Date)) async -> [(dayOfWeek: Int, count: Int, sessionIds: [UUID])] {
        if range.start == Date.distantPast { return sessions }
        
        var filtered: [Int: [UUID]] = [:]
        
        for dayData in sessions {
            for sessionId in dayData.sessionIds {
                if let session = try? await coordinator.fetchSessions(ids: [sessionId]).first,
                   session.startTime >= range.start && session.startTime <= range.end {
                    filtered[dayData.dayOfWeek, default: []].append(sessionId)
                }
            }
        }
        
        return filtered.map { (dayOfWeek: $0.key, count: $0.value.count, sessionIds: $0.value) }
    }
    
    // MARK: - Time Bucketing for Feed View
    
    struct TimeBucket: Identifiable {
        let id = UUID()
        let header: String
        let summaries: [Summary]
        let isEmpty: Bool
    }
    
    /// Today/Yesterday session summaries for the chosen journal
    private var visibleSessionSummaries: [Summary] {
        guard categoryFilter != .all else { return sessionSummaries }
        return sessionSummaries.filter { summary in
            guard let id = summary.sessionId else { return false }
            // No saved category means Personal, the recorder's default
            return (sessionJournals[id] ?? .personal).itemFilter == categoryFilter
        }
    }
    
    private func groupSessionsByTimeBucket() -> [TimeBucket] {
        let calendar = Calendar.current
        let dateRange = getDateRange(for: selectedTimeRange)
        
        switch selectedTimeRange {
        case .today, .yesterday:
            // Show individual session summaries grouped by hour
            return groupByHour(dateRange: dateRange, calendar: calendar)
            
        case .month, .allTime:
            // The month digest and the Year Wrap are the content here. The older text rollups
            // mixed both journals together, so they aren't listed.
            return []
        }
    }
    
    private func groupByHour(dateRange: (start: Date, end: Date), calendar: Calendar) -> [TimeBucket] {
        var buckets: [TimeBucket] = []
        var summariesByHour: [Int: [Summary]] = [:]
        
        // Group existing summaries by hour
        for summary in visibleSessionSummaries {
            let hour = calendar.component(.hour, from: summary.periodStart)
            summariesByHour[hour, default: []].append(summary)
        }
        
        // Create buckets for all hours in range
        let startHour = calendar.component(.hour, from: dateRange.start)
        let endHour = calendar.component(.hour, from: dateRange.end)
        let actualEndHour = dateRange.end > dateRange.start ? endHour : 23
        
        for hour in startHour...actualEndHour {
            let hourString = hour == 0 ? "12 AM" : (hour < 12 ? "\(hour) AM" : (hour == 12 ? "12 PM" : "\(hour - 12) PM"))
            let nextHour = (hour + 1) % 24
            let nextHourString = nextHour == 0 ? "12 AM" : (nextHour < 12 ? "\(nextHour) AM" : (nextHour == 12 ? "12 PM" : "\(nextHour - 12) PM"))
            let header = "\(hourString) - \(nextHourString)"
            
            let summaries = summariesByHour[hour] ?? []
            buckets.append(TimeBucket(header: header, summaries: summaries, isEmpty: summaries.isEmpty))
        }
        
        return buckets.reversed() // Newest first (oldest at bottom)
    }
    
    // MARK: - Copy All Functionality
    
    private func copyAllSummaries() {
        let timeBuckets = groupSessionsByTimeBucket()
        var fullText = ""
        
        for bucket in timeBuckets {
            if !bucket.summaries.isEmpty {
                // Add bucket header
                fullText += "\(bucket.header)\n"
                fullText += String(repeating: "=", count: bucket.header.count) + "\n\n"
                
                // Add each summary in the bucket
                for summary in bucket.summaries {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
                    let timeString = dateFormatter.string(from: summary.periodStart)
                    
                    fullText += "• \(timeString)\n"
                    fullText += summary.text + "\n\n"
                }
                
                fullText += "\n"
            }
        }
        
        if !fullText.isEmpty {
            UIPasteboard.general.string = fullText
            coordinator.showSuccess("All summaries copied to clipboard")
        } else {
            coordinator.showError("No summaries to copy")
        }
    }
    
    private func formatMonth(year: Int, month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: year, month: month)) ?? Date()
        return formatter.string(from: date)
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

// MARK: - Year Wrap Generation Sheet

struct YearWrapGenerationSheet: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let isSmartestAIUnlocked: Bool
    let smartestAIPrice: String?
    let isPurchasing: Bool
    let onGenerate: (EngineTier) -> Void
    let onPurchaseSmartestAI: () -> Void
    let onCancel: () -> Void
    
    /// Engines that can run a wrap right now; nil while checking
    @State private var engines: [EngineTier]?
    
    private var hasExternalAPIConfigured: Bool {
        let openaiKey = KeychainHelper.load(key: "openai_api_key")
        let anthropicKey = KeychainHelper.load(key: "anthropic_api_key")
        return (openaiKey != nil && !openaiKey!.isEmpty) || (anthropicKey != nil && !anthropicKey!.isEmpty)
    }
    
    private var provider: String {
        UserDefaults.standard.string(forKey: "externalAPIProvider") ?? "OpenAI"
    }
    
    private var appleAvailable: Bool { engines?.contains(.apple) ?? false }
    private var smartestReady: Bool { isSmartestAIUnlocked && hasExternalAPIConfigured && (engines?.contains(.external) ?? false) }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(AppTheme.textPrimary)
                
                Text("Wrap your year")
                    .font(AppTheme.titleFont(size: 24))
                
                Text("One wrap for work and one for personal, side by side under All")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)
            
            VStack(spacing: 12) {
                smartestRow
                appleRow
            }
            .opacity(engines == nil ? 0.5 : 1)
            .disabled(engines == nil)
            
            Text("It runs in the background, so you can keep using the app. Progress shows on the Year screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            if !isSmartestAIUnlocked {
                Text("All sales are final. Refund requests are handled by Apple per their App Store policies.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer(minLength: 0)
            
            Button("Cancel", action: onCancel)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .padding()
        .task {
            engines = await coordinator.yearWrapEngines()
        }
    }
    
    // MARK: - Rows
    
    @ViewBuilder
    private var smartestRow: some View {
        if smartestReady {
            engineButton(
                icon: "cloud",
                title: "Smartest (\(provider))",
                detail: "Best quality. Sends your month notes, not recordings, to \(provider).",
                trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(.secondary))
            ) {
                onGenerate(.external)
            }
        } else if isSmartestAIUnlocked {
            engineButton(
                icon: "cloud",
                title: "Smartest",
                detail: "Add your API key in Settings to use it",
                trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(.secondary))
            ) {
                onCancel()
                NotificationCenter.default.post(name: NSNotification.Name("NavigateToSmartestConfig"), object: nil)
            }
        } else {
            engineButton(
                icon: "cloud",
                title: "Smartest",
                detail: "OpenAI or Anthropic. Best quality.",
                trailing: AnyView(purchaseBadge)
            ) {
                onPurchaseSmartestAI()
            }
            .disabled(isPurchasing)
        }
    }
    
    @ViewBuilder
    private var appleRow: some View {
        if appleAvailable {
            engineButton(
                icon: "apple.logo",
                title: "Apple Intelligence",
                detail: "Free and private. Runs on this iPhone.",
                trailing: AnyView(Image(systemName: "chevron.right").foregroundStyle(.secondary))
            ) {
                onGenerate(.apple)
            }
        } else if engines != nil {
            HStack(spacing: 12) {
                Image(systemName: "apple.logo")
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence")
                        .font(.headline)
                    Text("Not available on this device. It needs a supported iPhone with Apple Intelligence turned on.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.hairline, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
    }
    
    private var purchaseBadge: some View {
        Group {
            if isPurchasing {
                ProgressView()
            } else {
                Text(smartestAIPrice ?? "Unlock")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.onAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.purple)
                    .clipShape(Capsule())
            }
        }
    }
    
    private func engineButton(icon: String, title: String, detail: String, trailing: AnyView, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                trailing
            }
            .padding()
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.card).stroke(AppTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
