// =============================================================================
// LifeWrapped Widget Extension
// =============================================================================

import WidgetKit
import SwiftUI

// MARK: - Widget Entry

struct LifeWrappedEntry: TimelineEntry {
    let date: Date
    let streakDays: Int
    let todayWords: Int
    let todayMinutes: Int
    let goalProgress: Double
    let lastEntryTime: Date?
    let isStreakAtRisk: Bool
    
    static let placeholder = LifeWrappedEntry(
        date: Date(),
        streakDays: 7,
        todayWords: 350,
        todayMinutes: 5,
        goalProgress: 0.7,
        lastEntryTime: Date().addingTimeInterval(-3600),
        isStreakAtRisk: false
    )
    
    static let empty = LifeWrappedEntry(
        date: Date(),
        streakDays: 0,
        todayWords: 0,
        todayMinutes: 0,
        goalProgress: 0,
        lastEntryTime: nil,
        isStreakAtRisk: false
    )
}

// MARK: - Timeline Provider

struct LifeWrappedProvider: TimelineProvider {
    
    func placeholder(in context: Context) -> LifeWrappedEntry {
        .placeholder
    }
    
    func getSnapshot(in context: Context, completion: @escaping (LifeWrappedEntry) -> Void) {
        // Return placeholder for preview
        if context.isPreview {
            completion(.placeholder)
            return
        }
        
        // Return actual data
        let entry = loadCurrentEntry()
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<LifeWrappedEntry>) -> Void) {
        let entry = loadCurrentEntry()
        
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadCurrentEntry() -> LifeWrappedEntry {
        // TODO: Load real data from App Group shared storage
        // For now, return placeholder data
        
        // In real implementation:
        // 1. Open shared SQLite database from App Group container
        // 2. Query today's rollup data
        // 3. Calculate streak from activity dates
        // 4. Return populated entry
        
        return LifeWrappedEntry(
            date: Date(),
            streakDays: loadStreakDays(),
            todayWords: loadTodayWords(),
            todayMinutes: loadTodayMinutes(),
            goalProgress: loadGoalProgress(),
            lastEntryTime: loadLastEntryTime(),
            isStreakAtRisk: loadIsStreakAtRisk()
        )
    }
    
    // MARK: - Data Loading (Placeholder implementations)
    
    private func loadStreakDays() -> Int {
        // TODO: Load from App Group
        return 0
    }
    
    private func loadTodayWords() -> Int {
        // TODO: Load from App Group
        return 0
    }
    
    private func loadTodayMinutes() -> Int {
        // TODO: Load from App Group
        return 0
    }
    
    private func loadGoalProgress() -> Double {
        // TODO: Load from App Group
        return 0
    }
    
    private func loadLastEntryTime() -> Date? {
        // TODO: Load from App Group
        return nil
    }
    
    private func loadIsStreakAtRisk() -> Bool {
        // TODO: Load from App Group
        return false
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

@main
struct LifeWrappedWidget: Widget {
    let kind: String = "LifeWrappedWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LifeWrappedProvider()) { entry in
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
