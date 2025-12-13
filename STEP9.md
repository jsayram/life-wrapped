# Step 9: Integration — iPhone App Core

## Overview

This step integrates all packages into a cohesive iPhone app experience, creating:

- **AppCoordinator**: Central orchestrator connecting all packages
- **Main UI**: SwiftUI-based tabbed interface with recording, history, and insights

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        LifeWrappedApp                                │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                     AppCoordinator                           │   │
│  │  @MainActor ObservableObject                                 │   │
│  │                                                               │   │
│  │  Recording Flow:                                              │   │
│  │  startRecording() → AudioCaptureManager                      │   │
│  │  stopRecording() → TranscriptionManager → Storage            │   │
│  │                   → SummarizationManager → InsightsManager   │   │
│  │                   → WidgetDataManager → WidgetKit            │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              ↓                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                      ContentView (TabView)                   │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐           │   │
│  │  │  Home   │ │ History │ │Insights │ │Settings │           │   │
│  │  │   Tab   │ │   Tab   │ │   Tab   │ │   Tab   │           │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘           │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Files Created

### App/Coordinators/AppCoordinator.swift

Central orchestrator that:

- Manages initialization of all package managers
- Controls recording flow (start → stop → process)
- Publishes state for SwiftUI observation
- Updates widget data via App Group

Key types:

```swift
// Recording state machine
public enum RecordingState: Sendable, Equatable {
    case idle
    case recording(startTime: Date)
    case processing
    case completed(chunkId: UUID)
    case failed(String)
}

// Today's activity summary
public struct DayStats: Sendable, Equatable {
    let date: Date
    let segmentCount: Int
    let wordCount: Int
    let totalDuration: TimeInterval
}

// Main coordinator
@MainActor
public final class AppCoordinator: ObservableObject {
    @Published var recordingState: RecordingState
    @Published var currentStreak: Int
    @Published var todayStats: DayStats
    @Published var isInitialized: Bool

    func initialize() async
    func startRecording() async throws
    func stopRecording() async throws -> UUID
    func cancelRecording() async
    func refreshStreak() async
    func refreshTodayStats() async
    func updateWidgetData() async
    func fetchRecentRecordings(limit:) async throws -> [AudioChunk]
    func fetchTranscript(for:) async throws -> [TranscriptSegment]
    func fetchRecentSummaries(limit:) async throws -> [Summary]
    func deleteRecording(_:) async throws
}
```

### App/ContentView.swift

SwiftUI interface with:

- **HomeTab**: Streak display, recording button, today's stats
- **HistoryTab**: List of past recordings with swipe-to-delete
- **InsightsTab**: Daily/weekly summaries
- **SettingsTab**: Preferences and data management

Key components:

- `StreakCard`: Shows current streak with motivational messages
- `RecordingButton`: Animated mic button with state transitions
- `TodayStatsCard`: Entry count, word count, duration
- `RecordingRow`: Individual recording in history list
- `SummaryRow`: Summary card with period type badge

### App/LifeWrappedApp.swift

App entry point that:

- Creates AppCoordinator as StateObject
- Passes coordinator via EnvironmentObject
- Triggers async initialization on app launch

## Recording Flow

```
User taps Record
      ↓
AppCoordinator.startRecording()
      ↓
AudioCaptureManager.startRecording(mode: .active)
      ↓
User taps Stop
      ↓
AppCoordinator.stopRecording()
      │
      ├─→ AudioCaptureManager.stopRecording()
      │       ↓ (callback: onChunkCompleted)
      │   AudioChunk created
      │
      ├─→ DatabaseManager.insertAudioChunk(chunk)
      │
      ├─→ TranscriptionManager.transcribe(chunk: chunk)
      │       ↓
      │   [TranscriptSegment] returned
      │
      ├─→ DatabaseManager.insertTranscriptSegment (for each)
      │
      ├─→ SummarizationManager.generateSummary(from:to:)
      │       ↓
      │   Summary saved to database
      │
      ├─→ InsightsManager.generateRollup(bucketType: .day)
      │       ↓
      │   InsightsRollup saved to database
      │
      ├─→ WidgetDataManager.writeWidgetData(...)
      │
      └─→ WidgetCenter.shared.reloadAllTimelines()
```

## Data Flow

```
                    SharedModels
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
   AudioChunk    TranscriptSegment   InsightsRollup
         │               │               │
         └───────────────┼───────────────┘
                         │
                         ▼
                  DatabaseManager (Storage)
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
   AppCoordinator ◄──────────────► WidgetDataManager
         │                               │
         ▼                               ▼
    SwiftUI Views                  Widget Extension
```

## Package Dependencies

The main app now depends on all packages:

- `SharedModels`: Core data types
- `Storage`: SQLite database operations
- `AudioCapture`: Microphone recording
- `Transcription`: Speech-to-text conversion
- `Summarization`: Text summarization
- `InsightsRollup`: Analytics aggregation
- `WidgetCore`: Widget data sharing

## Concurrency Model

- **AppCoordinator**: `@MainActor` for UI state management
- **AudioCaptureManager**: `@MainActor` for audio session
- **DatabaseManager**: Actor for thread-safe database access
- **TranscriptionManager**: Actor for speech recognition
- **SummarizationManager**: Actor for text processing
- **InsightsManager**: Actor for analytics

All inter-package communication uses `async/await`.

## Testing

Total tests across all packages: **117 tests**

| Package        | Tests |
| -------------- | ----- |
| SharedModels   | 7     |
| Storage        | 10    |
| AudioCapture   | 14    |
| Transcription  | 10    |
| Summarization  | 20    |
| InsightsRollup | 28    |
| WidgetCore     | 28    |

## Next Steps

1. **Step 10**: Background processing and audio detection
2. **Step 11**: Export functionality (JSON, markdown)
3. **Step 12**: Final polish and App Store preparation
