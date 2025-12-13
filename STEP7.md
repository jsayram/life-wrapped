# Step 7: Widget Extension

## Overview

Step 7 implements a comprehensive iOS Widget Extension for Life Wrapped, enabling users to view their journaling statistics directly from their Home Screen and Lock Screen. The widget supports multiple configurations and sizes, providing at-a-glance access to streaks, goals, and weekly stats.

## Architecture

### Package Structure

```
Packages/WidgetCore/
├── Package.swift
├── Sources/WidgetCore/
│   ├── WidgetCore.swift          # Public exports
│   ├── WidgetData.swift          # Data model for widget display
│   ├── WidgetDataManager.swift   # App Group storage manager
│   └── WidgetDisplayMode.swift   # Configuration modes
└── Tests/WidgetCoreTests/
    └── WidgetCoreTests.swift     # 28 comprehensive tests

WidgetExtension/
├── LifeWrappedWidget.swift       # Widget bundle and views
├── Info.plist                    # Extension configuration
└── WidgetExtension.entitlements  # App Group access
```

### Data Flow

```
┌─────────────────┐    ┌─────────────────────┐    ┌─────────────────┐
│   Main App      │───▶│  WidgetDataManager  │◀───│  Widget         │
│   (writes)      │    │  (App Group)        │    │  (reads)        │
└─────────────────┘    └─────────────────────┘    └─────────────────┘
         │                       │                        │
         ▼                       ▼                        ▼
┌─────────────────┐    ┌─────────────────────┐    ┌─────────────────┐
│ InsightsRollup  │    │  UserDefaults       │    │ TimelineProvider│
│ StreakCalculator│    │  (shared container) │    │ (30min refresh) │
│ GoalTracker     │    │                     │    │                 │
└─────────────────┘    └─────────────────────┘    └─────────────────┘
```

## Widget Types

### 1. Life Wrapped Widget (Main)

The primary widget showing an overview of journaling activity.

**Supported Sizes:**

- **System Small**: Streak count, today's words, goal progress bar
- **System Medium**: Split view with streak badge and stats (words, minutes)
- **System Large**: Full stats grid with goal progress, last entry time
- **Accessory Circular**: Lock screen streak counter
- **Accessory Rectangular**: Lock screen streak and words
- **Accessory Inline**: Lock screen text ("🔥 7 day streak")

### 2. Streak Focus Widget

Dedicated widget for streak tracking.

**Features:**

- Large animated flame icon
- Streak day count
- "Streak at risk" warning when needed
- Encouraging messages

### 3. Goals Widget

Daily goal progress tracking.

**Features:**

- Circular progress ring
- Goal percentage
- Word count display
- Today's progress breakdown

### 4. Weekly Stats Widget

Weekly summary view.

**Features:**

- Weekly word and minute totals
- Today's contribution
- Streak badge
- Goal progress bar

## Core Components

### WidgetData

```swift
public struct WidgetData: Codable, Sendable, Equatable {
    public let streakDays: Int
    public let todayWords: Int
    public let todayMinutes: Int
    public let todayEntries: Int
    public let goalProgress: Double
    public let lastEntryTime: Date?
    public let isStreakAtRisk: Bool
    public let weeklyWords: Int
    public let weeklyMinutes: Int
    public let lastUpdated: Date
}
```

### WidgetDataManager

```swift
public final class WidgetDataManager: @unchecked Sendable {
    // App Group identifier for shared storage
    public static let appGroupIdentifier = "group.com.jsayram.lifewrapped"

    // Read widget data from App Group
    public func readWidgetData() -> WidgetData

    // Write widget data to App Group
    @discardableResult
    public func writeWidgetData(_ widgetData: WidgetData) -> Bool

    // Update widget data with closure
    @discardableResult
    public func updateWidgetData(_ update: (inout WidgetData) -> Void) -> Bool

    // Check data freshness
    public func isDataStale(maxAge: TimeInterval = 3600) -> Bool
}
```

### WidgetDisplayMode

```swift
public enum WidgetDisplayMode: String, CaseIterable, Sendable, Codable {
    case overview = "Overview"
    case streak = "Streak Focus"
    case goals = "Goals"
    case weekly = "Weekly Stats"

    var displayName: String
    var description: String
    var icon: String
}
```

## App Group Integration

### Entitlements

