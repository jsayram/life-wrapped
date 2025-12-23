//
//  BasicEngine.swift
//  Summarization
//
//  Created by Life Wrapped on 12/16/2025.
//

import Foundation
import NaturalLanguage
import SharedModels
import Storage

/// Basic summarization engine using extractive approach
/// Uses sentence scoring, keyword extraction, and sentiment analysis
public actor BasicEngine: SummarizationEngine {
    
    // MARK: - Protocol Properties
    
    public let tier: EngineTier = .basic
    
    // MARK: - Private Properties
    
    private let storage: DatabaseManager
    private let config: EngineConfiguration
    
    // MARK: - Statistics
    
    private(set) var summariesGenerated: Int = 0
    private(set) var totalProcessingTime: TimeInterval = 0
    
    // MARK: - Initialization
    
    public init(storage: DatabaseManager, config: EngineConfiguration? = nil) {
        self.storage = storage
        self.config = config ?? .defaults(for: .basic)
        
        #if DEBUG
        // Run timestamp removal test on initialization in Debug builds
        print("🧪 [BasicEngine] Running timestamp removal test...")
        _ = testTimestampRemoval()
        #endif
    }
    
    // MARK: - SummarizationEngine Protocol
    
    public func isAvailable() async -> Bool {
        // Basic engine is always available - no external dependencies
        return true
    }
    
    public func summarizeSession(
        sessionId: UUID,
        transcriptText: String,
        duration: TimeInterval,
        languageCodes: [String]
    ) async throws -> SessionIntelligence {
        let startTime = Date()
        
        // Check minimum content requirement
        let wordCount = transcriptText.split(separator: " ").count
        guard wordCount >= config.minimumWords else {
            throw SummarizationError.insufficientContent(
                minimumWords: config.minimumWords,
                actualWords: wordCount
            )
        }
        
        // Truncate if exceeds max context length
        let processedText = truncateText(transcriptText, maxWords: config.maxContextLength)
        
        // Generate extractive summary
        let summaryText = try extractiveSummarize(text: processedText, maxWords: 150)
        
        // Extract topics (top keywords)
        let topics = extractKeyTopics(from: processedText, limit: 5)
        
        // Extract entities (basic implementation using NLTagger)
        let entities = extractEntities(from: processedText)
        
        // Analyze sentiment
        let sentiment = analyzeSentiment(from: processedText)
        
        // Update statistics
        let processingTime = Date().timeIntervalSince(startTime)
        summariesGenerated += 1
        totalProcessingTime += processingTime
        
        return SessionIntelligence(
            sessionId: sessionId,
            summary: summaryText,
            topics: topics,
            entities: entities,
            sentiment: sentiment,
            duration: duration,
            wordCount: wordCount,
            languageCodes: languageCodes,
            keyMoments: nil  // Basic engine doesn't generate key moments
        )
    }
    
    public func summarizePeriod(
        periodType: PeriodType,
        sessionSummaries: [SessionIntelligence],
        periodStart: Date,
        periodEnd: Date
    ) async throws -> PeriodIntelligence {
        guard !sessionSummaries.isEmpty else {
            throw SummarizationError.noTranscriptData
        }
        
        // For rollups, format as bullet-pointed list of session summaries
        let bulletedSummaries = sessionSummaries.map { intelligence -> String in
            // Use helper function to remove all timestamps
            let cleaned = removeTimestamps(from: intelligence.summary)
            return "• \(cleaned)"
        }
        
        // Join with double newlines for readability
        let summaryText = bulletedSummaries.joined(separator: "\n\n")
        
        // Aggregate topics (deduplicated and sorted by frequency)
        let allTopics = sessionSummaries.flatMap { $0.topics }
        let topics = aggregateTopics(allTopics, limit: 10)
        
        // Aggregate entities
        let allEntities = sessionSummaries.flatMap { $0.entities }
        let entities = aggregateEntities(allEntities, limit: 15)
        
        // Average sentiment
        let avgSentiment = sessionSummaries.map { $0.sentiment }.reduce(0.0, +) / Double(sessionSummaries.count)
        
        // Calculate totals
        let totalDuration = sessionSummaries.map { $0.duration }.reduce(0, +)
        let totalWords = sessionSummaries.map { $0.wordCount }.reduce(0, +)
        
        return PeriodIntelligence(
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            summary: summaryText,
            topics: topics,
            entities: entities,
            sentiment: avgSentiment,
            sessionCount: sessionSummaries.count,
            totalDuration: totalDuration,
            totalWordCount: totalWords,
            trends: nil  // Basic engine doesn't detect trends
        )
    }
    
    // MARK: - Statistics
    
    public func getStatistics() -> (summariesGenerated: Int, averageProcessingTime: TimeInterval) {
        let avgTime = summariesGenerated > 0 ? totalProcessingTime / Double(summariesGenerated) : 0
        return (summariesGenerated, avgTime)
    }
    
    public func resetStatistics() {
        summariesGenerated = 0
        totalProcessingTime = 0
    }
    
    // MARK: - Testing Helper
    
    /// Test the timestamp removal function - returns true if no timestamps remain
    public nonisolated func testTimestampRemoval() -> Bool {
        let testCases = [
            "• Dec 22, 2025 12:00 AM: • Dec 22, 2025 12:00 AM: • Dec 22, 2025 9:08 PM: OK, I'm gonna just start recording this.",
            "• Dec 22, 2025 8:47 PM: OK, so I'm gonna try to see this.",
            "Dec 22, 2025 12:00 AM: Text without bullet",
            "• Dec 1, 2025 12:00 AM: Some text here"
        ]
        
        print("🧪 [BasicEngine] Testing timestamp removal:")
        var allPassed = true
        
        for (index, test) in testCases.enumerated() {
            let cleaned = removeTimestamps(from: test)
            let hasTimestamp = cleaned.range(of: #"\d{1,2}:\d{2}\s+[AP]M"#, options: .regularExpression) != nil
            let hasBullet = cleaned.hasPrefix("•") || cleaned.hasPrefix("●")
            
            if hasTimestamp {
                print("❌ Test \(index + 1) FAILED: Timestamp remains in '\(cleaned)'")
                allPassed = false
            } else if hasBullet {
                print("⚠️  Test \(index + 1) WARNING: Bullet remains in '\(cleaned)'")
            } else {
                print("✅ Test \(index + 1) PASSED: '\(cleaned)'")
            }
        }
        
        return allPassed
    }
    
    // MARK: - Private Helper Methods
    
    /// Aggressively remove all timestamp patterns from text
    private nonisolated func removeTimestamps(from text: String) -> String {
        var cleaned = text
        
        // Step 1: Remove ALL timestamp patterns globally (one or more consecutive)
        // This pattern matches: "• Dec 22, 2025 12:00 AM: " repeated any number of times
        // Example: "• Dec 22, 2025 12:00 AM: • Dec 22, 2025 12:00 AM: text" -> "text"
        let anyTimestampPattern = #"(?:[•●]?\s*[A-Za-z]+\s+\d{1,2},\s+\d{4}\s+\d{1,2}:\d{2}\s+[AP]M:\s*)+"#
        cleaned = cleaned.replacingOccurrences(of: anyTimestampPattern, with: "", options: .regularExpression)
        
        // Step 2: Safety pass - remove any remaining individual timestamps
        let singlePattern = #"[•●]?\s*[A-Za-z]+\s+\d{1,2},\s+\d{4}\s+\d{1,2}:\d{2}\s+[AP]M:\s*"#
        cleaned = cleaned.replacingOccurrences(of: singlePattern, with: "", options: .regularExpression)
        
        // Step 3: Remove leading bullets and whitespace
        cleaned = cleaned.replacingOccurrences(of: #"^[•●\s]+"#, with: "", options: .regularExpression)
        
        // Step 4: Additional cleanup - remove multiple spaces and trim
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let result = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Verification log - this will help debug if timestamps still appear
        if text.contains(":") && text.contains("AM") || text.contains("PM") {
            print("🧹 [BasicEngine] Cleaned timestamp from: '\(text.prefix(100))'")
            print("🧹 [BasicEngine] Result: '\(result.prefix(100))'")
        }
        
        return result
    }
    
    /// Truncate text to maximum word count
    private func truncateText(_ text: String, maxWords: Int) -> String {
        let words = text.split(separator: " ")
        guard words.count > maxWords else { return text }
        return words.prefix(maxWords).joined(separator: " ") + "..."
    }
    
    /// Perform extractive summarization using sentence scoring
    private func extractiveSummarize(text: String, maxWords: Int) throws -> String {
        // Split into sentences
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.split(separator: " ").count > 3 }
        
        guard !sentences.isEmpty else {
            return "No content available for summary."
        }
        
        // Calculate target number of sentences
        let avgWordsPerSentence = 15
        let maxSentences = max(1, maxWords / avgWordsPerSentence)
        
        // Score sentences
        let keywords = extractKeyTopics(from: text, limit: 10)
        let scoredSentences = sentences.enumerated().map { index, sentence in
            var score = 0.0
            
            // Position score (earlier sentences often more important)
            let positionScore = 1.0 - (Double(index) / Double(sentences.count))
            score += positionScore * 0.3
            
            // Length score (prefer medium-length sentences)
            let wordCount = sentence.split(separator: " ").count
            let lengthScore = wordCount >= 8 && wordCount <= 25 ? 1.0 : 0.5
            score += lengthScore * 0.2
            
            // Keyword presence
            let sentenceLower = sentence.lowercased()
            let keywordCount = keywords.filter { sentenceLower.contains($0) }.count
            score += Double(keywordCount) * 0.5
            
            return (sentence: sentence, score: score)
        }
        
        // Select top sentences
        let selectedSentences = scoredSentences
            .sorted { $0.score > $1.score }
            .prefix(min(maxSentences, sentences.count))
            .sorted { sentences.firstIndex(of: $0.sentence) ?? 0 < sentences.firstIndex(of: $1.sentence) ?? 0 }
            .map { $0.sentence }
        
        // Combine into summary
        var summary = selectedSentences.joined(separator: ". ")
        if !summary.isEmpty && !summary.hasSuffix(".") && !summary.hasSuffix("!") && !summary.hasSuffix("?") {
            summary += "."
        }
        
        return summary
    }
    
    /// Extract key topics using word frequency analysis
    private func extractKeyTopics(from text: String, limit: Int = 5) -> [String] {
        // Use NLTagger to extract nouns only
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        
        var nouns: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, tokenRange in
            if tag == .noun {
                let word = String(text[tokenRange]).lowercased()
                if word.count > 3 {  // Filter short words
                    nouns.append(word)
                }
            }
            return true
        }
        
        // Count frequencies
        var frequencies: [String: Int] = [:]
        for noun in nouns {
            frequencies[noun, default: 0] += 1
        }
        
        // Get top nouns by frequency
        return Array(frequencies.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key })
    }
    
    /// Extract entities using NaturalLanguage framework
    private func extractEntities(from text: String) -> [Entity] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        
        var entities: [Entity] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if let tag = tag {
                let name = String(text[tokenRange])
                let entityType = mapNLTagToEntityType(tag)
                let entity = Entity(name: name, type: entityType, confidence: 0.7)
                entities.append(entity)
            }
            return true
        }
        
        return entities.uniqueNames.prefix(10).map { name in
            entities.first(where: { $0.name == name }) ?? Entity(name: name, type: .other, confidence: 0.5)
        }
    }
    
    /// Map NLTag to EntityType
    private func mapNLTagToEntityType(_ tag: NLTag) -> EntityType {
        switch tag {
        case .personalName: return .person
        case .placeName: return .location
        case .organizationName: return .organization
        default: return .other
        }
    }
    
    /// Analyze sentiment using NaturalLanguage framework
    private func analyzeSentiment(from text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        let (tag, _) = tagger.tag(
            at: text.startIndex,
            unit: .paragraph,
            scheme: .sentimentScore
        )
        
        guard let tag = tag, let score = Double(tag.rawValue) else {
            return 0.0  // Neutral
        }
        
        return score
    }
    
    /// Aggregate topics from multiple sessions
    private func aggregateTopics(_ topics: [String], limit: Int) -> [String] {
        var frequencies: [String: Int] = [:]
        for topic in topics {
            frequencies[topic.lowercased(), default: 0] += 1
        }
        
        return Array(frequencies.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key })
    }
    
    /// Aggregate entities from multiple sessions
    private func aggregateEntities(_ entities: [Entity], limit: Int) -> [Entity] {
        // Group by name (case-insensitive)
        var grouped: [String: Entity] = [:]
        for entity in entities {
            let key = entity.name.lowercased()
            if let existing = grouped[key] {
                // Keep entity with higher confidence
                if entity.confidence > existing.confidence {
                    grouped[key] = entity
                }
            } else {
                grouped[key] = entity
            }
        }
        
        // Sort by confidence and take top N
        return Array(grouped.values.sorted { $0.confidence > $1.confidence }.prefix(limit))
    }
}
