import SwiftUI
import SharedModels
struct OverviewTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.colorScheme) var colorScheme
    @State private var periodSummary: Summary?
    @State private var sessionCount: Int = 0
    @State private var sessionsInPeriod: [RecordingSession] = []
    @State private var yearWrapSummary: Summary?
    @State private var isWrappingUpYear = false
    @State private var isRegeneratingPeriodSummary = false
    @State private var isLoading = true
    @State private var selectedTimeRange: TimeRange = .allTime
    @State private var showYearWrapConfirmation = false
    
    // Session summaries for Today/Yesterday feed
    @State private var sessionSummaries: [Summary] = []
    // Period rollups for Week/Month/Year feed
    @State private var periodRollups: [Summary] = []
    

    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Time Range Picker - ALWAYS show so users can switch periods
                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .tint(AppTheme.purple)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .disabled(isLoading)
                
                // Content area
                Group {
                    if isLoading {
                        LoadingView(size: .medium)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if periodSummary == nil && sessionsInPeriod.isEmpty {
                        ContentUnavailableView(
                            "No Overview Yet",
                            systemImage: "doc.text",
                            description: Text("Record more journal entries to generate summaries.")
                        )
                    } else {
                        // Copy All button
                        if !sessionSummaries.isEmpty {
                            HStack {
                                Spacer()
                                Button {
                                    copyAllSummaries()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption)
                                        Text("Copy \(sessionSummaries.count)")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundStyle(AppTheme.purple)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                RadialGradient(
                                                    colors: [AppTheme.purple.opacity(0.15), AppTheme.purple.opacity(0.05)],
                                                    center: .center,
                                                    startRadius: 0,
                                                    endRadius: 40
                                                )
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [AppTheme.purple.opacity(0.4), AppTheme.magenta.opacity(0.3)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                ),
                                                lineWidth: 1.5
                                            )
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        }
                        
                        // New Feed Layout
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                // Local period summary card for Today/Week/Month
                                if [.today, .week, .month].contains(selectedTimeRange) {
                                    if let periodSummary {
                                        PeriodSummaryCard(
                                            title: periodSummaryTitle(for: selectedTimeRange),
                                            subtitle: "Local AI rollup (on-device)",
                                            summary: periodSummary,
                                            isRegenerating: isRegeneratingPeriodSummary,
                                            onCopy: {
                                                UIPasteboard.general.string = periodSummary.text
                                                coordinator.showSuccess("Summary copied")
                                            },
                                            onRegenerate: {
                                                Task {
                                                    await regenerateAndReloadPeriodSummary()
                                                }
                                            }
                                        )
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                    } else if !sessionsInPeriod.isEmpty {
                                        GeneratePeriodSummaryCard(
                                            title: periodSummaryTitle(for: selectedTimeRange),
                                            isGenerating: isRegeneratingPeriodSummary,
                                            onGenerate: {
                                                Task {
                                                    await regenerateAndReloadPeriodSummary()
                                                }
                                            }
                                        )
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                    }
                                }
                                
                                // Year Wrapped Summary (only show for Year timerange)
                                if selectedTimeRange == .allTime {
                                    if let yearWrap = yearWrapSummary {
                                        YearWrappedCard(
                                            summary: yearWrap,
                                            coordinator: coordinator,
                                            onRegenerate: {
                                                showYearWrapConfirmation = true
                                            },
                                            isRegenerating: isWrappingUpYear
                                        )
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                    } else if !sessionsInPeriod.isEmpty {
                                        // Show generate button if no Year Wrap exists
                                        GenerateYearWrapCard(
                                            onGenerate: {
                                                showYearWrapConfirmation = true
                                            },
                                            isGenerating: isWrappingUpYear
                                        )
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                    }
                                }
                            }
                            
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                let timeBuckets = groupSessionsByTimeBucket()
                                
                                if timeBuckets.isEmpty {
                                    // No session summaries found
                                    ContentUnavailableView(
                                        "No Summaries Yet",
                                        systemImage: "doc.text",
                                        description: Text("Session summaries will appear here once recordings are summarized.")
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
                                                    SessionSummaryCard(summary: summary, coordinator: coordinator)
                                                        .padding(.horizontal, 16)
                                                        .padding(.vertical, 6)
                                                }
                                            }
                                        } header: {
                                            // Time bucket header
                                            HStack {
                                                Text(bucket.header)
                                                    .font(.headline)
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(bucket.isEmpty ? .secondary : .primary)
                                                
                                                Spacer()
                                                
                                                if !bucket.isEmpty {
                                                    Text("\(bucket.summaries.count)")
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundStyle(.secondary)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(
                                                            Capsule()
                                                                .fill(Color(.tertiarySystemFill))
                                                        )
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(Color(.systemGroupedBackground))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Overview")
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
            .onChange(of: selectedTimeRange) { oldValue, newValue in
                Task {
                    await loadInsights()
                }
            }
            .alert("Generate Year Wrap", isPresented: $showYearWrapConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button(actionButtonTitle()) {
                    handleYearWrapAction()
                }
            } message: {
                Text(yearWrapMessage())
            }
        }
    }
    
    private func hasExternalAPIConfigured() -> Bool {
        let openaiKey = KeychainHelper.load(key: "openai_api_key")
        let anthropicKey = KeychainHelper.load(key: "anthropic_api_key")
        return (openaiKey != nil && !openaiKey!.isEmpty) || (anthropicKey != nil && !anthropicKey!.isEmpty)
    }
    
    private func yearWrapMessage() -> String {
        if hasExternalAPIConfigured() {
            return "This will use ChatGPT or Claude to analyze your entire year of recordings and create a comprehensive year-in-review summary.\n\nThis process may take 30-60 seconds."
        } else {
            return "To generate a Year Wrap, you need to configure your ChatGPT (OpenAI) or Claude (Anthropic) API key in Settings.\n\nTap 'Open Settings' to add your API credentials."
        }
    }
    
    private func actionButtonTitle() -> String {
        return hasExternalAPIConfigured() ? "Generate" : "Open Settings"
    }
    
    private func handleYearWrapAction() {
        if hasExternalAPIConfigured() {
            Task {
                await wrapUpYear(forceRegenerate: false)
            }
        } else {
            // Post notification to switch to Settings tab
            NotificationCenter.default.post(name: NSNotification.Name("SwitchToSettingsTab"), object: nil)
        }
    }
    
    private func loadInsights() async {
        isLoading = true
        do {
            // Get date range for filtering
            let dateRange = getDateRange(for: selectedTimeRange)
            
            // Load period summary based on selected time range
            let periodType: PeriodType = {
                switch selectedTimeRange {
                case .yesterday: return .day
                case .today: return .day
                case .week: return .week
                case .month: return .month
                case .allTime: return .year // Show yearly summary for current year
                }
            }()
            
            // Clear previous data to avoid stale counts when DB is unavailable
            sessionsInPeriod = []
            sessionCount = 0
            sessionSummaries = []
            periodRollups = []
            
            // Load sessions in this period first
            if let dbManager = coordinator.getDatabaseManager() {
                if selectedTimeRange == .today || selectedTimeRange == .yesterday {
                    sessionsInPeriod = (try? await dbManager.fetchSessionsByDate(date: dateRange.start)) ?? []
                } else {
                    // For week/month/all, fetch ALL sessions and filter by date range
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
                    sessionSummaries = (try? await dbManager.fetchSessionSummariesInDateRange(
                        from: dateRange.start,
                        to: dateRange.end
                    )) ?? []
                    print("✅ [OverviewTab] Loaded \(sessionSummaries.count) session summaries")
                    
                case .week:
                    // Load weekly rollup summaries (one card per week)
                    periodRollups = (try? await dbManager.fetchWeeklySummaries(
                        from: dateRange.start,
                        to: dateRange.end
                    )) ?? []
                    print("✅ [OverviewTab] Loaded \(periodRollups.count) weekly rollups")
                    
                case .month:
                    // Load monthly rollup summaries (one card per month)
                    periodRollups = (try? await dbManager.fetchMonthlySummaries(
                        from: dateRange.start,
                        to: dateRange.end
                    )) ?? []
                    print("✅ [OverviewTab] Loaded \(periodRollups.count) monthly rollups")
                    
                case .allTime:
                    // Load yearly rollup summary (single card for whole year)
                    let allYearlySummaries = (try? await dbManager.fetchSummaries(periodType: .year)) ?? []
                    periodRollups = allYearlySummaries.filter { summary in
                        summary.periodStart >= dateRange.start && summary.periodStart < dateRange.end
                    }
                    print("✅ [OverviewTab] Loaded \(periodRollups.count) yearly rollup")
                }
            }
            
            // Try to fetch existing period summary (don't auto-generate on view load)
            // For week/month/year, use Date() to get current period, for day use startDate
            let dateForFetch = (periodType == .day) ? dateRange.start : Date()
            periodSummary = try? await coordinator.fetchPeriodSummary(type: periodType, date: dateForFetch)

            if selectedTimeRange == .allTime {
                yearWrapSummary = try? await coordinator.fetchPeriodSummary(type: .yearWrap, date: dateForFetch)
            } else {
                yearWrapSummary = nil
            }
            
            // Debug logging
            if periodSummary == nil && !sessionsInPeriod.isEmpty {
                print("ℹ️ [OverviewTab] No \(periodType.rawValue) summary found for \(dateForFetch.formatted()), use Regenerate to create one")
                print("   Searched for: type=\(periodType.rawValue), date=\(dateForFetch.ISO8601Format())")
                print("   Sessions in period: \(sessionsInPeriod.count)")
            } else if periodSummary != nil {
                print("✅ [OverviewTab] Found \(periodType.rawValue) summary for \(dateForFetch.formatted())")
            }
        } catch {
            print("❌ [OverviewTab] Failed to load insights: \(error)")
        }
        isLoading = false
    }
    
    private func regenerateAndReloadPeriodSummary() async {
        guard !isRegeneratingPeriodSummary else { return }
        isRegeneratingPeriodSummary = true
        defer { isRegeneratingPeriodSummary = false }
        await regeneratePeriodSummary()
        await loadInsights()
    }

    private func regeneratePeriodSummary() async {
        let (startDate, _) = getDateRange(for: selectedTimeRange)
        
        let periodType: PeriodType = {
            switch selectedTimeRange {
            case .yesterday: return .day
            case .today: return .day
            case .week: return .week
            case .month: return .month
            case .allTime: return .year
            }
        }()
        
        // Use Date() (today) for week/month/year calculations, startDate for day
        let dateForGeneration = (periodType == .day) ? startDate : Date()
        
        print("🔄 [OverviewTab] Regenerating \(periodType.rawValue) summary...")
        
        switch periodType {
        case .day:
            await coordinator.updateDailySummary(date: dateForGeneration, forceRegenerate: false)
        case .week:
            await coordinator.updateWeeklySummary(date: dateForGeneration, forceRegenerate: false)
        case .month:
            await coordinator.updateMonthlySummary(date: dateForGeneration, forceRegenerate: false)
        case .year:
            await coordinator.updateYearlySummary(date: dateForGeneration, forceRegenerate: false)
        default:
            break
        }
        
        // Fetch again after regeneration
        try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5s
        periodSummary = try? await coordinator.fetchPeriodSummary(type: periodType, date: dateForGeneration)
        
        if periodSummary != nil {
            coordinator.showSuccess("Summary regenerated")
        } else {
            coordinator.showError("Failed to regenerate summary")
        }
    }

    private func wrapUpYear(forceRegenerate: Bool) async {
        guard !isWrappingUpYear else { return }
        isWrappingUpYear = true
        let dateForGeneration = Date()

        await coordinator.wrapUpYear(date: dateForGeneration, forceRegenerate: forceRegenerate)

        yearWrapSummary = try? await coordinator.fetchPeriodSummary(type: .yearWrap, date: dateForGeneration)
        isWrappingUpYear = false
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
        case .week:
            // Current week: Monday to Sunday (or today if mid-week)
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            components.weekday = 2 // Monday
            let startOfWeek = calendar.date(from: components) ?? now
            return (startOfWeek, now)
        case .month:
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return (start, now)
        case .allTime:
            // Show only current year (e.g., 2025) up to today
            let currentYear = calendar.component(.year, from: now)
            let startOfYear = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1)) ?? now
            return (startOfYear, now)
        }
    }

    private func periodSummaryTitle(for range: TimeRange) -> String {
        switch range {
        case .today: return "Today's Recordings"
        case .week: return "This Week's Recordings"
        case .month: return "This Month's Recordings"
        default: return "Recordings"
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
    
    private func groupSessionsByTimeBucket() -> [TimeBucket] {
        let calendar = Calendar.current
        let dateRange = getDateRange(for: selectedTimeRange)
        
        switch selectedTimeRange {
        case .today, .yesterday:
            // Show individual session summaries grouped by hour
            return groupByHour(dateRange: dateRange, calendar: calendar)
            
        case .week:
            // Show weekly rollup summaries (one card per week)
            return groupByWeekRollup(dateRange: dateRange, calendar: calendar, rollups: periodRollups)
            
        case .month:
            // Show monthly rollup summaries (one card per month)
            return groupByMonthRollup(dateRange: dateRange, calendar: calendar, rollups: periodRollups)
            
        case .allTime:
            // Show yearly rollup summary (single card for whole year)
            return groupByYearRollup(dateRange: dateRange, calendar: calendar, rollups: periodRollups)
        }
    }
    
    private func groupByHour(dateRange: (start: Date, end: Date), calendar: Calendar) -> [TimeBucket] {
        var buckets: [TimeBucket] = []
        var summariesByHour: [Int: [Summary]] = [:]
        
        // Group existing summaries by hour
        for summary in sessionSummaries {
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
    
    private func groupByDayRollup(dateRange: (start: Date, end: Date), calendar: Calendar, rollups: [Summary]) -> [TimeBucket] {
        var buckets: [TimeBucket] = []
        
        var summariesByDay: [Date: [Summary]] = [:]
        for summary in rollups {
            let dayStart = calendar.startOfDay(for: summary.periodStart)
            summariesByDay[dayStart, default: []].append(summary)
        }
        
        // Create buckets for all days in range
        var currentDate = calendar.startOfDay(for: dateRange.start)
        let endDate = calendar.startOfDay(for: dateRange.end)
        
        while currentDate <= endDate {
            let formatter = DateFormatter()
            if calendar.isDateInToday(currentDate) {
                formatter.dateFormat = "'Today' - EEEE, MMM d"
            } else if calendar.isDateInYesterday(currentDate) {
                formatter.dateFormat = "'Yesterday' - EEEE, MMM d"
            } else {
                formatter.dateFormat = "EEEE, MMM d"
            }
            let header = formatter.string(from: currentDate)
            
            let summaries = summariesByDay[currentDate] ?? []
            buckets.append(TimeBucket(header: header, summaries: summaries, isEmpty: summaries.isEmpty))
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return buckets.reversed() // Most recent first
    }
    
    private func groupByWeekRollup(dateRange: (start: Date, end: Date), calendar: Calendar, rollups: [Summary]) -> [TimeBucket] {
        var buckets: [TimeBucket] = []
        
        var summariesByWeek: [Date: [Summary]] = [:]
        for summary in rollups {
            let weekStart = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: summary.periodStart)
            if let weekStartDate = calendar.date(from: weekStart) {
                summariesByWeek[weekStartDate, default: []].append(summary)
            }
        }
        
        // Create buckets for all weeks in range
        var currentWeekStart = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: dateRange.start)
        let endWeekStart = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: dateRange.end)
        
        guard var currentWeekDate = calendar.date(from: currentWeekStart),
              let endWeekDate = calendar.date(from: endWeekStart) else {
            return buckets
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        
        while currentWeekDate <= endWeekDate {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: currentWeekDate) ?? currentWeekDate
            // Format: "Monday, Dec 16 - Sunday, Dec 22"
            let header = "Monday, \(dateFormatter.string(from: currentWeekDate)) - Sunday, \(dateFormatter.string(from: weekEnd))"
            
            let summaries = summariesByWeek[currentWeekDate] ?? []
            buckets.append(TimeBucket(header: header, summaries: summaries, isEmpty: summaries.isEmpty))
            
            currentWeekDate = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekDate) ?? currentWeekDate
        }
        
        return buckets.reversed() // Most recent first
    }
    
    private func groupByMonthRollup(dateRange: (start: Date, end: Date), calendar: Calendar, rollups: [Summary]) -> [TimeBucket] {
        var buckets: [TimeBucket] = []
        
        var summariesByMonth: [Date: [Summary]] = [:]
        for summary in rollups {
            let monthStart = calendar.dateComponents([.year, .month], from: summary.periodStart)
            if let monthStartDate = calendar.date(from: monthStart) {
                summariesByMonth[monthStartDate, default: []].append(summary)
            }
        }
        
        // Create buckets for all months in range
        var currentMonthStart = calendar.dateComponents([.year, .month], from: dateRange.start)
        let endMonthStart = calendar.dateComponents([.year, .month], from: dateRange.end)
        
        guard var currentMonthDate = calendar.date(from: currentMonthStart),
              let endMonthDate = calendar.date(from: endMonthStart) else {
            return buckets
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"
        
        while currentMonthDate <= endMonthDate {
            let header = dateFormatter.string(from: currentMonthDate)
            
            let summaries = summariesByMonth[currentMonthDate] ?? []
            buckets.append(TimeBucket(header: header, summaries: summaries, isEmpty: summaries.isEmpty))
            
            currentMonthDate = calendar.date(byAdding: .month, value: 1, to: currentMonthDate) ?? currentMonthDate
        }
        
        return buckets.reversed() // Most recent first
    }
    
    private func groupByYearRollup(dateRange: (start: Date, end: Date), calendar: Calendar, rollups: [Summary]) -> [TimeBucket] {
        var buckets: [TimeBucket] = []
        
        var summariesByYear: [Int: [Summary]] = [:]
        for summary in rollups {
            let year = calendar.component(.year, from: summary.periodStart)
            summariesByYear[year, default: []].append(summary)
        }
        
        // Create buckets for all years in range
        let startYear = calendar.component(.year, from: dateRange.start)
        let endYear = calendar.component(.year, from: dateRange.end)
        
        for year in startYear...endYear {
            let header = "\(year)"
            let summaries = summariesByYear[year] ?? []
            buckets.append(TimeBucket(header: header, summaries: summaries, isEmpty: summaries.isEmpty))
        }
        
        return buckets.reversed() // Most recent first
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
