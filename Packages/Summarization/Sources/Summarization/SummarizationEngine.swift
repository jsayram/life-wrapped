//
//  SummarizationEngine.swift
//  Summarization
//
//  Created by Life Wrapped on 12/16/2025.
//

import Foundation
import SharedModels

// MARK: - Engine Tier

/// Tiers of summarization engines, ordered by capability
public enum EngineTier: String, Codable, Sendable, CaseIterable {
    case basic      // Simple extractive + keyword extraction
    case local      // Local LLM (Phi-3.5 via llama.cpp)
    case apple      // Apple Intelligence / Foundation Models (iOS 18.1+)
    case external   // External API (OpenAI, Anthropic with user keys)
    
    /// Private/on-device tiers only (excludes external)
    public static var privateTiers: [EngineTier] {
        [.basic, .local, .apple]
    }
    
    public var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .local: return "Local AI (Phi-3.5)"
        case .apple: return "Apple Intelligence"
        case .external: return "Year Wrapped Pro AI"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .basic: return "Fast, simple summarization"
        case .local: return "On-device LLM processing"
        case .apple: return "Apple's on-device AI (iOS 18.1+)"
        case .external: return "OpenAI, Anthropic with your API keys"
        }
    }
    
    public var icon: String {
        switch self {
        case .basic: return "bolt.fill"
        case .local: return "cpu.fill"
        case .apple: return "apple.intelligence"
        case .external: return "sparkles"
        }
    }
    
    public var description: String {
        switch self {
        case .basic:
            return "Fast on-device extractive summarization using sentence scoring and keyword analysis. Works offline."
        case .local:
            return "On-device LLM (Phi-3.5 Mini) for smart chunk-by-chunk processing. Each audio chunk is summarized by local AI, then aggregated. Works offline."
        case .apple:
            return "Advanced AI using Apple's on-device Foundation Models (iOS 18.1+, Apple Intelligence enabled). Works offline."
        case .external:
            return "Premium AI using external services (OpenAI or Anthropic). Requires your API key and internet connection. Automatically falls back to Basic when offline."
        }
    }
    
    /// Whether this tier requires internet connectivity
    public var requiresInternet: Bool {
        switch self {
        case .basic, .local, .apple: return false
        case .external: return true
        }
    }
    
    /// Whether this tier is privacy-preserving (fully on-device)
    public var isPrivacyPreserving: Bool {
        switch self {
        case .basic, .local, .apple: return true
        case .external: return false
        }
    }
}

// MARK: - Summarization Engine Protocol

/// Protocol for all summarization engines (Basic, Apple, Local, External)
public protocol SummarizationEngine: Sendable {
    
    /// The tier this engine represents
    var tier: EngineTier { get }
    
    /// Check if this engine is currently available on the device
    /// - Returns: true if engine can be used, false otherwise
    func isAvailable() async -> Bool
    
    /// Generate a session-level summary with structured intelligence
    /// - Parameters:
    ///   - sessionId: The UUID of the recording session
    ///   - transcriptText: The full concatenated transcript text
    ///   - duration: Total duration of the session in seconds
    ///   - languageCodes: Array of detected language codes
    /// - Returns: SessionIntelligence with summary, topics, entities, sentiment
    /// - Throws: SummarizationError if generation fails
    func summarizeSession(
        sessionId: UUID,
        transcriptText: String,
        duration: TimeInterval,
        languageCodes: [String]
    ) async throws -> SessionIntelligence
    
    /// Generate a period-level summary (day/week/month) by aggregating session summaries
    /// - Parameters:
    ///   - periodType: The type of period (day, week, month)
    ///   - sessionSummaries: Array of session-level summaries to aggregate
    ///   - periodStart: Start date of the period
    ///   - periodEnd: End date of the period
    /// - Returns: PeriodIntelligence with aggregated insights
    /// - Throws: SummarizationError if generation fails
    func summarizePeriod(
        periodType: PeriodType,
        sessionSummaries: [SessionIntelligence],
        periodStart: Date,
        periodEnd: Date,
        categoryContext: String?
    ) async throws -> PeriodIntelligence
}

// MARK: - Engine Configuration

