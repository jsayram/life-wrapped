//
//  LocalEngine.swift
//  Summarization
//
//  Created by Life Wrapped on 12/22/2025.
//

import Foundation
import SharedModels
import LocalLLM

/// Local LLM-based summarization engine using Phi-3.5 via llama.cpp
/// Processes each chunk through the local model, then aggregates for session summary
public actor LocalEngine: SummarizationEngine {
    
    // MARK: - Protocol Properties
    
    public let tier: EngineTier = .local
    
    // MARK: - Private Properties
    
    private let configuration: EngineConfiguration
    private let llamaContext: LlamaContext
    private let modelFileManager: ModelFileManager
    
    // Statistics
    private var summariesGenerated: Int = 0
    private var totalProcessingTime: TimeInterval = 0
    private var chunksProcessed: Int = 0
    
    // Track per-chunk AI summaries
    private var chunkSummaries: [UUID: String] = [:]
    
    // MARK: - Initialization
    
    public init(
        configuration: EngineConfiguration? = nil
    ) {
        self.configuration = configuration ?? EngineConfiguration(tier: .local)
        self.llamaContext = LlamaContext()
        self.modelFileManager = ModelFileManager()
    }
    
    // MARK: - SummarizationEngine Protocol
    
    /// Check if local AI is available (model downloaded and ready)
    public func isAvailable() async -> Bool {
        // Check if model file exists
        let isDownloaded = await modelFileManager.isModelDownloaded(.phi35)
        return isDownloaded
    }
    
    /// Check if the model is loaded and ready for inference
    public func isModelLoaded() async -> Bool {
        return await llamaContext.isReady()
    }
    
    /// Load the model into memory
    public func loadModel() async throws {
        try await llamaContext.loadModel(.phi35)
    }
    
    /// Unload the model from memory
    public func unloadModel() async {
        await llamaContext.unloadModel()
    }
    
    /// Summarize an individual chunk using local AI
    /// Called after each chunk is transcribed
    public func summarizeChunk(
        chunkId: UUID,
        transcriptText: String
    ) async throws -> String {
        let startTime = Date()
        
        // Ensure model is loaded
        if !(await llamaContext.isReady()) {
            try await loadModel()
        }
        
        // Build prompt for chunk summarization
        let prompt = LocalLLM.buildChunkPrompt(transcript: transcriptText)
        
        // Generate summary
        let summary = try await llamaContext.generate(prompt: prompt, maxTokens: 128)
        
        // Cache the chunk summary
        chunkSummaries[chunkId] = summary
        chunksProcessed += 1
        
        let processingTime = Date().timeIntervalSince(startTime)
        totalProcessingTime += processingTime
        
        #if DEBUG
        print("🤖 [LocalEngine] Chunk \(chunkId) summarized in \(String(format: "%.2f", processingTime))s")
        print("   - Input: \(transcriptText.prefix(50))...")
        print("   - Output: \(summary.prefix(100))...")
        #endif
        
        return summary
    }
    
    /// Get the cached summary for a chunk
    public func getChunkSummary(chunkId: UUID) -> String? {
        return chunkSummaries[chunkId]
    }
    
    /// Clear cached chunk summaries for a session
    public func clearChunkSummaries(for chunkIds: [UUID]) {
        for id in chunkIds {
            chunkSummaries.removeValue(forKey: id)
        }
    }
    
    /// Summarize a full session by aggregating chunk summaries (protocol conformance)
    /// Uses BasicEngine-style rollup of all AI-processed chunk summaries
    public func summarizeSession(
        sessionId: UUID,
        transcriptText: String,
        duration: TimeInterval,
        languageCodes: [String]
    ) async throws -> SessionIntelligence {
        // Call the version with chunk IDs, using all cached summaries
        return try await summarizeSessionWithChunks(
            sessionId: sessionId,
            transcriptText: transcriptText,
            duration: duration,
            languageCodes: languageCodes,
            chunkIds: []
        )
    }
    
    /// Summarize a full session by aggregating chunk summaries with specific chunk IDs
    public func summarizeSessionWithChunks(
        sessionId: UUID,
        transcriptText: String,
        duration: TimeInterval,
        languageCodes: [String],
        chunkIds: [UUID]
    ) async throws -> SessionIntelligence {
        let startTime = Date()
        
        // For session summary, we expect chunk summaries to already exist
        // If called directly, fall back to processing the full text
        let wordCount = transcriptText.split(separator: " ").count
        
        // Get cached chunk summaries
        var aggregatedSummaries: [String] = []
        
        for chunkId in chunkIds {
            if let cachedSummary = chunkSummaries[chunkId] {
                aggregatedSummaries.append(cachedSummary)
            }
        }
        
        // If no specific chunk IDs provided, check all cached summaries
        if chunkIds.isEmpty {
            aggregatedSummaries = Array(chunkSummaries.values)
        }
        
        // If we have cached chunk summaries, aggregate them
        // Otherwise, generate a single summary from the full text
        let finalSummary: String
        if aggregatedSummaries.isEmpty {
            // No cached summaries - generate from full text (limited to 256 tokens)
            if await llamaContext.isReady() {
                let prompt = LocalLLM.buildChunkPrompt(transcript: String(transcriptText.prefix(2000)))
                finalSummary = try await llamaContext.generate(prompt: prompt)
            } else {
                // Model not loaded, return extractive summary
                finalSummary = extractiveSummary(from: transcriptText)
            }
        } else {
            // Combine chunk summaries into final summary
            finalSummary = aggregateSummaries(aggregatedSummaries)
        }
        
        // Extract topics from summary
        let topics = extractTopics(from: finalSummary)
        
        // Basic sentiment analysis
        let sentiment = analyzeSentiment(from: transcriptText)
        
        // Extract entities
        let entities = extractEntities(from: transcriptText)
        
        let processingTime = Date().timeIntervalSince(startTime)
        summariesGenerated += 1
        totalProcessingTime += processingTime
        
        #if DEBUG
        print("🤖 [LocalEngine] Session summary generated in \(String(format: "%.2f", processingTime))s")
        print("   - Chunks aggregated: \(aggregatedSummaries.count)")
        print("   - Summary: \(finalSummary.prefix(100))...")
        #endif
        
        return SessionIntelligence(
            sessionId: sessionId,
            summary: finalSummary,
            topics: topics,
            entities: entities,
            sentiment: sentiment,
            duration: duration,
            wordCount: wordCount,
            languageCodes: languageCodes,
            keyMoments: nil
        )
    }
    
    /// Summarize a time period using basic aggregation
    public func summarizePeriod(
        periodType: PeriodType,
        sessionSummaries: [SessionIntelligence],
        periodStart: Date,
        periodEnd: Date
    ) async throws -> PeriodIntelligence {
        // For period summaries, use simple aggregation (BasicEngine style)
        guard !sessionSummaries.isEmpty else {
            return PeriodIntelligence(
                periodType: periodType,
                periodStart: periodStart,
                periodEnd: periodEnd,
                summary: "No recordings during this period.",
                topics: [],
                entities: [],
                sentiment: 0,
                sessionCount: 0,
                totalDuration: 0,
                totalWordCount: 0,
                trends: nil
            )
        }
        
        // Aggregate session summaries
        let combinedSummaries = sessionSummaries
            .map { "• \($0.summary)" }
            .joined(separator: "\n")
        
        // Collect all topics and find most common
        var topicCounts: [String: Int] = [:]
        for session in sessionSummaries {
            for topic in session.topics {
                topicCounts[topic, default: 0] += 1
            }
        }
        let topTopics = topicCounts.sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
        
        // Calculate aggregates
        let totalDuration = sessionSummaries.reduce(0) { $0 + $1.duration }
        let totalWordCount = sessionSummaries.reduce(0) { $0 + $1.wordCount }
        let averageSentiment = sessionSummaries.reduce(0.0) { $0 + $1.sentiment } / Double(sessionSummaries.count)
        
        // Collect all entities
        var allEntities: [Entity] = []
        for session in sessionSummaries {
            allEntities.append(contentsOf: session.entities)
        }
        
        return PeriodIntelligence(
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            summary: combinedSummaries,
            topics: Array(topTopics),
            entities: allEntities,
            sentiment: averageSentiment,
            sessionCount: sessionSummaries.count,
            totalDuration: totalDuration,
            totalWordCount: totalWordCount,
            trends: nil
        )
    }
    
    // MARK: - Private Helpers
    
    /// Aggregate multiple chunk summaries into a coherent session summary
    private func aggregateSummaries(_ summaries: [String]) -> String {
        guard !summaries.isEmpty else { return "No content available." }
        
        if summaries.count == 1 {
            return summaries[0]
        }
        
        // Join summaries with proper formatting
        // Remove redundant phrases and clean up
        var cleanedSummaries: [String] = []
        var seenContent: Set<String> = []
        
        for summary in summaries {
            let normalized = summary.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip if too similar to existing summary
            if !seenContent.contains(normalized) && !summary.isEmpty {
                cleanedSummaries.append(summary)
                seenContent.insert(normalized)
            }
        }
        
        return cleanedSummaries.joined(separator: " ")
    }
    
    /// Simple extractive summary as fallback
    private func extractiveSummary(from text: String) -> String {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.split(separator: " ").count >= 5 }
        
        // Take first 3 meaningful sentences
        let selected = sentences.prefix(3).joined(separator: ". ")
        return selected.isEmpty ? "Recording captured." : selected + "."
    }
    
    /// Extract topics from text using keyword frequency
    private func extractTopics(from text: String) -> [String] {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 4 && !Self.stopWords.contains($0) }
        
        var counts: [String: Int] = [:]
        for word in words {
            counts[word, default: 0] += 1
        }
        
        return counts.sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key.capitalized }
    }
    
    /// Simple sentiment analysis
    private func analyzeSentiment(from text: String) -> Double {
        let lowered = text.lowercased()
        
        var score = 0.0
        for word in Self.positiveWords {
            if lowered.contains(word) { score += 0.1 }
        }
        for word in Self.negativeWords {
            if lowered.contains(word) { score -= 0.1 }
        }
        
        return max(-1.0, min(1.0, score))
    }
    
    /// Extract named entities
    private func extractEntities(from text: String) -> [Entity] {
        // Simple capitalized word extraction as entities
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        var entities: [Entity] = []
        
        for word in words {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            if cleaned.count > 2,
               let first = cleaned.first,
               first.isUppercase,
               !Self.commonCapitalized.contains(cleaned.lowercased()) {
                let entity = Entity(
                    name: cleaned,
                    type: .other,
                    confidence: 0.5
                )
                if !entities.contains(where: { $0.name == cleaned }) {
                    entities.append(entity)
                }
            }
        }
        
        return Array(entities.prefix(10))
    }
    
    // MARK: - Static Constants
    
    private static let stopWords: Set<String> = [
        "about", "after", "again", "being", "could", "doing", "during",
        "going", "having", "their", "there", "these", "thing", "think",
        "those", "through", "today", "would", "really", "actually", "basically"
    ]
    
    private static let positiveWords: Set<String> = [
        "good", "great", "happy", "excellent", "wonderful", "amazing",
        "love", "enjoy", "excited", "fantastic", "awesome", "pleasant"
    ]
    
    private static let negativeWords: Set<String> = [
        "bad", "terrible", "awful", "hate", "angry", "frustrated",
        "sad", "disappointed", "worried", "stressed", "annoyed", "upset"
    ]
    
    private static let commonCapitalized: Set<String> = [
        "i", "the", "a", "an", "monday", "tuesday", "wednesday",
        "thursday", "friday", "saturday", "sunday", "january", "february",
        "march", "april", "may", "june", "july", "august", "september",
        "october", "november", "december", "ok", "okay"
    ]
    
    // MARK: - Model Management
    
    /// Check if the local AI model is downloaded
    public func isModelDownloaded() async -> Bool {
        return await modelFileManager.isModelDownloaded(.phi35)
    }
    
    /// Download the local AI model with progress tracking
    /// - Parameter progress: Closure called with download progress (0.0-1.0)
    public func downloadModel(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try await modelFileManager.downloadModel(.phi35, progress: progress)
    }
    
    /// Delete the local AI model
    public func deleteModel() async throws {
        try await modelFileManager.deleteModel(.phi35)
        // Unload from memory if loaded
        await llamaContext.unloadModel()
    }
    
    /// Get the size of the downloaded model in bytes, or nil if not downloaded
    public func modelSizeBytes() async -> Int64? {
        return await modelFileManager.modelSize(.phi35)
    }
    
    /// Get formatted model size string: "Downloaded (2282 MB)" or "Not Downloaded"
    public func modelSizeFormatted() async -> String {
        if let size = await modelFileManager.modelSize(.phi35) {
            let sizeMB = size / (1024 * 1024)
            return "Downloaded (\(sizeMB) MB)"
        }
        return "Not Downloaded"
    }
    
    /// Get the expected model size for display before download
    public var expectedModelSizeMB: String {
        return "~2.3 GB"
    }
    
    /// Get the model display name
    public var modelDisplayName: String {
        return LocalModelType.phi35.displayName
    }
}
