//
//  AppleEngine.swift
//  Summarization
//
//  Created by Life Wrapped on 12/17/2025.
//

import Foundation
import SharedModels
import Storage

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence engine using on-device Foundation Models
///
/// **Requirements**:
/// - iOS 26.0+ (Foundation Models framework)
/// - Apple Intelligence enabled in Settings
/// - Compatible hardware (A17 Pro / M1 or later)
///
/// This engine uses Apple's on-device large language model to generate
/// summaries, extract topics/entities, and analyze sentiment.
/// It uses the same UniversalPrompt system as ExternalAPIEngine for consistency.
@available(iOS 26.0, macOS 26.0, *)
public actor AppleEngine: SummarizationEngine {
    
    // MARK: - Properties
    
    private let storage: DatabaseManager
    
    // Statistics tracking (actor-isolated for thread safety)
    private var summariesGenerated: Int = 0
    private var totalProcessingTime: TimeInterval = 0.0
    
    #if canImport(FoundationModels)
    // Language model session for conversations
    private var session: LanguageModelSession?
    #endif
    
    // MARK: - Initialization
    
    public init(storage: DatabaseManager) {
        self.storage = storage
    }
    
    // MARK: - SummarizationEngine Protocol
    
    public nonisolated var tier: EngineTier {
        .apple
    }
    
    public func isAvailable() async -> Bool {
        #if canImport(FoundationModels)
        // Check if the system language model is available
        let availability = SystemLanguageModel.default.availability
        switch availability {
        case .available:
            return true
        case .unavailable:
            #if DEBUG
            print("⚠️ [AppleEngine] Apple Intelligence is unavailable on this device")
            #endif
            return false
        @unknown default:
            return false
        }
        #else
        // Foundation Models framework not available (older iOS)
        return false
        #endif
    }
    
    public func summarizeSession(
        sessionId: UUID,
        transcriptText: String,
        duration: TimeInterval,
        languageCodes: [String]
    ) async throws -> SessionIntelligence {
        
        let startTime = Date()
        defer {
            let elapsed = Date().timeIntervalSince(startTime)
            totalProcessingTime += elapsed
            summariesGenerated += 1
        }
        
        #if canImport(FoundationModels)
        // Create or reuse session
        if session == nil {
            session = LanguageModelSession()
        }
        
        guard let session = session else {
            throw SummarizationError.summarizationFailed("Failed to create language model session")
        }
        
        // Calculate word count
        let wordCount = transcriptText.split(separator: " ").count
        
        // Use UniversalPrompt for consistency with External API
        let messages = UniversalPrompt.buildMessages(
            level: .session,
            input: transcriptText,
            metadata: [
                "duration": "\(Int(duration))s",
                "wordCount": wordCount
            ]
        )
        
        // Combine system and user message for Foundation Models
        // Apple's Foundation Models doesn't have separate system/user - we combine them
        let fullPrompt = """
        \(messages.system)
        
        \(messages.user)
        """
        
        #if DEBUG
        print("🍎 [AppleEngine] Sending session summarization request")
        print("   └─ Input length: \(transcriptText.count) chars, \(wordCount) words")
        #endif
        
        let response = try await session.respond(to: fullPrompt)
        let responseText = String(response.content)
        
        #if DEBUG
        print("🍎 [AppleEngine] Response received: \(responseText.prefix(200))...")
        #endif
        
        // Parse JSON response (same format as External API)
        let parsed = parseSessionResponse(responseText, sessionId: sessionId, duration: duration, wordCount: wordCount, languageCodes: languageCodes)
        return parsed
        
        #else
        // Fallback for older iOS - use basic extractive summary
        let wordCount = transcriptText.split(separator: " ").count
        let summary = generateBasicSummary(text: transcriptText)
        let topics = extractBasicTopics(text: transcriptText)
        
        return SessionIntelligence(
            sessionId: sessionId,
            summary: summary,
            topics: topics,
            entities: [],
            sentiment: 0.0,
            duration: duration,
            wordCount: wordCount,
            languageCodes: languageCodes,
            keyMoments: nil
        )
        #endif
    }
    
    public func summarizePeriod(
        periodType: PeriodType,
        sessionSummaries: [SessionIntelligence],
        periodStart: Date,
        periodEnd: Date,
        categoryContext: String? = nil
    ) async throws -> PeriodIntelligence {
        
        guard !sessionSummaries.isEmpty else {
            throw SummarizationError.insufficientContent(minimumWords: 1, actualWords: 0)
        }
        
        let startTime = Date()
        defer {
            let elapsed = Date().timeIntervalSince(startTime)
            totalProcessingTime += elapsed
            summariesGenerated += 1
        }
        
        #if canImport(FoundationModels)
        // Create or reuse session
        if session == nil {
            session = LanguageModelSession()
        }
        
        guard let session = session else {
            throw SummarizationError.summarizationFailed("Failed to create language model session")
        }
        
        // Build input from session summaries (same as External API)
        let combinedSummaries = sessionSummaries
            .prefix(30) // Limit to avoid token overflow (Apple model has smaller context)
            .enumerated()
            .map { index, session in
                """
                Session \(index + 1):
                - Summary: \(session.summary)
                - Topics: \(session.topics.joined(separator: ", "))
                - Duration: \(Int(session.duration))s
                """
            }
            .joined(separator: "\n\n")
        
        // Use UniversalPrompt for consistency
        let level = SummaryLevel.from(periodType: periodType)
        let messages = UniversalPrompt.buildMessages(
            level: level,
            input: combinedSummaries,
            metadata: [
                "sessionCount": sessionSummaries.count,
                "periodType": periodType.displayName,
                "periodStart": ISO8601DateFormatter().string(from: periodStart),
                "periodEnd": ISO8601DateFormatter().string(from: periodEnd)
            ],
            categoryContext: categoryContext
        )
        
        // Combine system and user message
        let fullPrompt = """
        \(messages.system)
        
        \(messages.user)
        """
        
        #if DEBUG
        print("🍎 [AppleEngine] Sending \(periodType.displayName) summarization request")
        print("   └─ Sessions: \(sessionSummaries.count), Level: \(level.rawValue)")
        #endif
        
        let response = try await session.respond(to: fullPrompt)
        let responseText = String(response.content)
        
        #if DEBUG
        print("🍎 [AppleEngine] Response received: \(responseText.prefix(200))...")
        #endif
        
        // Parse JSON response
        let parsed = parsePeriodResponse(
            responseText,
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            sessionSummaries: sessionSummaries
        )
        return parsed
        
        #else
        // Fallback aggregation for older iOS
        let aggregatedSummary = sessionSummaries.map { $0.summary }.joined(separator: " ")
        let summary = "Period summary covering \(sessionSummaries.count) sessions. " +
                     String(aggregatedSummary.prefix(200))
        
        var topicCounts: [String: Int] = [:]
        var entityMap: [String: Entity] = [:]
        
        for session in sessionSummaries {
            for topic in session.topics {
                topicCounts[topic, default: 0] += 1
            }
            for entity in session.entities {
                entityMap[entity.name] = entity
            }
        }
        
        let topTopics = topicCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
        
        let avgSentiment = sessionSummaries.map { $0.sentiment }.reduce(0, +) / Double(sessionSummaries.count)
        let totalDuration = sessionSummaries.reduce(0) { $0 + $1.duration }
        let totalWords = sessionSummaries.reduce(0) { $0 + $1.wordCount }
        
        return PeriodIntelligence(
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            summary: summary,
            topics: Array(topTopics),
            entities: Array(entityMap.values),
            sentiment: avgSentiment,
            sessionCount: sessionSummaries.count,
            totalDuration: totalDuration,
            totalWordCount: totalWords
        )
        #endif
    }
    
    // MARK: - JSON Parsing (same as External API)
    
    private func parseSessionResponse(
        _ responseText: String,
        sessionId: UUID,
        duration: TimeInterval,
        wordCount: Int,
        languageCodes: [String]
    ) -> SessionIntelligence {
        // Try to parse JSON response
        guard let jsonData = responseText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            // Fallback: use response as plain text summary
            return SessionIntelligence(
                sessionId: sessionId,
                summary: responseText.trimmingCharacters(in: .whitespacesAndNewlines),
                topics: [],
                entities: [],
                sentiment: 0.0,
                duration: duration,
                wordCount: wordCount,
                languageCodes: languageCodes,
                keyMoments: nil
            )
        }
        
        // Extract fields from JSON (matching UniversalPrompt session schema)
        let title = json["title"] as? String ?? ""
        let summary = json["summary"] as? String ?? responseText
        let keyPoints = json["key_points"] as? [String] ?? []
        
        // Use key_points as topics if available
        let topics = keyPoints.isEmpty ? extractBasicTopics(text: summary) : keyPoints
        
        return SessionIntelligence(
            sessionId: sessionId,
            summary: title.isEmpty ? summary : "[\(title)] \(summary)",
            topics: topics,
            entities: [],
            sentiment: 0.0,
            duration: duration,
            wordCount: wordCount,
            languageCodes: languageCodes,
            keyMoments: nil
        )
    }
    
    private func parsePeriodResponse(
        _ responseText: String,
        periodType: PeriodType,
        periodStart: Date,
        periodEnd: Date,
        sessionSummaries: [SessionIntelligence]
    ) -> PeriodIntelligence {
        // Calculate totals
        let avgSentiment = sessionSummaries.map { $0.sentiment }.reduce(0, +) / Double(max(sessionSummaries.count, 1))
        let totalDuration = sessionSummaries.reduce(0) { $0 + $1.duration }
        let totalWords = sessionSummaries.reduce(0) { $0 + $1.wordCount }
        
        // Try to parse JSON response
        guard let jsonData = responseText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            // Fallback: use response as plain text summary
            return PeriodIntelligence(
                periodType: periodType,
                periodStart: periodStart,
                periodEnd: periodEnd,
                summary: responseText.trimmingCharacters(in: .whitespacesAndNewlines),
                topics: [],
                entities: [],
                sentiment: avgSentiment,
                sessionCount: sessionSummaries.count,
                totalDuration: totalDuration,
                totalWordCount: totalWords
            )
        }
        
        // Extract fields based on period type (matching UniversalPrompt schemas)
        let summary: String
        let topics: [String]
        
        switch periodType {
        case .day:
            summary = json["daily_summary"] as? String ?? responseText
            topics = json["top_topics"] as? [String] ?? []
        case .week:
            summary = json["weekly_summary"] as? String ?? responseText
            topics = json["top_patterns"] as? [String] ?? []
        case .month:
            summary = json["month_summary"] as? String ?? responseText
            topics = json["recurring_themes"] as? [String] ?? []
        case .year, .yearWrap, .yearWrapWork, .yearWrapPersonal:
            summary = json["year_summary"] as? String ?? responseText
            topics = json["major_arcs"] as? [String] ?? (json["top_worked_on_topics"] as? [[String: String]])?.compactMap { $0["text"] } ?? []
        default:
            summary = responseText
            topics = []
        }
        
        return PeriodIntelligence(
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            summary: summary,
            topics: topics,
            entities: [],
            sentiment: avgSentiment,
            sessionCount: sessionSummaries.count,
            totalDuration: totalDuration,
            totalWordCount: totalWords
        )
    }
    
    // MARK: - Performance Monitoring
    
    public func getStatistics() async -> (summariesGenerated: Int, averageTime: TimeInterval, totalTime: TimeInterval) {
        let average = summariesGenerated > 0 ? totalProcessingTime / Double(summariesGenerated) : 0.0
        return (summariesGenerated, average, totalProcessingTime)
    }
    
    public func logPerformanceMetrics() async {
        let stats = await getStatistics()
        #if DEBUG
        print("📊 [AppleEngine] Performance Metrics:")
        print("   - Summaries Generated: \(stats.summariesGenerated)")
        print("   - Average Processing Time: \(String(format: "%.2f", stats.averageTime))s")
        print("   - Total Processing Time: \(String(format: "%.2f", stats.totalTime))s")
        #endif
    }
    
    // MARK: - Basic Fallback Methods
    
    private func generateBasicSummary(text: String) -> String {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return sentences.prefix(3).joined(separator: ". ") + "."
    }
    
    private func extractBasicTopics(text: String) -> [String] {
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 4 }
        
        let wordCounts = Dictionary(grouping: words, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        return wordCounts.prefix(5).map { $0.key }
    }
}