/// Configuration for a summarization engine
public struct EngineConfiguration: Sendable {
    public let tier: EngineTier
    public let minimumWords: Int
    public let maxContextLength: Int
    public let timeoutSeconds: TimeInterval
    public let temperature: Double
    public let maxTokens: Int
    
    public init(
        tier: EngineTier,
        minimumWords: Int = 1,
        maxContextLength: Int = 4000,
        timeoutSeconds: TimeInterval = 30.0,
        temperature: Double = 0.3,
        maxTokens: Int = 2000
    ) {
        self.tier = tier
        self.minimumWords = minimumWords
        self.maxContextLength = maxContextLength
        self.timeoutSeconds = timeoutSeconds
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
    
    /// Default configuration for each tier
    public static func defaults(for tier: EngineTier) -> EngineConfiguration {
        switch tier {
        case .basic:
            return EngineConfiguration(
                tier: .basic,
                minimumWords: 1,
                maxContextLength: 10000,
                timeoutSeconds: 5.0,
                temperature: 0.0,  // Basic engine doesn't use temperature
                maxTokens: 500
            )
        case .local:
            return EngineConfiguration(
                tier: .local,
                minimumWords: 1,
                maxContextLength: 2000,  // Smaller context for local LLM
                timeoutSeconds: 60.0,    // Longer timeout for local inference
                temperature: 0.2,
                maxTokens: 256
            )
        case .apple:
            return EngineConfiguration(
                tier: .apple,
                minimumWords: 1,
                maxContextLength: 8000,
                timeoutSeconds: 30.0,
                temperature: 0.3,
                maxTokens: 2000
            )
        case .external:
            return EngineConfiguration(
                tier: .external,
                minimumWords: 1,
                maxContextLength: 16000,
                timeoutSeconds: 30.0,
                temperature: 0.3,
                maxTokens: 2000
            )
        }
    }
}

// MARK: - Helper Extensions

extension SummarizationEngine {
    
    /// Get display-friendly status string
    public func statusDescription() async -> String {
        let available = await isAvailable()
        return available ? "Available" : "Unavailable"
    }
    
    /// Get engine icon for UI display
    public var icon: String {
        switch tier {
        case .basic: return "bolt.fill"
        case .local: return "cpu"
        case .apple: return "apple.intelligence"
        case .external: return "network"
        }
    }
}

// MARK: - JSON Encoding Helpers

extension SessionIntelligence {
    
    /// Convert topics array to JSON string for database storage
    public func topicsJSON() throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(topics)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SummarizationError.encodingFailed("Failed to encode topics to JSON string")
        }
        return json
    }
    
    /// Convert entities array to JSON string for database storage
    public func entitiesJSON() throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(entities)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SummarizationError.encodingFailed("Failed to encode entities to JSON string")
        }
        return json
    }
}

extension PeriodIntelligence {
    
    /// Convert topics array to JSON string for database storage
    public func topicsJSON() throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(topics)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SummarizationError.encodingFailed("Failed to encode topics to JSON string")
        }
        return json
    }
    
    /// Convert entities array to JSON string for database storage
    public func entitiesJSON() throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(entities)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SummarizationError.encodingFailed("Failed to encode entities to JSON string")
        }
        return json
    }
}

// MARK: - JSON Decoding Helpers

extension Array where Element == String {
    
    /// Decode topics from JSON string
    public static func fromTopicsJSON(_ json: String?) throws -> [String] {
        guard let json = json, !json.isEmpty else { return [] }
        guard let data = json.data(using: .utf8) else {
            throw SummarizationError.decodingFailed("Invalid JSON string")
        }
        let decoder = JSONDecoder()
        return try decoder.decode([String].self, from: data)
    }
}

extension Array where Element == Entity {
    
    /// Decode entities from JSON string
    public static func fromEntitiesJSON(_ json: String?) throws -> [Entity] {
        guard let json = json, !json.isEmpty else { return [] }
        guard let data = json.data(using: .utf8) else {
            throw SummarizationError.decodingFailed("Invalid JSON string")
        }
        let decoder = JSONDecoder()
        return try decoder.decode([Entity].self, from: data)
    }
}
