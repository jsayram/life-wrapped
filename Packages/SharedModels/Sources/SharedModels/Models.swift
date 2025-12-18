// =============================================================================
// SharedModels — Core Data Types
// =============================================================================
// Cross-platform models used by all packages and apps.
// =============================================================================

import Foundation

// MARK: - Audio Chunk

/// Represents a recorded audio segment stored on disk.
public struct AudioChunk: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let fileURL: URL
    public let startTime: Date
    public let endTime: Date
    public let format: AudioFormat
    public let sampleRate: Int
    public let createdAt: Date
    public let sessionId: UUID
    public let chunkIndex: Int

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        startTime: Date,
        endTime: Date,
        format: AudioFormat,
        sampleRate: Int,
        createdAt: Date = Date(),
        sessionId: UUID? = nil,
        chunkIndex: Int = 0
    ) {
        self.id = id
        self.fileURL = fileURL
        self.startTime = startTime
        self.endTime = endTime
        self.format = format
        self.sampleRate = sampleRate
        self.createdAt = createdAt
        self.sessionId = sessionId ?? id // Default to own ID for backward compatibility
        self.chunkIndex = chunkIndex
    }

    /// Duration in seconds
    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
}

// MARK: - Recording Session

/// Represents a logical recording session composed of multiple audio chunks
public struct RecordingSession: Identifiable, Sendable, Hashable {
    public let sessionId: UUID
    public let chunks: [AudioChunk]
    
    // Optional metadata (loaded from session_metadata table)
    public var title: String?
    public var notes: String?
    public var isFavorite: Bool
    
    public var id: UUID { sessionId }
    
    public init(sessionId: UUID, chunks: [AudioChunk], title: String? = nil, notes: String? = nil, isFavorite: Bool = false) {
        self.sessionId = sessionId
        self.chunks = chunks.sorted { $0.chunkIndex < $1.chunkIndex }
        self.title = title
        self.notes = notes
        self.isFavorite = isFavorite
    }
    
    /// Display name: title if set, otherwise formatted time
    public var displayName: String {
        if let title = title, !title.isEmpty {
            return title
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }
    
    /// Total duration of all chunks combined
    public var totalDuration: TimeInterval {
        chunks.reduce(0) { $0 + $1.duration }
    }
    
    /// Number of chunks in this session
    public var chunkCount: Int {
        chunks.count
    }
    
    /// Start time of the first chunk
    public var startTime: Date {
        chunks.first?.startTime ?? Date()
    }
    
    /// End time of the last chunk
    public var endTime: Date {
        chunks.last?.endTime ?? Date()
    }
    
    /// Created at timestamp from the first chunk
    public var createdAt: Date {
        chunks.first?.createdAt ?? Date()
    }
}

// MARK: - Audio Format

public enum AudioFormat: String, Codable, Sendable, CaseIterable {
    case wav
    case m4a
    case caf

    public var fileExtension: String {
        rawValue
    }

    public var mimeType: String {
        switch self {
        case .wav: "audio/wav"
        case .m4a: "audio/mp4"
        case .caf: "audio/x-caf"
        }
    }
}

// MARK: - Transcript Segment

/// A transcribed segment of speech with timing information.
public struct TranscriptSegment: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let audioChunkID: UUID
    public let startTime: TimeInterval  // Offset from audio chunk start
    public let endTime: TimeInterval
    public let text: String
    public let confidence: Float
    public let languageCode: String
    public let createdAt: Date
    public let wordCount: Int  // Cached word count
    public let sentimentScore: Double?  // NEW: Sentiment from -1.0 (negative) to +1.0 (positive)

    // Future fields (placeholders)
    public let speakerLabel: String?
    public let entitiesJSON: String?