// MARK: - Fallback for iOS 18.1-25.x (placeholder)

/// Legacy Apple Engine for iOS 18.1-25.x
/// Apple Intelligence was available but without public programmatic API
@available(iOS 18.1, *)
public actor AppleEngineLegacy: SummarizationEngine {
    
    private let storage: DatabaseManager
    private var summariesGenerated: Int = 0
    private var totalProcessingTime: TimeInterval = 0.0
    
    public init(storage: DatabaseManager) {
        self.storage = storage
    }
    
    public nonisolated var tier: EngineTier {
        .apple
    }
    
    public func isAvailable() async -> Bool {
        // Apple Intelligence was available on iOS 18.1+ but without public API
        // Return false since we can't actually use it programmatically until iOS 26
        return false
    }
    
    public func summarizeSession(
        sessionId: UUID,
        transcriptText: String,
        duration: TimeInterval,
        languageCodes: [String]
    ) async throws -> SessionIntelligence {
        throw SummarizationError.summarizationFailed("Apple Intelligence API requires iOS 26.0+. Please use Local AI or External API instead.")
    }
    
    public func summarizePeriod(
        periodType: PeriodType,
        sessionSummaries: [SessionIntelligence],
        periodStart: Date,
        periodEnd: Date,
        categoryContext: String? = nil
    ) async throws -> PeriodIntelligence {
        throw SummarizationError.summarizationFailed("Apple Intelligence API requires iOS 26.0+. Please use Local AI or External API instead.")
    }
    
    public func getStatistics() async -> (summariesGenerated: Int, averageTime: TimeInterval, totalTime: TimeInterval) {
        return (0, 0, 0)
    }
    
    public func logPerformanceMetrics() async {}
}
