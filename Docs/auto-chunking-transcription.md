# Auto-Chunking & Transcription Feature

## Overview

Life Wrapped includes an intelligent auto-chunking recording system with robust speech-to-text transcription that captures every word you speak, regardless of pauses. This feature enables long-form recording sessions while ensuring accurate, complete transcription of your spoken content.

## Key Features

### 1. **Auto-Chunking Recording**

- Automatically splits long recording sessions into manageable chunks
- Configurable chunk duration (30 seconds to 300 seconds)
- Seamless chunk transitions without audio loss
- Session-based architecture groups related chunks together

### 2. **Complete Transcription**

- Captures **every single word** from the beginning of each recording
- Handles pauses of any length gracefully (seconds, minutes, or longer)
- Never misses text regardless of speech patterns or silence duration
- On-device processing for privacy and performance

### 3. **Pause Handling Intelligence**

The transcription system includes sophisticated pause detection that:

- Detects when Speech Recognition starts a new utterance after pauses
- Automatically saves abandoned text when word count drops
- Accumulates all utterances across the entire recording
- Concatenates multiple speech segments with proper spacing

## Architecture

### Recording Flow

```
Start Recording
    ↓
Create New Session (UUID)
    ↓
Start Audio Capture (Chunk 0)
    ↓
Auto-Chunk Timer (Every N Seconds)
    ↓
[Timer Fires] → Finalize Current Chunk → Start Next Chunk
    ↓                    ↓
Continue Recording      Process Chunk:
                        1. Save to Database
                        2. Start Transcription (Background)
                        3. Save Transcript Segments
                        4. Update Statistics
    ↓
Stop Recording → Finalize Final Chunk → Process
```

### Session Structure

Each recording session consists of:

- **Session ID**: Unique identifier (UUID) for the recording session
- **Chunks**: Ordered array of audio chunks (0, 1, 2, ...)
- **Duration**: Configurable chunk size (default 180 seconds)
- **Timestamps**: Start and end times for each chunk

Example session:

```
Session: 9C70E221-C787-4625-BB79-1327C2E9F7F8
├── Chunk 0 (0:00 - 3:00)
├── Chunk 1 (3:00 - 6:00)
└── Chunk 2 (6:00 - 7:45)
```

### Transcription State Management

The transcription system uses a state-based approach:

```swift
TranscriptionState {
    allUtterances: [String]    // All completed speech segments
    currentUtterance: String   // In-progress speech
    fullText: String          // All utterances joined with spaces
}
```

**Processing Logic:**

1. **Partial Results**: Update `currentUtterance` with current speech
2. **Abandoned Detection**: If word count drops, save current to `allUtterances`
3. **Final Results**: Mark utterance complete, save to `allUtterances`
4. **Timeout**: Return `fullText` (concatenation of all utterances)

### Why Abandoned Detection?

Apple's Speech Recognition treats pauses as utterance boundaries. Sometimes it abandons the previous text without marking it "final" when starting a new utterance after a pause. Example:

```
Partial: "OK, we're going to talk and talk..." (37 words)
[Pause]
Partial: "Until..." (1 word)  ← Word count dropped!
```

The system detects this drop from 37→1 words and automatically saves the 37-word utterance before processing the new one.

## Configuration

### Chunk Duration Setting

Users can configure chunk duration in the Settings tab:

- **Range**: 30 seconds to 300 seconds (5 minutes)
- **Steps**: 30-second increments
- **Default**: 180 seconds (3 minutes)
- **Location**: Settings → Recording section

Shorter durations are useful for:

- Testing transcription quality
- Frequent checkpoints
- Lower memory usage

Longer durations are useful for:

- Extended conversations
- Fewer file segments
- Less overhead

## Technical Implementation

### Components

1. **AudioCaptureManager** (`Packages/AudioCapture`)

   - Manages audio recording with AVAudioEngine
   - Handles auto-chunk timer with RunLoop.common mode for reliability
   - Finalizes chunks and triggers callback for processing
   - Generates unique file URLs for each chunk

2. **TranscriptionManager** (`Packages/Transcription`)

   - Uses Apple's SFSpeechRecognizer for on-device transcription
   - Implements abandoned utterance detection
   - Accumulates all speech segments across pauses
   - Converts transcribed text to timestamped segments

3. **AppCoordinator** (`App/Coordinators`)

   - Orchestrates recording and transcription workflow
   - Processes chunks immediately via callback (not waiting for stop)
   - Launches background Tasks for parallel transcription
   - Updates statistics and widget data

4. **DatabaseManager** (`Packages/Storage`)
   - Stores audio chunks with session_id and chunk_index
   - Saves transcript segments with timestamps
   - Manages daily rollups and statistics

### Processing Pipeline

```
Chunk Complete
    ↓
Callback Invoked (Immediate)
    ↓
Save to Database
    ↓
Launch Background Task
    ↓
Transcribe Audio File
    ├─ Detect Pauses
    ├─ Accumulate Utterances
    ├─ Handle Abandoned Text
    └─ Wait for Timeout
    ↓
Convert to Segments
    ↓
Save Transcript Segments
    ↓
Update Statistics & Rollups
    ↓
Refresh UI
```

## Benefits

### For Users

- **Never miss a word**: Complete capture of all spoken content
- **Natural speech**: Speak with pauses, no rushing required
- **Long recordings**: No time limits or manual chunking needed
- **Fast access**: Chunks processed as they complete, not waiting for session end