    public init(
        id: UUID = UUID(),
        audioChunkID: UUID,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        confidence: Float,
        languageCode: String = "en-US",
        createdAt: Date = Date(),
        speakerLabel: String? = nil,
        entitiesJSON: String? = nil,
        wordCount: Int? = nil,
        sentimentScore: Double? = nil
    ) {
        self.id = id
        self.audioChunkID = audioChunkID
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.confidence = confidence
        self.languageCode = languageCode
        self.createdAt = createdAt
        self.speakerLabel = speakerLabel
        self.entitiesJSON = entitiesJSON
        // Calculate word count if not provided
        self.wordCount = wordCount ?? text.split(separator: " ").count
        self.sentimentScore = sentimentScore
    }

    /// Duration of this segment in seconds
    public var duration: TimeInterval {
        endTime - startTime
    }
    
    /// Categorized sentiment label for UI display
    public var sentimentCategory: String {
        guard let score = sentimentScore else { return "unknown" }
        switch score {
        case ..<(-0.3): return "negative"
        case -0.3..<0.3: return "neutral"
        default: return "positive"
        }
    }
}

// MARK: - Summary

/// An AI-generated summary for a time period.
public struct Summary: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let periodType: PeriodType
    public let periodStart: Date
    public let periodEnd: Date
    public let text: String
    public let createdAt: Date
    public let sessionId: UUID?  // Optional: set for session summaries
    public let topicsJSON: String?  // JSON array of topics
    public let entitiesJSON: String?  // JSON array of entities
    public let engineTier: String?  // "basic", "apple", "local", "external"

    public init(
        id: UUID = UUID(),
        periodType: PeriodType,
        periodStart: Date,
        periodEnd: Date,
        text: String,
        createdAt: Date = Date(),
        sessionId: UUID? = nil,
        topicsJSON: String? = nil,
        entitiesJSON: String? = nil,
        engineTier: String? = nil
    ) {
        self.id = id
        self.periodType = periodType
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.text = text
        self.createdAt = createdAt
        self.sessionId = sessionId
        self.topicsJSON = topicsJSON
        self.entitiesJSON = entitiesJSON
        self.engineTier = engineTier
    }
}

// MARK: - Period Type

public enum PeriodType: String, Codable, Sendable, CaseIterable {
    case session  // Session-level summary
    case hour
    case day
    case week
    case month

    public var displayName: String {
        switch self {
        case .session:
            return "Session"
        case .hour:
            return "Hour"
        case .day:
            return "Day"
        case .week:
            return "Week"
        case .month:
            return "Month"
        }
    }
}

// MARK: - Insights Rollup

/// Pre-aggregated statistics for a time bucket.
public struct InsightsRollup: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let bucketType: PeriodType
    public let bucketStart: Date
    public let bucketEnd: Date
    public let wordCount: Int
    public let speakingSeconds: Double
    public let segmentCount: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        bucketType: PeriodType,
        bucketStart: Date,
        bucketEnd: Date,
        wordCount: Int,
        speakingSeconds: Double,
        segmentCount: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bucketType = bucketType
        self.bucketStart = bucketStart
        self.bucketEnd = bucketEnd
        self.wordCount = wordCount
        self.speakingSeconds = speakingSeconds
        self.segmentCount = segmentCount
        self.createdAt = createdAt
    }

    /// Words per minute
    public var wordsPerMinute: Double {
        guard speakingSeconds > 0 else { return 0 }
        return Double(wordCount) / (speakingSeconds / 60.0)
    }
}

// MARK: - Control Event

/// Logs user actions and state changes.
public struct ControlEvent: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let source: EventSource
    public let type: EventType
    public let payloadJSON: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: EventSource,
        type: EventType,
        payloadJSON: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.type = type
        self.payloadJSON = payloadJSON
    }
}

public enum EventSource: String, Codable, Sendable, CaseIterable {
    case phone
    case watch
    case widget
    case siri
    case system
}

public enum EventType: String, Codable, Sendable, CaseIterable {
    case startListening
    case stopListening
    case toggleMode
    case addMarker
    case exportBackup
    case importBackup
    case summarize
}
