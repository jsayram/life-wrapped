// =============================================================================
// LifeWrapped Widget Extension
// =============================================================================

import WidgetKit
import SwiftUI
import AppIntents
import WidgetCore

// MARK: - Deep Link URLs

enum WidgetDeepLink {
    static let home = URL(string: "lifewrapped://home")!
    static let history = URL(string: "lifewrapped://history")!
    static let overview = URL(string: "lifewrapped://overview")!
    static let settings = URL(string: "lifewrapped://settings")!
    static let record = URL(string: "lifewrapped://record")!
}

// MARK: - Widget Entry

struct LifeWrappedEntry: TimelineEntry {
    let date: Date
    let widgetData: WidgetData
    let configuration: WidgetDisplayModeIntent
    
    var streakDays: Int { widgetData.streakDays }
    var todayWords: Int { widgetData.todayWords }
    var todayMinutes: Int { widgetData.todayMinutes }
    var lastEntryTime: Date? { widgetData.lastEntryTime }
    var isStreakAtRisk: Bool { widgetData.isStreakAtRisk }
    
    static let placeholder = LifeWrappedEntry(
        date: Date(),
        widgetData: .placeholder,
        configuration: .overview
    )
    
    static let empty = LifeWrappedEntry(
        date: Date(),
        widgetData: .empty,
        configuration: .overview
    )
}

// MARK: - Widget Display Mode Intent

enum WidgetDisplayModeIntent: String, CaseIterable, AppEnum {
    case overview = "Overview"
    case streak = "Streak Focus"
    case weekly = "Weekly Stats"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Display Mode"
    }
    
    static var caseDisplayRepresentations: [WidgetDisplayModeIntent: DisplayRepresentation] {
        [
            .overview: "Overview",
            .streak: "Streak Focus",
            .weekly: "Weekly Stats"
        ]
    }
}

// MARK: - Widget Configuration Intent

struct LifeWrappedWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Configure Widget"
    static let description: IntentDescription = "Choose what to display in your widget."
    
    @Parameter(title: "Display Mode", default: .overview)
    var displayMode: WidgetDisplayModeIntent
}

// MARK: - Timeline Provider

struct LifeWrappedProvider: AppIntentTimelineProvider {
    typealias Entry = LifeWrappedEntry
    typealias Intent = LifeWrappedWidgetIntent
    
    private let dataManager = WidgetDataManager.shared
    
    func placeholder(in context: Context) -> LifeWrappedEntry {
        .placeholder
    }
    
    func snapshot(for configuration: LifeWrappedWidgetIntent, in context: Context) async -> LifeWrappedEntry {
        // Return placeholder for preview
        if context.isPreview {
            return .placeholder
        }
        
        // Return actual data
        return loadCurrentEntry(configuration: configuration.displayMode)
    }
    
    func timeline(for configuration: LifeWrappedWidgetIntent, in context: Context) async -> Timeline<LifeWrappedEntry> {
        let entry = loadCurrentEntry(configuration: configuration.displayMode)
        
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
    
    private func loadCurrentEntry(configuration: WidgetDisplayModeIntent) -> LifeWrappedEntry {
        let widgetData = dataManager.readWidgetData()
        
        return LifeWrappedEntry(
            date: Date(),
            widgetData: widgetData,
            configuration: configuration
        )
    }
}

// MARK: - Widget Views

struct LifeWrappedWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: LifeWrappedEntry
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        case .accessoryInline:
            AccessoryInlineView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Streak
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(entry.streakDays > 0 ? .orange : .gray)
                Text("\(entry.streakDays)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("day streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Today's words
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.todayWords)")
                    .font(.title)
                    .fontWeight(.bold)
                Text("words today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Today's minutes
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(entry.todayMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WidgetDeepLink.home)
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Left side - Streak
            VStack(alignment: .center, spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.largeTitle)
                    .foregroundStyle(entry.streakDays > 0 ? .orange : .gray)
                
                Text("\(entry.streakDays)")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("day streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if entry.isStreakAtRisk {
                    Text("Journal today!")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            // Right side - Stats
            VStack(alignment: .leading, spacing: 8) {
                StatRow(icon: "text.word.spacing", value: "\(entry.todayWords)", label: "words")
                StatRow(icon: "clock", value: "\(entry.todayMinutes)", label: "minutes")
                StatRow(icon: "doc.text", value: "\(entry.widgetData.todayEntries)", label: "entries")
            }
            .frame(maxWidth: .infinity)
            
            // Record button area
            Link(destination: WidgetDeepLink.record) {
                VStack(spacing: 4) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.red)
                    Text("Record")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 50)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WidgetDeepLink.home)
    }
}

