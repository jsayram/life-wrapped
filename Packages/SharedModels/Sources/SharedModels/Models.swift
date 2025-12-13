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

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        startTime: Date,
        endTime: Date,
        format: AudioFormat,
        sampleRate: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileURL = fileURL
        self.startTime = startTime
        self.endTime = endTime
        self.format = format
        self.sampleRate = sampleRate
        self.createdAt = createdAt
    }

    /// Duration in seconds
    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
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
        entitiesJSON: String? = nil
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
    }

    /// Duration of this segment in seconds
    public var duration: TimeInterval {
        endTime - startTime
    }

    /// Word count (simple whitespace split)
    public var wordCount: Int {
        text.split(separator: " ").count
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

    public init(
        id: UUID = UUID(),
        periodType: PeriodType,
        periodStart: Date,
        periodEnd: Date,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.periodType = periodType
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.text = text
        self.createdAt = createdAt
    }
}

// MARK: - Period Type

public enum PeriodType: String, Codable, Sendable, CaseIterable {
    case hour
    case day
    case week
    case month

    public var displayName: String {
        switch self {
        case .hour: "Hour"
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
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
