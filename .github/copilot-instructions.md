# Life Wrapped - AI Agent Instructions

## Project Status: Shipped on the App Store

**Life Wrapped is live on the App Store with real users and a paid in-app purchase (Cloud AI).** Their journals live only on their devices, so there's no server copy to fall back on. Treat user data as irreplaceable.

**When making changes:**

- **Never lose user data.** Schema changes go through a new versioned migration in `Packages/Storage/Sources/Storage/Migrations/SchemaManager.swift` (bump `currentSchemaVersion`, add the step to `runMigrations`). Don't edit existing CREATE TABLE statements in a way that breaks older databases.
- Keep stored raw values stable: `EngineTier` raw values (`basic`, `local`, `apple`, `external`), `PeriodType` raw values and the in-app purchase product ID `com.jsayram.lifewrapped.smartestai`.
- Keep this file, the README and the website (`docs/`) describing the current app. When a feature changes what data leaves the device, update `docs/privacy.md` and `App/Views/Utility/PrivacyPolicyView.swift` in the same change.

---

## Architecture Overview

**Privacy-First Audio Journaling App** for iPhone and iPad. Transcription always happens on the device. Summaries come from one of four engines the user picks; only Cloud AI sends text off the device, to the user's own OpenAI or Anthropic account.

### Core Data Flow