struct StatRow: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Large Widget

struct LargeWidgetView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with Record Button
            HStack {
                VStack(alignment: .leading) {
                    Text("Life Wrapped")
                        .font(.headline)
                    Text("Today's Journal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Record button
                Link(destination: WidgetDeepLink.record) {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.circle.fill")
                            .foregroundStyle(.red)
                        Text("Record")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.red.opacity(0.15))
                    .clipShape(Capsule())
                }
                
                // Streak badge
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(entry.streakDays)")
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.2))
                .clipShape(Capsule())
            }
            
            Divider()
            
            // Stats grid with links
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                Link(destination: WidgetDeepLink.history) {
                    StatCard(icon: "text.word.spacing", value: "\(entry.todayWords)", label: "Words", color: .blue)
                }
                Link(destination: WidgetDeepLink.history) {
                    StatCard(icon: "clock", value: "\(entry.todayMinutes)m", label: "Speaking", color: .green)
                }
                Link(destination: WidgetDeepLink.history) {
                    StatCard(icon: "doc.text", value: "\(entry.widgetData.todayEntries)", label: "Entries", color: .purple)
                }
                Link(destination: WidgetDeepLink.history) {
                    StatCard(icon: "calendar", value: lastEntryText, label: "Last Entry", color: .orange)
                }
            }
            
            Spacer()
            
            // Weekly summary bar
            HStack {
                Label("\(entry.widgetData.weeklyWords) words this week", systemImage: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("\(entry.widgetData.weeklyMinutes) min", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WidgetDeepLink.home)
    }
    
    private var lastEntryText: String {
        guard let lastEntry = entry.lastEntryTime else { return "Never" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastEntry, relativeTo: Date())
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Lock Screen Widgets

struct AccessoryCircularView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            
            VStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                Text("\(entry.streakDays)")
                    .font(.headline)
                    .fontWeight(.bold)
            }
        }
        .widgetURL(WidgetDeepLink.home)
    }
}

struct AccessoryRectangularView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.title3)
            
            VStack(alignment: .leading) {
                Text("\(entry.streakDays) day streak")
                    .font(.headline)
                Text("\(entry.todayWords) words today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .widgetURL(WidgetDeepLink.home)
    }
}

struct AccessoryInlineView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        Text("🔥 \(entry.streakDays) day streak")
            .widgetURL(WidgetDeepLink.home)
    }
}

// MARK: - Widget Configuration

struct LifeWrappedWidget: Widget {
    let kind: String = "LifeWrappedWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: LifeWrappedWidgetIntent.self, provider: LifeWrappedProvider()) { entry in
            LifeWrappedWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Life Wrapped")
        .description("Track your journaling streak and daily progress.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Streak Focus Widget

struct StreakFocusWidget: Widget {
    let kind: String = "LifeWrappedStreakWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: LifeWrappedWidgetIntent.self, provider: LifeWrappedProvider()) { entry in
            StreakFocusWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak Focus")
        .description("Keep your journaling streak alive!")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

struct StreakFocusWidgetView: View {
    let entry: LifeWrappedEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            StreakSmallView(entry: entry)
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        default:
            StreakSmallView(entry: entry)
        }
    }
}

struct StreakSmallView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        VStack(spacing: 8) {
            // Flame with animation hint
            Image(systemName: entry.streakDays > 0 ? "flame.fill" : "flame")
                .font(.system(size: 48))
                .foregroundStyle(flameGradient)
            
