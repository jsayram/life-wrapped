// =============================================================================
// LifeWrapped Widget Extension
// =============================================================================

import WidgetKit
import SwiftUI
import WidgetCore

// MARK: - Deep Link URLs

enum WidgetDeepLink {
    static let home = URL(string: "lifewrapped://home")!
    static let history = URL(string: "lifewrapped://history")!
    static let overview = URL(string: "lifewrapped://overview")!
    static let settings = URL(string: "lifewrapped://settings")!
    static let record = URL(string: "lifewrapped://record")!
    static let recordWork = URL(string: "lifewrapped://record?category=work")!
    static let recordPersonal = URL(string: "lifewrapped://record?category=personal")!
}

// MARK: - Widget Entry

struct LifeWrappedEntry: TimelineEntry {
    let date: Date
    let widgetData: WidgetData
    
    var streakDays: Int { widgetData.streakDays }
    var todayWords: Int { widgetData.todayWords }
    var todayMinutes: Int { widgetData.todayMinutes }
    var todaySessions: Int { widgetData.todayEntries }
    var lastEntryTime: Date? { widgetData.lastEntryTime }
    var isStreakAtRisk: Bool { widgetData.isStreakAtRisk }
    
    static let placeholder = LifeWrappedEntry(
        date: Date(),
        widgetData: .placeholder
    )
    
    static let empty = LifeWrappedEntry(
        date: Date(),
        widgetData: .empty
    )
}

// MARK: - Timeline Provider

struct LifeWrappedProvider: TimelineProvider {
    typealias Entry = LifeWrappedEntry
    
    private let dataManager = WidgetDataManager.shared
    
    func placeholder(in context: Context) -> LifeWrappedEntry {
        .placeholder
    }
    
    func getSnapshot(in context: Context, completion: @escaping (LifeWrappedEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(loadCurrentEntry())
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<LifeWrappedEntry>) -> Void) {
        let entry = loadCurrentEntry()
        
        // Refresh every 15 minutes for fresher data
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadCurrentEntry() -> LifeWrappedEntry {
        let widgetData = dataManager.readWidgetData()
        return LifeWrappedEntry(date: Date(), widgetData: widgetData)
    }
}

// MARK: - Today Widget (Main Stats)

struct TodayWidget: Widget {
    let kind: String = "LifeWrappedTodayWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LifeWrappedProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Summary")
        .description("View your daily journaling stats and streak.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct TodayWidgetView: View {
    let entry: LifeWrappedEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            TodaySmallView(entry: entry)
        case .systemMedium:
            TodayMediumView(entry: entry)
        case .accessoryCircular:
            TodayCircularView(entry: entry)
        case .accessoryRectangular:
            TodayRectangularView(entry: entry)
        case .accessoryInline:
            TodayInlineView(entry: entry)
        default:
            TodaySmallView(entry: entry)
        }
    }
}

struct TodaySmallView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        VStack(spacing: 12) {
            // Streak
            VStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(entry.streakDays > 0 ? .orange : .gray)
                Text("\(entry.streakDays)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("day streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Sessions count
            VStack(spacing: 2) {
                Text("\(entry.todaySessions)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("sessions today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if entry.isStreakAtRisk {
                Text("Record today!")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fontWeight(.medium)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WidgetDeepLink.home)
    }
}

struct TodayMediumView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Left side - Streak
            VStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(entry.streakDays > 0 ? .orange : .gray)
                
                Text("\(entry.streakDays)")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("day streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if entry.isStreakAtRisk {
                    Text("At risk!")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fontWeight(.medium)
                }
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            // Center - Sessions count
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 24))
                    .foregroundStyle(.purple)
                
                Text("\(entry.todaySessions)")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            // Right side - Record button
            Link(destination: WidgetDeepLink.record) {
                VStack(spacing: 8) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.red)
                    Text("Record")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WidgetDeepLink.home)
    }
}

// Lock Screen Widgets
struct TodayCircularView: View {
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

struct TodayRectangularView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.title3)
            VStack(alignment: .leading) {
                Text("\(entry.streakDays) day streak")
                    .font(.headline)
                Text("\(entry.todaySessions) sessions today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .widgetURL(WidgetDeepLink.home)
    }
}

struct TodayInlineView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        Text("🔥 \(entry.streakDays)d · \(entry.todaySessions) sessions")
            .widgetURL(WidgetDeepLink.home)
    }
}

// MARK: - Record Widget (With Work/Personal Toggle)

struct RecordWidget: Widget {
    let kind: String = "LifeWrappedRecordWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LifeWrappedProvider()) { entry in
            RecordWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Record")
        .description("Start recording with Work or Personal category.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular
        ])
    }
}

