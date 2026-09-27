import SwiftUI
import SharedModels

struct StatisticsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var wordLimit: Double = 20
    
    // Statistics data
    @State private var sessionsByHour: [(hour: Int, count: Int, sessionIds: [UUID])] = []
    @State private var sessionsByDayOfWeek: [(dayOfWeek: Int, count: Int, sessionIds: [UUID])] = []
    @State private var longestSession: (sessionId: UUID, duration: TimeInterval, date: Date)?
    @State private var mostActiveMonth: (year: Int, month: Int, count: Int, sessionIds: [UUID])?
    @State private var topWords: [WordFrequency] = []
    @State private var isLoadingStats = false
    
    private let wordLimitKey = "insightsWordLimit"

    
    var body: some View {
        List {
            // Key Statistics Section
            if longestSession != nil || mostActiveMonth != nil {
                Section {
                    if let longest = longestSession {
                        NavigationLink {
                            FilteredSessionsView(
                                title: "Longest recording",
                                sessionIds: [longest.sessionId]
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "timer")
                                    .scaledFont(size: 20, weight: .regular)
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .frame(width: 28)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Longest recording")
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
                                    .scaledFont(size: 20, weight: .regular)
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .frame(width: 28)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Most active month")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Text(formatMonth(year: mostActive.year, month: mostActive.month))
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        Text("\(mostActive.count) recording\(mostActive.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Key statistics")
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
                                            .foregroundStyle(AppTheme.textSecondary)
                                        Text("\(data.count)")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                        Text(data.count == 1 ? "recording" : "recordings")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 70)
                                    .padding(.vertical, 8)
                                    .background(
                                        AppTheme.fill
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                } header: {
                    Text("Recordings by time of day")
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
                                            .foregroundStyle(AppTheme.textSecondary)
                                        Text("\(data.count)")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                        Text(data.count == 1 ? "recording" : "recordings")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 70)
                                    .padding(.vertical, 8)
                                    .background(
                                        AppTheme.fill
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                } header: {
                    Text("Recordings by day of week")
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
                                        .scaledFont(size: fontSizeForRank(index), weight: .bold)
                                        .foregroundStyle(colorForRank(index))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    
                                    Text("\(wordFreq.count)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(AppTheme.onAccent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(colorForRank(index))
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
                    Text("Most used words")
                } footer: {
                    Text("Meaningful words from your transcripts")
                }
            }
            
            // Settings Sections
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Word cloud limit")
                        Spacer()
                        Text("\(Int(wordLimit))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    // Apply when the slider is let go, not on every step
                    Slider(value: $wordLimit, in: 10...200, step: 10) {
                        Text("Word limit")
                    } onEditingChanged: { editing in
                        guard !editing else { return }
                        UserDefaults.standard.set(Int(wordLimit), forKey: wordLimitKey)
                        Task { await loadWords() }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Settings")
            } footer: {
                Text("Number of most-used words to display in the Statistics tab.")
            }
            
            Section {
                NavigationLink(destination: ExcludedWordsView()) {
                    SettingsRowLabel(icon: "text.badge.minus", title: "Excluded words")
                }
            } header: {
                Text("Filters")
            }
        }
        .themedScreen()
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.large)
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
    
    /// Load every section on its own, so one failing query doesn't blank the rest
    private func loadStatistics() async {
        isLoadingStats = true
        defer { isLoadingStats = false }

        longestSession = try? await coordinator.fetchLongestSession()
        mostActiveMonth = try? await coordinator.fetchMostActiveMonth()
        sessionsByHour = (try? await coordinator.fetchSessionsByHour()) ?? []
        sessionsByDayOfWeek = (try? await coordinator.fetchSessionsByDayOfWeek()) ?? []
        await loadWords()
    }

    private func loadWords() async {
        guard let transcriptTexts = try? await coordinator.fetchTranscriptText(startDate: .distantPast, endDate: Date()) else {
            topWords = []
            return
        }
        let customExcludedWords = Set(UserDefaults.standard.stringArray(forKey: "customExcludedWords") ?? [])
        topWords = WordAnalyzer.analyzeWords(
            from: transcriptTexts,
            limit: Int(wordLimit),
            customExcludedWords: customExcludedWords
        )
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        } else {
            return "\(seconds)s"
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
    
    /// "9 AM" or "09", following the phone's 12/24-hour setting
    private func formatHour(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    private func formatHourShort(_ hour: Int) -> String {
        formatHour(hour)
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
    
    /// Top words in full ink, the rest in secondary ink; both read in light and dark mode
    private func colorForRank(_ rank: Int) -> Color {
        rank < 3 ? AppTheme.textPrimary : AppTheme.textSecondary
    }
}