            // Streak count
            Text("\(entry.streakDays)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            
            Text(entry.streakDays == 1 ? "day" : "days")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Status message
            if entry.isStreakAtRisk {
                Text("Journal today!")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fontWeight(.medium)
            } else if entry.streakDays > 0 {
                Text("Keep going! 🎯")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WidgetDeepLink.home)
    }
    
    private var flameGradient: LinearGradient {
        LinearGradient(
            colors: entry.streakDays > 0 
                ? [.orange, .red] 
                : [.gray, .gray.opacity(0.5)],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

// MARK: - Weekly Stats Widget

struct WeeklyStatsWidget: Widget {
    let kind: String = "LifeWrappedWeeklyWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: LifeWrappedWidgetIntent.self, provider: LifeWrappedProvider()) { entry in
            WeeklyStatsWidgetView(entry: entry)
        }
        .configurationDisplayName("Weekly Stats")
        .description("View your weekly journaling summary.")
        .supportedFamilies([
            .systemMedium,
            .systemLarge
        ])
    }
}

struct WeeklyStatsWidgetView: View {
    let entry: LifeWrappedEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemMedium:
            WeeklyMediumView(entry: entry)
        case .systemLarge:
            WeeklyLargeView(entry: entry)
        default:
            WeeklyMediumView(entry: entry)
        }
    }
}

struct WeeklyMediumView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Weekly summary
            VStack(alignment: .leading, spacing: 8) {
                Text("This Week")
                    .font(.headline)
                
                HStack(spacing: 4) {
                    Image(systemName: "text.word.spacing")
                        .foregroundStyle(.blue)
                    Text("\(entry.widgetData.weeklyWords)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("words")
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .foregroundStyle(.green)
                    Text("\(entry.widgetData.weeklyMinutes)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("minutes")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Streak
            VStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                
                Text("\(entry.streakDays)")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("day streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            // Record button
            Link(destination: WidgetDeepLink.record) {
                VStack(spacing: 4) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                    Text("Record")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WidgetDeepLink.overview)
    }
}

struct WeeklyLargeView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with record button
            HStack {
                Text("Weekly Summary")
                    .font(.headline)
                Spacer()
                
                // Record button
                Link(destination: WidgetDeepLink.record) {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.circle.fill")
                            .foregroundStyle(.red)
                        Text("Record")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.red.opacity(0.15))
                    .clipShape(Capsule())
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(entry.streakDays) days")
                        .fontWeight(.semibold)
                }
            }
            
            Divider()
            
            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                Link(destination: WidgetDeepLink.history) {
                    WeeklyStatCard(
                        icon: "text.word.spacing",
                        title: "Words",
                        thisWeek: entry.widgetData.weeklyWords,
                        today: entry.todayWords,
                        color: .blue
                    )
                }
                
                Link(destination: WidgetDeepLink.history) {
                    WeeklyStatCard(
                        icon: "clock",
                        title: "Minutes",
                        thisWeek: entry.widgetData.weeklyMinutes,
                        today: entry.todayMinutes,
                        color: .green
                    )
                }
            }
            
            Spacer()
            
            // Today's entries summary
            HStack {
                Label("\(entry.widgetData.todayEntries) entries today", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if entry.isStreakAtRisk {
                    Text("Journal today to keep your streak!")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WidgetDeepLink.overview)
    }
}

struct WeeklyStatCard: View {
    let icon: String
    let title: String
    let thisWeek: Int
    let today: Int
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text("\(thisWeek)")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Today: \(today)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Quick Record Widget

struct QuickRecordWidget: Widget {
    let kind: String = "LifeWrappedQuickRecordWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickRecordProvider()) { entry in
            QuickRecordWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Record")
        .description("Quickly start recording your journal.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular
        ])
    }
}

