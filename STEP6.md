# Step 6: InsightsRollup Package

## Overview

The InsightsRollup package provides analytics, metrics aggregation, streak tracking, and goal management for the voice journaling app. This step was split into:

- **Step 6A**: Core insights manager with rollup aggregation for different time periods
- **Step 6B**: Streak calculator, goal tracker, and comprehensive tests

## Features

### Core Capabilities

- **Rollup Aggregation**: Pre-calculated statistics for hour, day, week, month periods
- **Streak Tracking**: Track consecutive days of journaling activity
- **Goal Management**: Set and track progress toward journaling goals
- **Period Comparison**: Compare activity between two time periods
- **Analytics Queries**: Total words, speaking time, averages
- **Trend Analysis**: Identify patterns in journaling behavior
- **Actor-based**: Thread-safe concurrent operations

### Components

#### 1. InsightsManager (Actor)

Main analytics coordinator:

- `generateRollup(bucketType:for:)`: Generate rollup for specific period
- `generateHourlyRollup(for:)`: Quick hourly rollup
- `generateDailyRollup(for:)`: Quick daily rollup
- `generateWeeklyRollup(for:)`: Quick weekly rollup
- `generateMonthlyRollup(for:)`: Quick monthly rollup
- `generateAllRollups(for:)`: Generate all period types for a date
- `generateRollupsForRange(bucketType:from:to:)`: Batch rollup generation
- `getTotalSpeakingTime(from:to:)`: Total speaking seconds
- `getTotalWordCount(from:to:)`: Total words spoken
- `getAverageWordsPerDay(from:to:)`: Average daily word count
- `comparePeriods(...)`: Compare two time periods

#### 2. StreakCalculator (Struct)

Streak tracking functionality:

- `calculateStreak(from:)`: Calculate current and longest streaks
- `streakAtRisk(_:)`: Check if streak will break without activity today
- `StreakInfo`: Current/longest streak, dates, status messages
- Automatic streak detection from activity dates
- Emoji status messages for user motivation

#### 3. GoalTracker (Struct)

Goal setting and progress tracking:

- `Goal`: Configurable goal with type and target
- `GoalProgress`: Progress calculation with percentage and status
- `GoalType`: Daily/weekly goals for words, minutes, entries
- `createDefaultGoals()`: Pre-configured goal set
- `calculateProgress(goal:wordCount:speakingSeconds:entryCount:)`: Progress calculation
- Progress emojis based on completion level

#### 4. PeriodComparison (Struct)

Time period comparison:

- Word count, speaking time, entry count for both periods
- Percentage change calculations
- `isImproving`: Boolean improvement indicator
- `trendDescription`: Human-readable trend ("Significantly more active", etc.)

#### 5. InsightsError (Enum)

Comprehensive error handling:

- `noDataAvailable`: No data for insights
- `invalidDateRange`: Invalid start/end dates
- `aggregationFailed`: Aggregation process failed
- `storageError`: Database error
- `insufficientData`: Not enough data points
- `invalidBucketType`: Unknown period type
- `calculationError`: Math/calculation error

## Package Structure

```
Packages/InsightsRollup/
├── Package.swift
├── Sources/
│   └── InsightsRollup/
│       ├── InsightsManager.swift       (280+ lines, analytics engine)
│       ├── StreakCalculator.swift      (130+ lines, streak tracking)
│       ├── GoalTracker.swift           (140+ lines, goal management)
│       └── InsightsError.swift         (45+ lines, error definitions)
└── Tests/
    └── InsightsRollupTests/
        └── InsightsRollupTests.swift   (280+ lines, 28 tests in 6 suites)
```

## Usage Examples

### Generating Rollups

```swift
import InsightsRollup
import Storage

// Initialize
let databaseManager = DatabaseManager()
let insightsManager = InsightsManager(storage: databaseManager)

// Generate daily rollup for today
do {
    let rollup = try await insightsManager.generateDailyRollup(for: Date())

    print("Today's Stats:")
    print("  Words: \(rollup.wordCount)")
    print("  Speaking: \(Int(rollup.speakingSeconds / 60)) minutes")
    print("  Entries: \(rollup.segmentCount)")
    print("  WPM: \(String(format: "%.1f", rollup.wordsPerMinute))")
} catch {
    print("No data for today: \(error)")
}
```

### Weekly and Monthly Rollups

```swift
// Generate weekly rollup
let weeklyRollup = try await insightsManager.generateWeeklyRollup(for: Date())

print("This Week:")
print("  Total words: \(weeklyRollup.wordCount)")
print("  Total speaking: \(Int(weeklyRollup.speakingSeconds / 60)) minutes")

// Generate monthly rollup
let monthlyRollup = try await insightsManager.generateMonthlyRollup(for: Date())
print("This Month: \(monthlyRollup.wordCount) words")
```

### Batch Rollup Generation

