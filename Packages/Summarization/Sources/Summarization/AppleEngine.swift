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
        
        // Generate summary using Foundation Models
        let summaryPrompt = """
        Summarize the following transcript in 2-3 concise sentences. Focus on the main topics and key points discussed.
        
        Transcript:
        \(transcriptText.prefix(4000))
        """
        
        let summaryResponse = try await session.respond(to: summaryPrompt)
        let summary = String(summaryResponse.content)
        
        // Extract topics
        let topicsPrompt = """
        Extract 3-5 main topics from this transcript. Return only the topic names, one per line.
        
        Transcript:
        \(transcriptText.prefix(2000))
        """
        
        let topicsResponse = try await session.respond(to: topicsPrompt)
        let topics = String(topicsResponse.content)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(5)
            .map { String($0) }
        
        // Analyze sentiment (simple approach)
        let sentimentPrompt = """
        Rate the overall sentiment of this text on a scale from -1.0 (very negative) to 1.0 (very positive). 
        Return ONLY a decimal number, nothing else.
        
        Text:
        \(transcriptText.prefix(1000))
        """
        
        let sentimentResponse = try await session.respond(to: sentimentPrompt)
        let sentimentString = String(sentimentResponse.content).trimmingCharacters(in: .whitespacesAndNewlines)
        let sentiment = Double(sentimentString) ?? 0.0
        
        return SessionIntelligence(
            sessionId: sessionId,
            summary: summary,
            topics: topics,
            entities: [], // Entity extraction can be added later
            sentiment: sentiment,
            duration: duration,
            wordCount: wordCount,
            languageCodes: languageCodes,
            keyMoments: nil
        )
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
        
        // Combine session summaries for context
        let combinedSummaries = sessionSummaries
            .prefix(20) // Limit to avoid token overflow
            .map { "• \($0.summary)" }
            .joined(separator: "\n")
        
        // Generate period summary
        let periodPrompt = """
        Create a brief summary (2-3 sentences) of the following \(periodType.displayName.lowercased())'s activities based on these session summaries:
        
        \(combinedSummaries)
        
        Focus on overarching themes and patterns.
        """
        
        let summaryResponse = try await session.respond(to: periodPrompt)
        let summary = String(summaryResponse.content)
        
        // Aggregate topics from all sessions
        var topicCounts: [String: Int] = [:]
        var entityMap: [String: Entity] = [:]
        
        for session in sessionSummaries {
            for topic in session.topics {
                topicCounts[topic.lowercased(), default: 0] += 1
            }
            for entity in session.entities {
                entityMap[entity.name] = entity
            }
        }
        
        // Top topics by frequency
        let topTopics = topicCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key.capitalized }
        
        // Calculate average sentiment
        let avgSentiment = sessionSummaries.map { $0.sentiment }.reduce(0, +) / Double(sessionSummaries.count)
        
        // Sum totals
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