struct QuickRecordEntry: TimelineEntry {
    let date: Date
    let streakDays: Int
    let todayWords: Int
    let isStreakAtRisk: Bool
    
    static let placeholder = QuickRecordEntry(
        date: Date(),
        streakDays: 7,
        todayWords: 250,
        isStreakAtRisk: false
    )
}

struct QuickRecordProvider: TimelineProvider {
    typealias Entry = QuickRecordEntry
    
    private let dataManager = WidgetDataManager.shared
    
    func placeholder(in context: Context) -> QuickRecordEntry {
        .placeholder
    }
    
    func getSnapshot(in context: Context, completion: @escaping (QuickRecordEntry) -> Void) {
        let widgetData = dataManager.readWidgetData()
        let entry = QuickRecordEntry(
            date: Date(),
            streakDays: widgetData.streakDays,
            todayWords: widgetData.todayWords,
            isStreakAtRisk: widgetData.isStreakAtRisk
        )
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickRecordEntry>) -> Void) {
        let widgetData = dataManager.readWidgetData()
        let entry = QuickRecordEntry(
            date: Date(),
            streakDays: widgetData.streakDays,
            todayWords: widgetData.todayWords,
            isStreakAtRisk: widgetData.isStreakAtRisk
        )
        
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct QuickRecordWidgetView: View {
    let entry: QuickRecordEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            QuickRecordSmallView(entry: entry)
        case .accessoryCircular:
            QuickRecordCircularView(entry: entry)
        default:
            QuickRecordSmallView(entry: entry)
        }
    }
}

struct QuickRecordSmallView: View {
    let entry: QuickRecordEntry
    
    var body: some View {
        VStack(spacing: 12) {
            // Record button as main focus
            Link(destination: WidgetDeepLink.record) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.red, .red.opacity(0.7)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 40
                            )
                        )
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
            }
            
            Text("Tap to Record")
                .font(.caption)
                .fontWeight(.medium)
            
            // Today's stats
            HStack(spacing: 12) {
                Label("\(entry.todayWords)", systemImage: "text.word.spacing")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                if entry.streakDays > 0 {
                    Label("\(entry.streakDays)", systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            
            // Streak warning
            if entry.isStreakAtRisk {
                Text("Save your streak!")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fontWeight(.medium)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct QuickRecordCircularView: View {
    let entry: QuickRecordEntry
    
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            
            VStack(spacing: 2) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                Text("REC")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
        }
        .widgetURL(WidgetDeepLink.record)
    }
}

// MARK: - Widget Bundle

@main
struct LifeWrappedWidgetBundle: WidgetBundle {
    var body: some Widget {
        LifeWrappedWidget()
        StreakFocusWidget()
        WeeklyStatsWidget()
        QuickRecordWidget()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    LifeWrappedWidget()
} timeline: {
    LifeWrappedEntry.placeholder
    LifeWrappedEntry.empty
}

#Preview("Medium", as: .systemMedium) {
    LifeWrappedWidget()
} timeline: {
    LifeWrappedEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    LifeWrappedWidget()
} timeline: {
    LifeWrappedEntry.placeholder
}

#Preview("Streak Small", as: .systemSmall) {
    StreakFocusWidget()
} timeline: {
    LifeWrappedEntry.placeholder
}

#Preview("Weekly Large", as: .systemLarge) {
    WeeklyStatsWidget()
} timeline: {
    LifeWrappedEntry.placeholder
}

#Preview("Quick Record Small", as: .systemSmall) {
    QuickRecordWidget()
} timeline: {
    QuickRecordEntry.placeholder
}

#Preview("Quick Record Circular", as: .accessoryCircular) {
    QuickRecordWidget()
} timeline: {
    QuickRecordEntry.placeholder
}
