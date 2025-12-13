// =============================================================================
// LifeWrapped Widget Extension
// =============================================================================

import WidgetKit
import SwiftUI
import AppIntents
import WidgetCore

// MARK: - Widget Entry

struct LifeWrappedEntry: TimelineEntry {
    let date: Date
    let widgetData: WidgetData
    let configuration: WidgetDisplayModeIntent
    
    var streakDays: Int { widgetData.streakDays }
    var todayWords: Int { widgetData.todayWords }
    var todayMinutes: Int { widgetData.todayMinutes }
    var goalProgress: Double { widgetData.goalProgress }
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
    case goals = "Goals"
    case weekly = "Weekly Stats"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Display Mode"
    }
    
    static var caseDisplayRepresentations: [WidgetDisplayModeIntent: DisplayRepresentation] {
        [
            .overview: "Overview",
            .streak: "Streak Focus",
            .goals: "Goals",
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
            }
            
            // Today's words
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.todayWords)")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("words today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.3))
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(.blue)
                        .frame(width: geometry.size.width * entry.goalProgress, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
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
                
                // Progress
                HStack {
                    Text("Goal:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ProgressView(value: entry.goalProgress)
                        .tint(.blue)
                    
                    Text("\(Int(entry.goalProgress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
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
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Life Wrapped")
                        .font(.headline)
                    Text("Today's Journal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
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
            
            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatCard(icon: "text.word.spacing", value: "\(entry.todayWords)", label: "Words", color: .blue)
                StatCard(icon: "clock", value: "\(entry.todayMinutes)m", label: "Speaking", color: .green)
                StatCard(icon: "target", value: "\(Int(entry.goalProgress * 100))%", label: "Goal", color: .purple)
                StatCard(icon: "calendar", value: lastEntryText, label: "Last Entry", color: .orange)
            }
            
            Spacer()
            
            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Goal Progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.secondary.opacity(0.3))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(progressColor)
                            .frame(width: geometry.size.width * entry.goalProgress, height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    private var lastEntryText: String {
        guard let lastEntry = entry.lastEntryTime else { return "Never" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastEntry, relativeTo: Date())
    }
    
    private var progressColor: Color {
        switch entry.goalProgress {
        case 0..<0.25: return .red
        case 0.25..<0.5: return .orange
        case 0.5..<0.75: return .yellow
        case 0.75..<1.0: return .green
        default: return .blue
        }
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
    }
}

struct AccessoryInlineView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        Text("🔥 \(entry.streakDays) day streak")
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

// MARK: - Goals Widget

struct GoalsWidget: Widget {
    let kind: String = "LifeWrappedGoalsWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: LifeWrappedWidgetIntent.self, provider: LifeWrappedProvider()) { entry in
            GoalsWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Goals")
        .description("Track your daily journaling goals.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium
        ])
    }
}

struct GoalsWidgetView: View {
    let entry: LifeWrappedEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            GoalsSmallView(entry: entry)
        case .systemMedium:
            GoalsMediumView(entry: entry)
        default:
            GoalsSmallView(entry: entry)
        }
    }
}

struct GoalsSmallView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        VStack(spacing: 12) {
            // Goal ring
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.3), lineWidth: 8)
                
                Circle()
                    .trim(from: 0, to: entry.goalProgress)
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(Int(entry.goalProgress * 100))%")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("goal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)
            
            Text("\(entry.todayWords) words")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    private var progressColor: Color {
        switch entry.goalProgress {
        case 0..<0.25: return .red
        case 0.25..<0.5: return .orange
        case 0.5..<0.75: return .yellow
        case 0.75..<1.0: return .green
        default: return .blue
        }
    }
}

struct GoalsMediumView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        HStack(spacing: 20) {
            // Goal ring
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.3), lineWidth: 10)
                
                Circle()
                    .trim(from: 0, to: entry.goalProgress)
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(Int(entry.goalProgress * 100))%")
                        .font(.title)
                        .fontWeight(.bold)
                }
            }
            .frame(width: 100, height: 100)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's Progress")
                    .font(.headline)
                
                GoalProgressRow(icon: "text.word.spacing", label: "Words", value: entry.todayWords, color: .blue)
                GoalProgressRow(icon: "clock", label: "Minutes", value: entry.todayMinutes, color: .green)
                GoalProgressRow(icon: "doc.text", label: "Entries", value: entry.widgetData.todayEntries, color: .purple)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    private var progressColor: Color {
        switch entry.goalProgress {
        case 0..<0.25: return .red
        case 0.25..<0.5: return .orange
        case 0.5..<0.75: return .yellow
        case 0.75..<1.0: return .green
        default: return .blue
        }
    }
}

struct GoalProgressRow: View {
    let icon: String
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)
            
            Text("\(value)")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct WeeklyLargeView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Weekly Summary")
                    .font(.headline)
                Spacer()
                
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
                WeeklyStatCard(
                    icon: "text.word.spacing",
                    title: "Words",
                    thisWeek: entry.widgetData.weeklyWords,
                    today: entry.todayWords,
                    color: .blue
                )
                
                WeeklyStatCard(
                    icon: "clock",
                    title: "Minutes",
                    thisWeek: entry.widgetData.weeklyMinutes,
                    today: entry.todayMinutes,
                    color: .green
                )
            }
            
            Spacer()
            
            // Goal progress
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Daily Goal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(entry.goalProgress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.secondary.opacity(0.3))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(.blue)
                            .frame(width: geometry.size.width * entry.goalProgress, height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
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

// MARK: - Widget Bundle

@main
struct LifeWrappedWidgetBundle: WidgetBundle {
    var body: some Widget {
        LifeWrappedWidget()
        StreakFocusWidget()
        GoalsWidget()
        WeeklyStatsWidget()
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

#Preview("Goals Medium", as: .systemMedium) {
    GoalsWidget()
} timeline: {
    LifeWrappedEntry.placeholder
}

#Preview("Weekly Large", as: .systemLarge) {
    WeeklyStatsWidget()
} timeline: {
    LifeWrappedEntry.placeholder
}