```swift
// Generate rollups for a date range
let startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
let endDate = Date()

let count = try await insightsManager.generateRollupsForRange(
    bucketType: .day,
    from: startDate,
    to: endDate,
    onProgress: { completed, total in
        print("Progress: \(completed)/\(total)")
    }
)

print("Generated \(count) daily rollups")
```

### Period Comparison

```swift
// Compare this week to last week
let calendar = Calendar.current
let thisWeekStart = calendar.startOfDay(for: Date())
let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeekStart)!
let lastWeekEnd = thisWeekStart

let comparison = try await insightsManager.comparePeriods(
    period1Start: lastWeekStart,
    period1End: lastWeekEnd,
    period2Start: thisWeekStart,
    period2End: Date()
)

print("Week-over-week:")
print("  Words: \(comparison.period1Words) → \(comparison.period2Words)")
print("  Change: \(String(format: "%.1f", comparison.wordChangePercent))%")
print("  Trend: \(comparison.trendDescription)")
print("  Improving: \(comparison.isImproving ? "Yes" : "No")")
```

### Streak Tracking

```swift
import InsightsRollup

// Get activity dates (from database)
let activityDates: [Date] = [...] // Dates with journal entries

// Calculate streaks
let streakInfo = StreakCalculator.calculateStreak(from: activityDates)

print("Streak Info:")
print("  Current: \(streakInfo.currentStreak) days")
print("  Longest: \(streakInfo.longestStreak) days")
print("  Active Today: \(streakInfo.isActiveToday)")
print("  Status: \(streakInfo.statusMessage)")

// Check if streak is at risk
if StreakCalculator.streakAtRisk(streakInfo) {
    print("⚠️ Journal today to keep your streak!")
}
```

### Goal Setting and Progress

```swift
import InsightsRollup

// Create default goals
let goals = GoalTracker.createDefaultGoals()

// Or create custom goal
let customGoal = GoalTracker.Goal(type: .dailyWords, target: 1000)

// Calculate progress
let progress = GoalTracker.calculateProgress(
    goal: customGoal,
    wordCount: 650,
    speakingSeconds: 180,
    entryCount: 3
)

print("Goal Progress:")
print("  \(progress.goal.type.displayName): \(Int(progress.current))/\(Int(progress.goal.target))")
print("  Progress: \(Int(progress.progressPercent))% \(progress.progressEmoji)")
print("  Remaining: \(Int(progress.remaining)) \(progress.goal.type.unit)")
print("  Status: \(progress.statusMessage)")
```

### Analytics Queries

```swift
// Get aggregate stats for date range
let startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
let endDate = Date()

let totalWords = try await insightsManager.getTotalWordCount(from: startDate, to: endDate)
let totalSpeaking = try await insightsManager.getTotalSpeakingTime(from: startDate, to: endDate)
let avgWordsPerDay = try await insightsManager.getAverageWordsPerDay(from: startDate, to: endDate)

print("Last 30 Days:")
print("  Total words: \(totalWords)")
print("  Total speaking: \(Int(totalSpeaking / 60)) minutes")
print("  Average words/day: \(Int(avgWordsPerDay))")
```

## Architecture Decisions

### Rollup Pre-aggregation

Statistics are pre-calculated and stored:

- Reduces query time for dashboards
- Enables efficient time-series analysis
- Supports offline analytics
- Four bucket types: hour, day, week, month

### Bucket Boundary Calculation

Consistent boundary logic:

- **Hour**: Minutes and seconds set to 0
- **Day**: Start of calendar day (midnight)
- **Week**: Sunday through Saturday
- **Month**: First day of month to first day of next month

### Streak Calculation Logic

1. Convert activity dates to unique calendar days
2. Check if today is active
3. Walk backward from today (or yesterday) counting consecutive days
4. Separately calculate longest historical streak
5. Track streak start date for UI display

### Goal System Design

- Six default goal types (3 daily + 3 weekly)
- Flexible target values
- Progress calculation based on goal type
- Visual feedback with emojis
- Status messages for motivation

## Testing

### Test Suite (28 tests in 6 suites)

**Insights Error Tests (3 tests)**

- ✅ Error descriptions are meaningful
- ✅ Insufficient data error includes counts
- ✅ Invalid bucket type error includes type name

**Period Comparison Tests (5 tests)**

- ✅ Comparison detects improvement
- ✅ Comparison detects decline
- ✅ Trend description for significant increase
- ✅ Trend description for significant decrease
- ✅ Trend description for stable activity

**Bucket Calculation Tests (4 tests)**

- ✅ Daily bucket covers 24 hours
- ✅ Weekly bucket covers 7 days
- ✅ Monthly bucket starts on first day
- ✅ Hourly bucket covers 60 minutes

**InsightsRollup Model Tests (4 tests)**

- ✅ Words per minute calculation
- ✅ Words per minute handles zero speaking time
- ✅ All period types are iterable
- ✅ Period type display names are meaningful

**Streak Calculator Tests (5 tests)**

