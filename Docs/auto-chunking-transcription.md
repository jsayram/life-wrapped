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

## Implementation Roadmap

### Step 1: Database Session Queries

**Goal**: Add methods to fetch all chunks for a session and list all sessions

**Tasks**:

- Add `fetchChunksForSession(sessionId:)` → returns all chunks with same session_id
- Add `fetchAllSessions()` → returns distinct session_ids with metadata (first chunk timestamp, total chunks, total duration)
- Test: Print session list and verify chunks group correctly

**Testing**: Record 5+ minute session (2+ chunks), verify database returns all chunks for that session

---

### Step 2: History UI - Session Grouping

**Goal**: Display sessions instead of individual chunks in History

**Tasks**:

- Modify HistoryTab to fetch sessions instead of individual chunks
- Show session card with: total duration, total words, chunk count
- Display session start time (from first chunk)
- Group by date sections as before

**Testing**: History should show 1 card per session with aggregated stats

---

### Step 3: Detail View - Multi-Chunk Playback

**Goal**: Update RecordingDetailView to handle sessions with multiple chunks

**Tasks**:

- Modify detail view to accept sessionId instead of single chunk
- Fetch all chunks for session and display in order
- Show chunk boundaries in transcript (e.g., "— Chunk 2 —")
- Update audio player to play chunks sequentially
- Show combined transcript from all chunks

**Testing**: Tap session in History, should show all chunks and play continuously

---

### Step 4: Parallel Transcription with TaskGroup

**Goal**: Transcribe multiple chunks simultaneously (max 3 concurrent)

**Tasks**:

- Add `transcribeBatch()` method using TaskGroup
- Track active transcription count (max 3 concurrent)
- Queue additional chunks if limit reached
- Update progress tracking for batch operations

**Testing**: Record 6+ minute session (3+ chunks), verify chunks transcribe in parallel (check logs for concurrent processing)

---

### Step 5: Session Summary Generation

**Goal**: Generate summary across all chunks in a session

**Tasks**:

- Modify summarization to accept array of transcripts
- Combine all chunk transcripts before summarization
- Store summary at session level (not chunk level)
- Display session-wide summary in detail view

**Testing**: Multi-chunk session should have one coherent summary covering all content

---

### Step 6: Export Complete Session Transcripts

**Goal**: Export full session transcript as text file

**Tasks**:

- Add export button in RecordingDetailView
- Combine all chunk transcripts in order
- Format with timestamps and chunk markers
- Use UIActivityViewController for sharing
- Support .txt format with metadata header

**Testing**: Tap export, share transcript via Messages/Files/Email, verify complete content

---

### Step 7: Polish & Edge Cases

**Goal**: Handle edge cases and improve UX

**Tasks**:

- Handle single-chunk sessions gracefully (no chunk markers)
- Add loading states during multi-chunk operations
- Improve error handling for missing chunks
- Add session deletion (deletes all chunks)
- Update widget to show session count instead of chunk count

**Testing**: Test with various session lengths, verify smooth UX

---

## Current Status

✅ **Completed**: Auto-chunking, complete transcription, pause handling, abandoned utterance detection, configurable chunk duration

📋 **Ready to Build**: Follow steps 1-7 above, building and testing after each step

## Code References

- Auto-chunking timer: [AudioCaptureManager.swift](../Packages/AudioCapture/Sources/AudioCapture/AudioCaptureManager.swift)
- Transcription logic: [TranscriptionManager.swift](../Packages/Transcription/Sources/Transcription/TranscriptionManager.swift)
- Orchestration: [AppCoordinator.swift](../App/Coordinators/AppCoordinator.swift)
- Settings UI: [ContentView.swift](../App/ContentView.swift) (SettingsTab)
- Database schema: [DatabaseManager.swift](../Packages/Storage/Sources/Storage/DatabaseManager.swift)
