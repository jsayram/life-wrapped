# Life Wrapped - AI Agent Instructions

## 🚧 Project Status: Greenfield V1 Development

**This is an active V1 project under initial development.** All documentation describes the CURRENT state of the app, not historical changes or migrations.

**Development Philosophy:**

- ✅ Breaking changes are acceptable — this is day-one development
- ✅ Data loss is fine — SQLite data can be regenerated from test recordings
- ✅ No migration concerns unless explicitly requested by the developer
- ✅ Treat all code changes as "what the app IS" not "what changed"
- ✅ Documentation reflects current implementation, updated as features evolve

**When making changes:**

- Modify database schemas directly without ALTER TABLE migrations
- Change model structures without backward compatibility concerns
- Refactor architecture freely — no production users yet
- Update this documentation to reflect the NEW current state

---

## Architecture Overview

**Privacy-First Audio Journaling App** — All processing happens on-device using Swift 6 with strict concurrency.

### Core Data Flow

```
Recording → Auto-Chunking → Storage (SQLite) → Parallel Transcription → Session Summary → Insights
```

**Key Architectural Pattern**: Session-based chunking

- Audio is split into 30-300s chunks (configurable) within a recording session
- Each session has UUID + multiple chunks (UUID + chunkIndex)
- Chunks process independently but group together for playback/transcription

### Package Structure (Local Swift Packages)

- **SharedModels**: Core data types (`AudioChunk`, `TranscriptSegment`, `Summary`, `RecordingSession`)
- **Storage**: SQLite via raw `sqlite3` API (no dependencies), uses `actor` for thread safety
- **AudioCapture**: AVAudioEngine recording + playback, `@MainActor` isolated
- **Transcription**: Apple Speech framework with abandoned utterance detection
- **Summarization**: On-device LLM adapter (placeholder for Core ML integration)
- **InsightsRollup**: Time-based aggregations (hour/day/week/month buckets)
- **WidgetCore**: Shared widget data models

### Critical Concurrency Patterns

**Swift 6 Strict Concurrency** is enabled. All code must be concurrency-safe:

```swift
// Database operations use actor
public actor DatabaseManager { }

// UI-bound managers use @MainActor
@MainActor
public final class AudioCaptureManager: ObservableObject { }

// Background processing in Task blocks
Task {
    try await self.transcribeAudio(chunk: chunk)
}
```

**Rule**: DatabaseManager is an `actor`, always call with `await`. AppCoordinator is `@MainActor`, coordinates all async operations.

## Development Workflows

### Building

```bash
# Fast package-only build
./Scripts/build.sh packages

# Full iOS build
xcodebuild -scheme LifeWrapped -destination 'generic/platform=iOS Simulator' build
```

### Database Schema Changes

**Current Schema Version: V1** — No migrations yet, this is the initial schema.

Database schema lives in `Packages/Storage/Sources/Storage/DatabaseManager.swift`:

- **Approach**: Modify tables directly in `initializeDatabase()` method
- Change columns, indexes, or constraints in CREATE TABLE statements
- Delete app and reinstall to regenerate database with new schema
- No migration code needed unless explicitly requested

**Current summaries table schema:**

```swift
private func initializeDatabase() throws {
    try execute("""
        CREATE TABLE IF NOT EXISTS summaries (
            id TEXT PRIMARY KEY,
            period_type TEXT NOT NULL,
            period_start REAL NOT NULL,
            period_end REAL NOT NULL,
            text TEXT NOT NULL,
            created_at REAL NOT NULL,
            session_id TEXT  -- Links summary to recording session
        )
    """)

    try execute("""
        CREATE INDEX IF NOT EXISTS idx_summaries_period
        ON summaries(period_type, period_start)
    """)

    try execute("""
        CREATE INDEX IF NOT EXISTS idx_summaries_session
        ON summaries(session_id)
    """)
}
```

**To modify schema**: Edit CREATE TABLE, delete app, reinstall. Test data regenerates from new recordings.

### Testing Transcription

Transcription has **abandoned utterance detection** to handle pauses:

```swift
// When Speech Recognition starts new utterance after pause, word count drops
// System detects this and saves abandoned text to allUtterances array
if newWordCount < currentWordCount {
    // Save abandoned utterance before processing new one
}
```

## Project-Specific Conventions

### Model Naming