- ✅ Empty dates returns zero streak
- ✅ Today only gives streak of 1
- ✅ Streak at risk when not active today
- ✅ Streak not at risk when active today
- ✅ Status message for active streak

**Goal Tracker Tests (7 tests)**

- ✅ Default goals have expected values
- ✅ Goal type display names are meaningful
- ✅ Goal type units are correct
- ✅ Progress calculation for words goal
- ✅ Progress calculation for completed goal
- ✅ Progress emoji reflects progress
- ✅ Daily vs weekly goal detection

### Running Tests

```bash
cd Packages/InsightsRollup
swift test
```

**Result**: All 28 tests passed in 0.008 seconds

## Dependencies

- **SharedModels**: InsightsRollup, PeriodType, TranscriptSegment models
- **Storage**: DatabaseManager for data retrieval and rollup storage
- **Foundation**: Date, Calendar, TimeInterval

## Swift 6 Concurrency

The package uses Swift 6 strict concurrency:

- Actor isolation for InsightsManager
- Sendable conformance for all structs
- Async/await for all database operations
- No data races possible

## Performance Considerations

### Optimization Strategies

1. **Pre-aggregation**: Statistics calculated once and stored
2. **Batch Processing**: Generate multiple rollups efficiently
3. **Efficient Queries**: Date-range indexed lookups
4. **Progress Callbacks**: Non-blocking batch operations
5. **Calendar Caching**: Reuse Calendar instance

### Resource Usage

- Rollups stored once, queried many times
- Streak calculation O(n) for n activity dates
- Goal progress calculation O(1)
- Memory efficient: no caching of raw data

## Default Goal Values

| Goal Type      | Default Target | Unit    |
| -------------- | -------------- | ------- |
| Daily Words    | 500            | words   |
| Daily Minutes  | 5              | minutes |
| Daily Entries  | 1              | entries |
| Weekly Words   | 3,500          | words   |
| Weekly Minutes | 30             | minutes |
| Weekly Entries | 5              | entries |

## Progress Emoji Guide

| Progress | Emoji | Meaning       |
| -------- | ----- | ------------- |
| 0-24%    | 🌱    | Just starting |
| 25-49%   | 🌿    | Growing       |
| 50-74%   | 🌳    | Thriving      |
| 75-99%   | 🔥    | Almost there  |
| 100%+    | 🏆    | Goal achieved |

## Trend Descriptions

| Change %    | Description                 |
| ----------- | --------------------------- |
| > +20%      | "Significantly more active" |
| +5% to +20% | "Slightly more active"      |
| -5% to +5%  | "About the same"            |
| -20% to -5% | "Slightly less active"      |
| < -20%      | "Significantly less active" |

## Integration with Other Packages

### Transcription → InsightsRollup

```swift
// After transcription, update rollups
let segments = try await transcriptionManager.transcribe(chunk: chunk)

// Generate/update today's rollup
let rollup = try await insightsManager.generateDailyRollup(for: Date())
```

### Summarization → InsightsRollup

```swift
// Use insights in summaries
let weeklyRollup = try await insightsManager.generateWeeklyRollup(for: Date())

// Include stats in summary context
let summary = try await summarizationManager.generateWeeklySummary(for: Date())
```

### UI Integration

```swift
// Dashboard view model
@MainActor
class DashboardViewModel: ObservableObject {
    @Published var streak: StreakCalculator.StreakInfo?
    @Published var goalProgress: [GoalTracker.GoalProgress] = []

    func loadData() async {
        // Get activity dates and calculate streak
        let dates = await storage.getActivityDates()
        streak = StreakCalculator.calculateStreak(from: dates)

        // Calculate goal progress
        let rollup = try? await insightsManager.generateDailyRollup(for: Date())
        goalProgress = GoalTracker.createDefaultGoals().map { goal in
            GoalTracker.calculateProgress(
                goal: goal,
                wordCount: rollup?.wordCount ?? 0,
                speakingSeconds: rollup?.speakingSeconds ?? 0,
                entryCount: rollup?.segmentCount ?? 0
            )
        }
    }
}
```

## Build Information

- **Build Time**: ~0.5s
- **Lines of Code**: ~875 lines (including tests)
- **Test Coverage**: 28 tests across 6 test suites
- **Swift Version**: 6.2.1
- **Platform**: macOS 15.0+, iOS 18.0+, watchOS 11.0+

## Completion Checklist

- ✅ InsightsManager with rollup aggregation
- ✅ Multiple bucket types (hour, day, week, month)
- ✅ Batch rollup generation with progress
- ✅ Period comparison with trend analysis
- ✅ Analytics queries (total, average)
- ✅ StreakCalculator with consecutive day tracking
- ✅ GoalTracker with progress and emojis
- ✅ PeriodComparison with trend descriptions
- ✅ Comprehensive error handling
- ✅ 28 passing tests in 6 suites
- ✅ Actor-based thread safety
- ✅ Comprehensive documentation

**Status**: Step 6 Complete ✅