Both the main app and widget extension share the App Group:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.jsayram.lifewrapped</string>
</array>
```

### Data Sync Pattern

The main app writes widget data after:

1. Recording completion
2. Transcription completion
3. Daily rollup generation
4. Goal updates

```swift
// In main app after data changes
let widgetData = WidgetData.from(
    streakDays: streakCalculator.currentStreak,
    todayWordCount: rollup.wordCount,
    todayDuration: rollup.totalDuration,
    todayEntryCount: rollup.entryCount,
    dailyWordGoal: goalTracker.dailyWordGoal,
    lastEntryDate: lastEntry?.createdAt,
    weeklyWordCount: weeklyRollup.wordCount,
    weeklyDuration: weeklyRollup.totalDuration
)
WidgetDataManager.shared.writeWidgetData(widgetData)
WidgetCenter.shared.reloadAllTimelines()
```

## Timeline Provider

```swift
struct LifeWrappedProvider: AppIntentTimelineProvider {
    func timeline(for configuration: LifeWrappedWidgetIntent, in context: Context) async -> Timeline<LifeWrappedEntry> {
        let entry = loadCurrentEntry(configuration: configuration.displayMode)

        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!

        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}
```

## Widget Configuration

Users can configure widgets through the App Intents system:

```swift
struct LifeWrappedWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Configure Widget"
    static let description: IntentDescription = "Choose what to display in your widget."

    @Parameter(title: "Display Mode", default: .overview)
    var displayMode: WidgetDisplayModeIntent
}
```

## Visual Design

### Color Coding

- **Streak Flame**: Orange gradient (active) / Gray (inactive)
- **Goal Progress**:
  - 0-25%: Red
  - 25-50%: Orange
  - 50-75%: Yellow
  - 75-100%: Green
  - 100%+: Blue

### Streak At Risk

Visual warning when:

- User has an active streak (> 0 days)
- No entry today
- It's past noon

Displays: "Journal today!" in red

## Testing

### Test Coverage (28 tests)

**WidgetData Tests (12 tests)**

- Empty data validation
- Placeholder values
- Custom initialization
- Codable conformance
- Factory method calculations
- Goal progress capping
- Zero goal handling
- Equatable conformance
- Duration conversion

**WidgetDataManager Tests (8 tests)**

- Unavailable App Group handling
- Empty data reading
- Write and read operations
- Update operations
- Clear operations
- Data staleness detection
- Shared instance access
- App Group identifier validation

**WidgetDisplayMode Tests (8 tests)**

- Raw value validation
- Unique values
- Display names
- Descriptions
- Icons
- Codable conformance
- Sendable conformance
- Mode-specific properties

### Running Tests

```bash
# Run WidgetCore tests
cd Packages/WidgetCore && swift test

# Expected output:
# ✔ Test run with 28 tests in 3 suites passed
```

## Build Configuration

### project.yml additions

```yaml
packages:
  WidgetCore:
    path: Packages/WidgetCore

targets:
  LifeWrappedWidget:
    type: app-extension
    platform: iOS
    dependencies:
      - package: SharedModels
      - package: Storage
      - package: InsightsRollup
      - package: WidgetCore
      - sdk: WidgetKit.framework
      - sdk: SwiftUI.framework
```

## Mac Catalyst Support

Widgets are configured for Mac Catalyst:

```yaml
SUPPORTS_MACCATALYST: true
DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER: true
```

## Privacy

All widget data is:

- Stored locally in App Group container
- Never transmitted externally
- Aggregated statistics only (no actual journal content)
- User-controlled refresh rate

## Future Enhancements

1. **Interactive Widgets**: Add buttons for quick recording
2. **Live Activities**: Show recording status
3. **StandBy Mode**: Optimize for horizontal display
4. **Watch Complications**: Extend to Apple Watch
5. **Custom Intents**: Allow goal threshold customization

## Summary

Step 7 delivers a complete widget experience:

| Component                 | Description                             |
| ------------------------- | --------------------------------------- |
| **WidgetCore Package**    | Testable data layer for widgets         |
| **4 Widget Types**        | Overview, Streak, Goals, Weekly         |
| **6 Size Classes**        | All system and accessory sizes          |
| **App Group Sharing**     | Secure data sync between app and widget |
| **28 Tests**              | Full coverage of data and manager logic |
| **Configuration Intents** | User-customizable display modes         |

The widget extension enables users to stay connected to their journaling practice without opening the app, providing motivation through visible streaks and goal progress.
