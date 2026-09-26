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
                    Image(systemName: "briefcase")
                    Text("Work")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.08))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // Personal button
            Link(destination: WidgetDeepLink.recordPersonal) {
                HStack {
                    Image(systemName: "house")
                    Text("Personal")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.08))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // Streak indicator
            if entry.isStreakAtRisk {
                Label("Save your streak", systemImage: "flame")
                    .font(.caption2)
                    .foregroundStyle(.primary)
            } else if entry.streakDays > 0 {
                Label("\(entry.streakDays) day streak", systemImage: "flame")
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
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 56, height: 56)
                        Image(systemName: "briefcase")
                            .font(.title2)
                            .foregroundStyle(.primary)
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
                        .fill(Color.primary)
                        .frame(width: 70, height: 70)
                    Image(systemName: "mic")
                        .font(.title)
                        .foregroundStyle(Color(.systemBackground))
                }
            }
            
            // Personal button
            Link(destination: WidgetDeepLink.recordPersonal) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 56, height: 56)
                        Image(systemName: "house")
                            .font(.title2)
                            .foregroundStyle(.primary)
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
                    Label("Save your \(entry.streakDays) day streak", systemImage: "flame")
                        .font(.caption2)
                        .foregroundStyle(.primary)
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
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            
            Text("\(entry.todaySessions)")
                .font(.system(size: 48, weight: .regular, design: .serif))
            
            Text(entry.todaySessions == 1 ? "session today" : "sessions today")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Streak indicator
            if entry.streakDays > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame")
                        .foregroundStyle(.secondary)
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
        Text("\(entry.todaySessions) sessions today")
            .widgetURL(WidgetDeepLink.history)
    }
}

// MARK: - Widget Bundle

@main
struct LifeWrappedWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordWidget()
        SessionsWidget()
    }
}

// MARK: - Previews

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

#Preview("Record Circular", as: .accessoryCircular) {
    RecordWidget()
} timeline: {
    LifeWrappedEntry.placeholder
}
