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

**Privacy-First Audio Journaling App** — Transcription happens on-device using Swift 6 with strict concurrency; AI summaries via external API or offline fallback.

### Core Data Flow

```
Recording → Auto-Chunking → Storage (SQLite) → Parallel Transcription → Session Summary (External AI / Apple Intelligence / Basic) → Insights
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
- **Summarization**: External API adapter (OpenAI/Anthropic) with fallback to Apple Intelligence and Basic engine
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

**Current Schema Version: V1** — All tables created in single `applySchema()` method.

Database schema lives in `Packages/Storage/Sources/Storage/DatabaseManager.swift`:

- **Approach**: Modify tables directly in `applySchema()` method
- Change columns, indexes, or constraints in CREATE TABLE statements
- Delete app and reinstall to regenerate database with new schema

**Key Database Tables:**

- `audio_chunks` — Recording segments with session_id and chunk_index
- `transcript_segments` — Text segments with word_count, sentiment_score
- `summaries` — Period-based + session-level summaries (session_id column)
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

- Users manually mark sessions as Work or Personal via picker in SessionDetailView
- Categories stored in `session_metadata` table (`category: SessionCategory?`)
- Year Wrap generation fetches all session categories and passes to AI as context
- AI classifies Year Wrap items as work/personal/both based on user's session categories
- **Architecture**: User choice → Database → Context → AI classification (NOT AI inference from content)

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
- `ItemCategory`: Classification for Year Wrap items (work, personal, both)
- `ClassifiedItem`: Year Wrap insight with category (text + category)
- `ItemFilter`: PDF export filter (all, workOnly, personalOnly)

### Year Wrap Work/Personal Classification

**Architecture**: User-defined session categories → AI classification context

Year Wrap items are classified based on which sessions they originated from:

```swift
// 1. User marks sessions in UI
SessionDetailView → Picker → updateSessionCategory(category: .work/.personal)

// 2. Year Wrap generation fetches categories
fetchSessionCategoriesForYear(year:) → [UUID: SessionCategory]
buildCategoryContext(categoryMap:) → String (context for AI)

// 3. AI receives context and classifies items
UniversalPrompt.buildMessages(categoryContext: "5 work sessions, 3 personal...")
AI returns: [ClassifiedItem] with .work, .personal, or .both

// 4. UI displays badges and PDF filters
CategoryBadge(category: .work) → 💼 Work (blue)
PDF Export with ItemFilter → filter items by category
```

**Key Files**:

- [SessionDetailView.swift](../../App/Views/Details/SessionDetailView.swift) - Category picker UI
- [SummaryCoordinator.swift](../../App/Coordinators/SummaryCoordinator.swift) - Category fetching logic
- [UniversalPrompt.swift](../../Packages/Summarization/Sources/Summarization/UniversalPrompt.swift) - AI schema with category rules
- [YearWrapDetailView.swift](../../App/Views/Overview/YearWrapDetailView.swift) - Category badges and PDF filters

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