struct RecordWidgetView: View {
    let entry: LifeWrappedEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            RecordSmallView(entry: entry)
        case .systemMedium:
            RecordMediumView(entry: entry)
        case .accessoryCircular:
            RecordCircularView(entry: entry)
        default:
            RecordSmallView(entry: entry)
        }
    }
}

struct RecordSmallView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        VStack(spacing: 12) {
            // Work button
            Link(destination: WidgetDeepLink.recordWork) {
                HStack {
                    Image(systemName: "briefcase.fill")
                    Text("Work")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.2))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // Personal button
            Link(destination: WidgetDeepLink.recordPersonal) {
                HStack {
                    Image(systemName: "person.fill")
                    Text("Personal")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.purple.opacity(0.2))
                .foregroundStyle(.purple)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // Streak indicator
            if entry.isStreakAtRisk {
                Text("🔥 Save your streak!")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if entry.streakDays > 0 {
                Text("🔥 \(entry.streakDays) day streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct RecordMediumView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Work button
            Link(destination: WidgetDeepLink.recordWork) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 56, height: 56)
                        Image(systemName: "briefcase.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    Text("Work")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .frame(maxWidth: .infinity)
            
            // Big mic button
            Link(destination: WidgetDeepLink.record) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.red, .red.opacity(0.7)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 35
                            )
                        )
                        .frame(width: 70, height: 70)
                    Image(systemName: "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
            
            // Personal button
            Link(destination: WidgetDeepLink.recordPersonal) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.2))
                            .frame(width: 56, height: 56)
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundStyle(.purple)
                    }
                    Text("Personal")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .overlay(alignment: .bottom) {
            HStack {
                if entry.isStreakAtRisk {
                    Label("Save your \(entry.streakDays) day streak!", systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Label("\(entry.todaySessions) sessions today", systemImage: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct RecordCircularView: View {
    let entry: LifeWrappedEntry
    
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

// MARK: - Sessions Widget

struct SessionsWidget: Widget {
    let kind: String = "LifeWrappedSessionsWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LifeWrappedProvider()) { entry in
            SessionsWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Sessions")
        .description("Quick view of your session count for today.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}

struct SessionsWidgetView: View {
    let entry: LifeWrappedEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SessionsSmallView(entry: entry)
        case .accessoryCircular:
            SessionsCircularView(entry: entry)
        case .accessoryInline:
            SessionsInlineView(entry: entry)
        default:
            SessionsSmallView(entry: entry)
        }
    }
}

struct SessionsSmallView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 32))
                .foregroundStyle(.purple)
            
            Text("\(entry.todaySessions)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
            
            Text(entry.todaySessions == 1 ? "session today" : "sessions today")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Streak indicator
            if entry.streakDays > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(entry.streakDays)")
                        .fontWeight(.semibold)
                }
                .font(.caption)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WidgetDeepLink.history)
    }
}

struct SessionsCircularView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: "waveform")
                    .font(.caption)
                Text("\(entry.todaySessions)")
                    .font(.headline)
                    .fontWeight(.bold)
            }
        }
        .widgetURL(WidgetDeepLink.history)
    }
}

struct SessionsInlineView: View {
    let entry: LifeWrappedEntry
    
    var body: some View {
        Text("📝 \(entry.todaySessions) sessions today")
            .widgetURL(WidgetDeepLink.history)
    }
}

// MARK: - Widget Bundle

@main
struct LifeWrappedWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        RecordWidget()
        SessionsWidget()
    }
}

// MARK: - Previews

#Preview("Today Small", as: .systemSmall) {
    TodayWidget()
} timeline: {
    LifeWrappedEntry.placeholder
    LifeWrappedEntry.empty
}

#Preview("Today Medium", as: .systemMedium) {
    TodayWidget()
} timeline: {
    LifeWrappedEntry.placeholder
}

#Preview("Record Small", as: .systemSmall) {
    RecordWidget()
} timeline: {
    LifeWrappedEntry.placeholder
}

#Preview("Record Medium", as: .systemMedium) {
    RecordWidget()
} timeline: {
    LifeWrappedEntry.placeholder
}

#Preview("Sessions Small", as: .systemSmall) {
    SessionsWidget()
} timeline: {
    LifeWrappedEntry.placeholder
}

#Preview("Today Rectangular", as: .accessoryRectangular) {
    TodayWidget()
} timeline: {
    LifeWrappedEntry.placeholder
}

#Preview("Record Circular", as: .accessoryCircular) {
    RecordWidget()
} timeline: {
    LifeWrappedEntry.placeholder
}