```
Recording → Auto-Chunking → Storage (SQLite) → Parallel Transcription → Session Summary (Cloud AI / Apple Intelligence / Offline AI / Key Sentences) → Insights
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
- **Summarization**: Four engines, shown in the UI as Key Sentences (`BasicEngine`), Offline AI (`LocalEngine`), Apple Intelligence (`AppleEngine`) and Cloud AI (`ExternalAPIEngine`, OpenAI/Anthropic). Tier raw values stay `basic`, `local`, `apple`, `external`
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

**Current Schema Version: V4** (`currentSchemaVersion` in `Packages/Storage/Sources/Storage/Migrations/SchemaManager.swift`). V4 added the `summary_versions` table.

- **Approach**: add a versioned migration step in `SchemaManager.swift` (see "To modify schema" below)
- Existing databases upgrade in place; never ask users to delete the app

**Key Database Tables:**

- `audio_chunks` — Recording segments with session_id and chunk_index
- `transcript_segments` — Text segments with word_count, sentiment_score
- `summaries` — Period-based + session-level summaries (session_id column, engine_tier, input_hash)
- `summary_versions`: earlier text of a rewritten summary (up to 10 per summary, restorable; exported in JSON 1.1)
- `session_metadata` — Titles, notes, favorites for sessions
- `insights_rollups` — Time-based aggregations
- `control_events` — App control events

**Session Metadata Features:**

- User-editable session titles
- Personal notes per session
- Favorites system with star toggle
- **Session categorization** (Work/Personal) - User marks sessions, not AI inference
- Full-text search across transcripts

**Session Category System:**

- Users mark each recording as Work or Personal (the Record tab switch, or the recording screen)
- Categories stored in `session_metadata` table (`category: SessionCategory?`)
- Work and Personal are separate journals: each has its own month summaries (`MonthDigestBuilder`) and its own Year Wrap (`YearWrapBuilder`). "All" is combined in code, not by the model
- **Architecture**: User choice → Database → per-journal month summaries → per-journal Year Wrap (NOT AI inference from content)

**To modify schema**: add a versioned migration in `SchemaManager.swift`. Never require deleting the app.

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
- `ItemCategory`: Classification for Year Wrap items (work, personal, both)
- `ClassifiedItem`: Year Wrap insight with category (text + category)
- `ItemFilter`: PDF export filter (all, workOnly, personalOnly)

### Year Wrap and month summaries

- `SummaryCoordinator.updateMonthDigest` builds one `MonthDigest` per journal from that month's recording summaries, dates, labels and notes, and rebuilds it when those inputs change (hash check). Ended months are finished in the background when the app opens, and by the `com.jsayram.lifewrapped.finalize-months` `BGProcessingTask` while the device charges (`AppCoordinator.registerBackgroundTasks`).
- `SummaryCoordinator.wrapUpYear` builds one Year Wrap per journal from its month digests with the engine the user picked (any engine via `yearWrapGenerator`; Key Sentences returns no generator and builds the wrap without a model), then combines them for "All" with `YearWrapData.combining`.
- Engines have a fidelity rank (`EngineTier.fidelityRank`: Cloud AI, Apple Intelligence, Offline AI, Key Sentences). Never let a lower-ranked engine rewrite a higher-ranked summary, month story or Year Wrap without the user asking, and save rewrites through `replaceSessionSummary` or `upsertPeriodSummary` so the old text lands in `summary_versions`.
- `ItemCategory` (work, personal, both) and `ItemFilter` (all, workOnly, personalOnly) drive the filters and PDF export.

**Key Files**:

- [SummaryCoordinator.swift](../App/Coordinators/SummaryCoordinator.swift) - month digests, Year Wrap, titles
- [MonthDigestBuilder.swift](../Packages/Summarization/Sources/Summarization/MonthDigestBuilder.swift) - month summaries
- [YearWrapBuilder.swift](../Packages/Summarization/Sources/Summarization/YearWrapBuilder.swift) - Year Wrap
- [YearWrapDetailView.swift](../App/Views/Overview/YearWrapDetailView.swift) - Year Wrap screen and PDF export

### Enum Extensions for Display

```swift
public enum PeriodType: String, Codable, Sendable, CaseIterable {
    case session, hour, day, week, month, quarter, year
    case yearWrap, yearWrapWork, yearWrapPersonal, monthDigest
    // Only session, monthDigest and the yearWrap types are written now. The others stay
    // so older databases still decode.

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

**Memory-Optimized Queue System** — Uses UUIDs instead of full objects:

```swift
private var pendingTranscriptionIds: [UUID] = []
@Published public private(set) var transcribingChunkIds: Set<UUID> = []
@Published public private(set) var transcribedChunkIds: Set<UUID> = []
@Published public private(set) var failedChunkIds: Set<UUID> = []
private var activeTranscriptionCount: Int = 0
private let maxConcurrentTranscriptions: Int = 3

// Chunks queue by ID (16 bytes vs 200+ bytes per chunk)
// Fetch from database only when starting transcription
private func processTranscriptionQueue() async { /* ... */ }
```

**Key Benefits:**

- Memory usage: 100 chunks = 1.6KB (UUIDs) vs 20KB+ (full objects)
- Real-time UI updates via @Published status sets
- Retry mechanism via `retryTranscription(chunkId:)`

### Session Summary Generation

Automatically triggered when all chunks in a session are transcribed:

```swift
// Check completion → Generate summary → Store with session_id
try await generateSessionSummary(sessionId: sessionId)
```

### UI State Management

`ContentView.swift` contains all views (1600+ lines):

- RecordingTab, HistoryTab (sessions list), SettingsTab, InsightsTab
- SessionDetailView with playback controls, waveform, transcript highlighting
- Uses Timers for real-time updates (playback position, transcription status)

**Performance Features:**

- Word count caching in database (SUM() aggregate queries)
- Parallel loading with `withTaskGroup` for session word counts
- Status badges show real-time transcription progress per chunk
- Empty states with ContentUnavailableView for better UX

**Playback Features:**

- Pre-playback scrubbing (can seek before pressing play)
- Cross-chunk playback progress tracking
- Waveform visualization with playhead indicator
- Sequential multi-chunk playback with auto-advance

**Session Detail Features:**

- Editable session titles (persisted to database)
- Personal notes section per session
- Favorites with star toggle in toolbar
- AI Summary section with regenerate button
- Share transcript via system share sheet
- Copy transcript/summary to clipboard
- Tap chunk to seek playback position
- **Transcript Editing**: Edit transcript text directly with text selection support
- **Selectable Text**: Select and copy individual words from transcripts
- **Edit-aware Summary**: Prompt to regenerate summary after transcript edits

**History Tab Features:**

- Full-text search (titles, notes, dates, transcripts)
- Favorites filter toggle in toolbar
- Session titles and favorite stars in list rows
- Debounced transcript search for performance

## Common Tasks

### Adding a New Database Table

1. Add `CREATE TABLE` directly in `applySchema()` method
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
- Network calls are limited to: the Offline AI model download (Hugging Face), StoreKit, and Cloud AI requests to api.openai.com / api.anthropic.com plus the www.apple.com connectivity check, both only when the user has saved an API key. Any new network call needs a privacy policy update first (verify with `./Scripts/verify-privacy.sh`)
- SQLite with `FileProtectionType.completeUntilFirstUserAuthentication`
- App Group sharing for widgets: `group.com.jsayram.lifewrapped`

## Build Configuration

Uses `.xcconfig` files in `Config/`:

- `Secrets.xcconfig` (gitignored) for API keys
- `Debug.xcconfig` / `Release.xcconfig` for build settings

## Documentation References

- [auto-chunking-transcription.md](../App/appDocs/auto-chunking-transcription.md) - Complete feature architecture
- [docs/privacy.md](../docs/privacy.md) - What leaves the device, as promised to users
- [README.md](../README.md) - Setup and development workflow

---

## Key Principles

1. **Protect User Data**: The app is shipped. Migrate, never wipe, and keep stored raw values stable
2. **Session-Based Architecture**: Chunk-processing pipeline with parallel transcription
3. **On-Device First**: Transcription and three of the four summary engines run on the device; Cloud AI is opt-in and uses the user's own key
4. **Swift 6 Concurrency**: Maintain strict concurrency safety with actors and @MainActor
5. **Session Integrity**: Keep sessionId + chunkIndex relationship intact
6. **Documentation Currency**: Update this file to reflect current state, not change history