- `AudioChunk`: A single recording segment (file on disk)
- `RecordingSession`: Groups multiple chunks by `sessionId`
- `TranscriptSegment`: Time-bounded text from transcription
- `Summary`: AI-generated summary (supports period-based OR session-based)

### Enum Extensions for Display

```swift
public enum PeriodType: String, Codable {
    case session, hour, day, week, month

    public var displayName: String { /* ... */ }
}
```

### Error Handling Pattern

```swift
public enum AppCoordinatorError: Error, Sendable {
    case notInitialized
    case transcriptionFailed(Error)
    // Always Sendable for Swift 6
}
```

### Observable Pattern

```swift
@MainActor
public final class AppCoordinator: ObservableObject {
    @Published public private(set) var recordingState: RecordingState = .idle
    // Published for UI, private(set) for encapsulation
}
```

## Key Integration Points

### AppCoordinator as Central Hub

`App/Coordinators/AppCoordinator.swift` orchestrates everything:

- Creates and manages all package managers
- Coordinates recording → transcription → summarization flow
- Updates widgets and insights
- **Pattern**: Background processing uses `Task {}` blocks, UI updates via `@Published`

### Parallel Transcription (Max 3 Concurrent)

```swift
private var pendingTranscriptions: [AudioChunk] = []
private var activeTranscriptionCount: Int = 0
private let maxConcurrentTranscriptions: Int = 3

// Chunks queue up, process 3 at a time
private func processTranscriptionQueue() async { /* ... */ }
```

### Session Summary Generation

Automatically triggered when all chunks in a session are transcribed:

```swift
// Check completion → Generate summary → Store with session_id
try await generateSessionSummary(sessionId: sessionId)
```

### UI State Management

`ContentView.swift` contains all views (1500+ lines):

- RecordingTab, HistoryTab (sessions list), SettingsTab, InsightsTab
- SessionDetailView with playback controls, waveform, transcript highlighting
- Uses Timers for real-time updates (playback position, transcription status)

## Common Tasks

### Adding a New Database Table

1. Add `CREATE TABLE` directly in `initializeDatabase()` method
2. Add CRUD methods to `DatabaseManager.swift`
3. Create corresponding model in `SharedModels`
4. Update `AppCoordinator` to use new methods
5. Delete app and reinstall to regenerate database with new schema

### Adding a New Summary Type

1. Add case to `PeriodType` enum in `SharedModels`
2. Update all switch statements (build will fail if missing)
3. Add generation logic in `AppCoordinator` or `SummarizationManager`

### Debugging Transcription Issues

Check logs for these markers:

- `🎯 [TranscriptionManager]` - Transcription lifecycle
- `🔄 [TranscriptionManager] Abandoned` - Detected pause/restart
- `💾 [TranscriptionManager] Saved` - Utterances preserved
- `🔄 [AppCoordinator]` - Parallel transcription queue

### Testing Playback

SessionDetailView implements:

- Sequential multi-chunk playback (auto-advance)
- Cross-chunk scrubbing (seeks to correct chunk)
- Real-time progress updates (50 waveform bars)
- Chunk highlighting in transcript

## Privacy Guarantees

**Non-Negotiable Rules**:

- ALL transcription uses `requiresOnDeviceRecognition = true`
- NO network calls in production code (verify with `./Scripts/verify-privacy.sh`)
- SQLite with `FileProtectionType.completeUntilFirstUserAuthentication`
- App Group sharing for widgets: `group.com.jsayram.lifewrapped`

## Build Configuration

Uses `.xcconfig` files in `Config/`:

- `Secrets.xcconfig` (gitignored) for API keys
- `Debug.xcconfig` / `Release.xcconfig` for build settings

## Documentation References

- [auto-chunking-transcription.md](../Docs/auto-chunking-transcription.md) - Complete feature architecture
- [README.md](../README.md) - Setup and development workflow

---

## Key Principles

1. **Greenfield Flexibility**: This is V1 development — make changes freely, no backward compatibility required
2. **Session-Based Architecture**: Chunk-processing pipeline with parallel transcription
3. **On-Device Only**: All processing local, privacy-first design
4. **Swift 6 Concurrency**: Maintain strict concurrency safety with actors and @MainActor
5. **Session Integrity**: Keep sessionId + chunkIndex relationship intact
6. **Documentation Currency**: Update this file to reflect current state, not change history
