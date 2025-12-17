//
//  IntelligenceModels.swift
//  SharedModels
//
//  Created by Life Wrapped on 12/16/2025.
//

import Foundation

// MARK: - Entity Recognition

/// Represents an entity extracted from transcribed text
public struct Entity: Codable, Sendable, Hashable {
    public let name: String
    public let type: EntityType
    public let confidence: Double  // 0.0 to 1.0
    
    public init(name: String, type: EntityType, confidence: Double) {
        self.name = name
        self.type = type
        self.confidence = confidence
    }
}

/// Categories of entities that can be extracted
public enum EntityType: String, Codable, Sendable {
    case person
    case location
    case organization
    case event
    case dateTime
    case other
    
    public var displayName: String {
        switch self {
        case .person: return "Person"
        case .location: return "Location"
        case .organization: return "Organization"
        case .event: return "Event"
        case .dateTime: return "Date/Time"
        case .other: return "Other"
        }
    }
    
    public var emoji: String {
        switch self {
        case .person: return "👤"
        case .location: return "📍"
        case .organization: return "🏢"
        case .event: return "📅"
        case .dateTime: return "🕐"
        case .other: return "💡"
        }
    }
}

// MARK: - Chunk Intelligence

/// Structured intelligence output from processing a single audio chunk
public struct ChunkIntelligence: Codable, Sendable {
    public let chunkId: UUID
    public let summary: String
    public let topics: [String]
    public let entities: [Entity]
    public let sentiment: Double  // -1.0 (negative) to 1.0 (positive)
    public let languageCode: String?
    
    public init(
        chunkId: UUID,
        summary: String,
        topics: [String],
        entities: [Entity],
        sentiment: Double,
        languageCode: String? = nil
    ) {
        self.chunkId = chunkId
        self.summary = summary
        self.topics = topics
        self.entities = entities
        self.sentiment = sentiment
        self.languageCode = languageCode
    }
}

// MARK: - Session Intelligence

/// Structured intelligence output from processing a complete recording session
public struct SessionIntelligence: Codable, Sendable {
    public let sessionId: UUID
    public let summary: String
    public let topics: [String]
    public let entities: [Entity]
    public let sentiment: Double  // -1.0 (negative) to 1.0 (positive)
    public let duration: TimeInterval
    public let wordCount: Int
    public let languageCodes: [String]
    public let keyMoments: [KeyMoment]?
    
    public init(
        sessionId: UUID,
        summary: String,
        topics: [String],
        entities: [Entity],
        sentiment: Double,
        duration: TimeInterval,
        wordCount: Int,
        languageCodes: [String],
        keyMoments: [KeyMoment]? = nil
    ) {
        self.sessionId = sessionId
        self.summary = summary
        self.topics = topics
        self.entities = entities
        self.sentiment = sentiment
        self.duration = duration
        self.wordCount = wordCount
        self.languageCodes = languageCodes
        self.keyMoments = keyMoments
    }
}

// MARK: - Key Moments

/// Represents a significant moment within a session
public struct KeyMoment: Codable, Sendable, Hashable {
    public let timestamp: TimeInterval  // Offset from session start
    public let description: String
    public let importance: Double  // 0.0 to 1.0
    
    public init(timestamp: TimeInterval, description: String, importance: Double) {
        self.timestamp = timestamp
        self.description = description
        self.importance = importance
    }
}

// MARK: - Period Intelligence

/// Structured intelligence for time-based period summaries (day, week, month)
public struct PeriodIntelligence: Codable, Sendable {
    public let periodType: PeriodType
    public let periodStart: Date
    public let periodEnd: Date
    public let summary: String
    public let topics: [String]
    public let entities: [Entity]
    public let sentiment: Double
    public let sessionCount: Int
    public let totalDuration: TimeInterval
    public let totalWordCount: Int
    public let trends: [String]?  // e.g., "Increased focus on work topics"
    
    public init(
        periodType: PeriodType,
        periodStart: Date,
        periodEnd: Date,
        summary: String,
        topics: [String],
        entities: [Entity],
        sentiment: Double,
        sessionCount: Int,
        totalDuration: TimeInterval,
        totalWordCount: Int,
        trends: [String]? = nil
    ) {
        self.periodType = periodType
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.summary = summary
        self.topics = topics
        self.entities = entities
        self.sentiment = sentiment
        self.sessionCount = sessionCount
        self.totalDuration = totalDuration
        self.totalWordCount = totalWordCount
        self.trends = trends
    }
}

// MARK: - Helper Extensions

extension Array where Element == Entity {
    /// Groups entities by type for easier display
    public func groupedByType() -> [EntityType: [Entity]] {
        Dictionary(grouping: self, by: { $0.type })
    }
    
    /// Returns unique entity names (case-insensitive)
    public var uniqueNames: [String] {
        var seen = Set<String>()
        return self.compactMap { entity in
            let lowercased = entity.name.lowercased()
            guard !seen.contains(lowercased) else { return nil }
            seen.insert(lowercased)
            return entity.name
        }
    }
}

extension Array where Element == String {
    /// Returns unique topics (case-insensitive)
    public var uniqueTopics: [String] {
        var seen = Set<String>()
        return self.compactMap { topic in
            let lowercased = topic.lowercased()
            guard !seen.contains(lowercased) else { return nil }
            seen.insert(lowercased)
            return topic
        }
    }
}
