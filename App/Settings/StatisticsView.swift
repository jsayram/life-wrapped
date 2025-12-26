import SwiftUI
import SharedModels

struct StatisticsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var wordLimit: Double = 20
    @State private var dateFormat: String = UserDefaults.standard.rollupDateFormat
    @State private var timeFormat: String = UserDefaults.standard.rollupTimeFormat
    
    // Statistics data
    @State private var sessionsByHour: [(hour: Int, count: Int, sessionIds: [UUID])] = []
    @State private var sessionsByDayOfWeek: [(dayOfWeek: Int, count: Int, sessionIds: [UUID])] = []
    @State private var longestSession: (sessionId: UUID, duration: TimeInterval, date: Date)?
    @State private var mostActiveMonth: (year: Int, month: Int, count: Int, sessionIds: [UUID])?
    @State private var topWords: [WordFrequency] = []
    @State private var dailySentiment: [(date: Date, sentiment: Double)] = []
    @State private var languageDistribution: [(language: String, wordCount: Int)] = []
    @State private var isLoadingStats = false
    
    private let wordLimitKey = "insightsWordLimit"
    
    private let dateFormatOptions = [
        ("MM/dd/yyyy", "12/22/2025"),
        ("dd/MM/yyyy", "22/12/2025"),
        ("yyyy-MM-dd", "2025-12-22"),
        ("MMM d, yyyy", "Dec 22, 2025"),
        ("MMMM d, yyyy", "December 22, 2025")
    ]
    
    private let timeFormatOptions = [
        ("HH:mm", "14:30 (24-hour)"),
        ("hh:mm a", "02:30 PM (12-hour)"),
        ("h:mm a", "2:30 PM (12-hour)")
    ]
    
    var body: some View {
        List {
            // Key Statistics Section
            if longestSession != nil || mostActiveMonth != nil {
                Section {
                    if let longest = longestSession {
                        NavigationLink {
                            FilteredSessionsView(
                                title: "Longest Session",
                                sessionIds: [longest.sessionId]
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "timer")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.purple)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RadialGradient(
                                            colors: [AppTheme.purple.opacity(0.15), AppTheme.purple.opacity(0.05)],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 20
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Longest Session")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Text(formatDuration(longest.duration))
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        Text(longest.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    if let mostActive = mostActiveMonth {
                        NavigationLink {
                            FilteredSessionsView(
                                title: formatMonth(year: mostActive.year, month: mostActive.month),
                                sessionIds: mostActive.sessionIds
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.magenta)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RadialGradient(
                                            colors: [AppTheme.magenta.opacity(0.15), AppTheme.magenta.opacity(0.05)],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 20
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Most Active Month")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Text(formatMonth(year: mostActive.year, month: mostActive.month))
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        Text("\(mostActive.count) session\(mostActive.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Key Statistics")
                }
            }
            
            // Sessions by Hour Section
            if !sessionsByHour.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(sessionsByHour.sorted(by: { $0.hour < $1.hour }), id: \.hour) { data in
                                NavigationLink {
                                    FilteredSessionsView(
                                        title: formatHour(data.hour),
                                        sessionIds: data.sessionIds
                                    )
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(formatHourShort(data.hour))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(AppTheme.skyBlue)
                                        Text("\(data.count)")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                        Text(data.count == 1 ? "session" : "sessions")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 70)
                                    .padding(.vertical, 8)
                                    .background(
                                        RadialGradient(
                                            colors: [AppTheme.skyBlue.opacity(0.15), AppTheme.skyBlue.opacity(0.05)],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 35
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                } header: {
                    Text("Sessions by Time of Day")
                }
            }
            
            // Sessions by Day of Week Section
            if !sessionsByDayOfWeek.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(sessionsByDayOfWeek.sorted(by: { $0.dayOfWeek < $1.dayOfWeek }), id: \.dayOfWeek) { data in
                                NavigationLink {
                                    FilteredSessionsView(
                                        title: formatDayOfWeekFull(data.dayOfWeek),
                                        sessionIds: data.sessionIds
                                    )
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(formatDayOfWeek(data.dayOfWeek))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(AppTheme.emerald)
                                        Text("\(data.count)")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                        Text(data.count == 1 ? "session" : "sessions")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 70)
                                    .padding(.vertical, 8)
                                    .background(
                                        RadialGradient(
                                            colors: [AppTheme.emerald.opacity(0.15), AppTheme.emerald.opacity(0.05)],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 35
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                } header: {
                    Text("Sessions by Day of Week")
                }
            }
            
            // Word Cloud Section
            if !topWords.isEmpty {
                Section {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(Array(topWords.enumerated()), id: \.element.id) { index, wordFreq in
                                VStack(spacing: 6) {
                                    Text(wordFreq.word.capitalized)
                                        .font(.system(size: fontSizeForRank(index), weight: .bold))
                                        .foregroundStyle(colorForRank(index))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    
                                    Text("\(wordFreq.count)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(colorForRank(index).gradient)
                                        .clipShape(Capsule())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(colorForRank(index).opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .frame(height: 400)
                } header: {
                    Text("Most Used Words")
                } footer: {
                    Text("Meaningful words from your transcripts")
                }
            }
            
            // Emotional Trends Section (Stats only, no chart)
            if !dailySentiment.isEmpty {
                Section {
                    HStack(spacing: 16) {
                        sentimentStatBox(
                            label: "Positive",
                            count: dailySentiment.filter { $0.sentiment > 0.3 }.count,
                            color: .green
                        )
                        sentimentStatBox(
                            label: "Neutral",
                            count: dailySentiment.filter { abs($0.sentiment) <= 0.3 }.count,
                            color: .gray
                        )
                        sentimentStatBox(
                            label: "Negative",
                            count: dailySentiment.filter { $0.sentiment < -0.3 }.count,
                            color: .red
                        )
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Emotional Trends")
                } footer: {
                    Text("Daily sentiment analysis from your journal entries")
                }
            }
            
            // Languages Section
            if !languageDistribution.isEmpty {
                Section {
                    let totalWords = languageDistribution.reduce(0) { $0 + $1.wordCount }
                    
                    ForEach(languageDistribution.prefix(5), id: \.language) { item in
                        let percentage = totalWords > 0 ? (Double(item.wordCount) / Double(totalWords)) * 100 : 0
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(LanguageDetector.displayName(for: item.language))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(percentage))%")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.2))
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(languageColor(index: languageDistribution.firstIndex(where: { $0.language == item.language }) ?? 0))
                                        .frame(width: geometry.size.width * (percentage / 100))
                                }
                            }
                            .frame(height: 8)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    if languageDistribution.count > 1 {
                        Text("You speak \(languageDistribution.count) language\(languageDistribution.count == 1 ? "" : "s") in your recordings")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                } header: {
                    Text("Languages Spoken")
                } footer: {
                    Text("Distribution of languages in your recordings")
                }
            }
            
            // Settings Sections
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Word Cloud Limit")
                        Spacer()
                        Text("\(Int(wordLimit))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(value: $wordLimit, in: 10...200, step: 10) {
                        Text("Word Limit")
                    }
                    .onChange(of: wordLimit) { oldValue, newValue in
                        UserDefaults.standard.set(Int(newValue), forKey: wordLimitKey)
                        coordinator.showSuccess("Word limit updated to \(Int(newValue))")
                        Task {
                            await loadStatistics()
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Settings")
            } footer: {
                Text("Number of most-used words to display in the Statistics tab.")
            }
            
            Section {
                Picker("Date Format", selection: $dateFormat) {
                    ForEach(dateFormatOptions, id: \.0) { format, example in
                        Text(example).tag(format)
                    }
                }
                .onChange(of: dateFormat) { oldValue, newValue in
                    UserDefaults.standard.rollupDateFormat = newValue
                    coordinator.showSuccess("Date format updated")
                }
                
                Picker("Time Format", selection: $timeFormat) {
                    ForEach(timeFormatOptions, id: \.0) { format, example in
                        Text(example).tag(format)
                    }
                }
                .onChange(of: timeFormat) { oldValue, newValue in
                    UserDefaults.standard.rollupTimeFormat = newValue
                    coordinator.showSuccess("Time format updated")
                }
            } header: {
                Text("Rollup Date & Time Format")
            } footer: {
                Text("Date and time format used in period rollups (hour, day, week, month, year).")
            }
            
            Section {
                NavigationLink(destination: ExcludedWordsView()) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Excluded Words")
                            Text("Manage stop words for word cloud")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "text.badge.xmark")
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Filters")
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoadingStats {
                LoadingView(size: .medium)
            }
        }
        .task {
            wordLimit = Double(UserDefaults.standard.integer(forKey: wordLimitKey))
            if wordLimit == 0 {
                wordLimit = 20
            }
            await loadStatistics()
        }
        .refreshable {
            await loadStatistics()
        }
    }
    
    private func loadStatistics() async {
        isLoadingStats = true
        do {
            // Load key statistics
            longestSession = try await coordinator.fetchLongestSession()
            mostActiveMonth = try await coordinator.fetchMostActiveMonth()
            
            // Load sessions by hour
            sessionsByHour = try await coordinator.fetchSessionsByHour()
            
            // Load sessions by day of week
            sessionsByDayOfWeek = try await coordinator.fetchSessionsByDayOfWeek()
            
            // Load word frequency analysis (all time)
            let transcriptTexts = try await coordinator.fetchTranscriptText(
                startDate: Date.distantPast,
                endDate: Date()
            )
            
            let customExcludedWords: Set<String> = {
                if let savedWords = UserDefaults.standard.stringArray(forKey: "customExcludedWords") {
                    return Set(savedWords)
                }
                return []
            }()
            
            topWords = WordAnalyzer.analyzeWords(
                from: transcriptTexts,
                limit: Int(wordLimit),
                customExcludedWords: customExcludedWords
            )
            
            // Load daily sentiment data (all time)
            dailySentiment = try await coordinator.fetchDailySentiment(from: Date.distantPast, to: Date())
            
            // Load language distribution
            languageDistribution = try await coordinator.fetchLanguageDistribution()
        } catch {
            print("❌ [StatisticsView] Failed to load statistics: \(error)")
        }
        isLoadingStats = false
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatMonth(year: Int, month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        if let date = Calendar.current.date(from: DateComponents(year: year, month: month)) {
            return formatter.string(from: date)
        }
        return "\(month)/\(year)"
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
    
    private func fontSizeForRank(_ rank: Int) -> CGFloat {
        switch rank {
        case 0...2: return 24
        case 3...5: return 20
        case 6...9: return 18
        default: return 16
        }
    }
    
    private func colorForRank(_ rank: Int) -> Color {
        switch rank {
        case 0: return AppTheme.skyBlue
        case 1: return AppTheme.purple
        case 2: return AppTheme.magenta
        case 3: return AppTheme.emerald
        case 4: return AppTheme.lightPurple
        default: return AppTheme.darkPurple
        }
    }
    
    private func sentimentStatBox(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            
            Text("days")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func languageColor(index: Int) -> Color {
        let colors: [Color] = [AppTheme.skyBlue, AppTheme.emerald, AppTheme.purple, AppTheme.magenta, AppTheme.lightPurple]
        return colors[index % colors.count]
    }
}