### For System

- **Memory efficient**: Fixed-size chunks prevent excessive memory usage
- **Parallel processing**: Multiple chunks can transcribe simultaneously
- **Resilient**: Each chunk independent, one failure doesn't affect others
- **Privacy-first**: On-device transcription, no cloud processing

## Logging & Debugging

The system includes comprehensive logging:

```
🎧 [AudioCaptureManager] - Recording lifecycle events
🎯 [TranscriptionManager] - Transcription progress
⏳ [TranscriptionManager] Partial - Current word counts
✅ [TranscriptionManager] Final - Completed utterances
🔄 [TranscriptionManager] Abandoned - Detected abandoned text
💾 [TranscriptionManager] Saved - Preserved utterances
📊 [AppCoordinator] - Stats and rollup updates
```

## V1 Implementation Details

### Database Performance

**Word Count Caching**:

- `transcript_segments` table includes `word_count INTEGER NOT NULL DEFAULT 0`
- Calculated once during segment insertion: `text.split(separator: " ").count`
- `fetchSessionWordCount()` uses efficient `SUM(word_count)` aggregate query
- Parallel loading in HistoryTab with `withTaskGroup` for responsive UI

**Transaction Safety**:

- Database migrations wrapped in `BEGIN TRANSACTION` / `COMMIT`
- Automatic `ROLLBACK` on any error during migration
- Detailed logging for debugging: `🔄 Starting`, `📝 Transaction started`, `✅ Committed`, `❌ Rolled back`

### Transcription Architecture

**Memory-Optimized Queue**:

- Queue stores `[UUID]` instead of `[AudioChunk]` objects
- Memory impact: 100 chunks = 1.6KB (UUIDs) vs 20KB+ (full objects)
- Chunks fetched from database only when starting transcription
- Real-time status tracking with `@Published` sets:
  - `transcribingChunkIds: Set<UUID>` — Currently processing
  - `transcribedChunkIds: Set<UUID>` — Successfully completed
  - `failedChunkIds: Set<UUID>` — Errors encountered

**Parallel Processing**:

- Maximum 3 concurrent transcriptions (`maxConcurrentTranscriptions = 3`)
- Additional chunks queue until slot available
- Each transcription runs in background Task
- UI updates automatically via SwiftUI observation

**Error Recovery**:

- `retryTranscription(chunkId:)` method for failed chunks
- Moves chunk from `failedChunkIds` back to `pendingTranscriptionIds`
- Triggers `processTranscriptionQueue()` for automatic retry
- UI shows orange retry button for failed chunks

### User Interface

**Session Detail View**:

- **Status Badges**: Per-chunk indicators showing transcription state
  - 🔵 ProgressView + "Transcribing..." for active
  - ✅ Green checkmark for completed
  - ⚠️ Orange warning for failed
- **Empty States**: ContentUnavailableView with context-aware messages
  - "Transcribing Audio..." when chunks processing
  - "Transcription Failed" with explanation when errors
  - "No Transcript" fallback for other cases
- **Playback Controls**:
  - Pre-playback scrubbing enabled (seek before pressing play)
  - Waveform visualization with animated playhead
  - Cross-chunk progress tracking
  - Sequential auto-advance through multiple chunks
- **Retry Mechanism**: Orange button appears for failed chunks

**History Tab**:

- Session cards with aggregated statistics
- Word counts loaded in parallel using `withTaskGroup`
- Date-based grouping for organization
- Navigation to SessionDetailView on tap

**Settings Tab**:

- Chunk duration slider (30-300s in 30s increments)
- Toast feedback on changes: "Chunk duration updated to Xs"
- Real-time updates to `audioCapture.autoChunkDuration`

---

## Current Status - V1 Complete

✅ **Core Features Implemented**:

- Auto-chunking recording with configurable duration (30-300s)
- Complete transcription with pause handling
- Abandoned utterance detection for pauses
- Session-based architecture with multi-chunk support

✅ **Performance Optimizations**:

- Word count caching in database (`word_count` column)
- Memory-optimized transcription queue (UUID-based, ~90% reduction)
- Parallel word count loading with `withTaskGroup`
- Efficient SUM() aggregate queries for session statistics

✅ **User Experience**:

- Real-time transcription status badges (🔵 transcribing, ✅ completed, ⚠️ failed)
- Context-aware empty states with ContentUnavailableView
- One-tap retry for failed transcriptions
- Pre-playback scrubbing support
- Cross-chunk playback with progress tracking
- Toast notifications for settings changes

✅ **Technical Quality**:

- Transaction-safe database migrations with ROLLBACK
- Swift 6 strict concurrency compliance
- Comprehensive error handling and recovery
- Detailed logging for debugging

## Code References

- Auto-chunking timer: [AudioCaptureManager.swift](../Packages/AudioCapture/Sources/AudioCapture/AudioCaptureManager.swift)
- Transcription logic: [TranscriptionManager.swift](../Packages/Transcription/Sources/Transcription/TranscriptionManager.swift)
- Orchestration: [AppCoordinator.swift](../App/Coordinators/AppCoordinator.swift)
- Settings UI: [ContentView.swift](../App/ContentView.swift) (SettingsTab)
- Database schema: [DatabaseManager.swift](../Packages/Storage/Sources/Storage/DatabaseManager.swift)
