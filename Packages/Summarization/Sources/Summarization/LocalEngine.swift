//
//  LocalEngine.swift
//  Summarization
//
//  Created by Life Wrapped on 12/22/2025.
//

import Foundation
import SharedModels
import LocalLLM
import CryptoKit

/// Smart tier: on-device summarization with a local model (Qwen3 4B, or Qwen3 1.7B on 4 GB phones; 4-bit, run with MLX).
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
    
    // Track per-chunk AI summaries with hashing for smart regeneration
    private var chunkSummaries: [UUID: String] = [:]
    private var chunkHashes: [UUID: String] = [:]  // Hash of transcript text for each chunk
    private var chunkOrder: [UUID] = []  // Maintain insertion order for correct aggregation
    
    /// The model Smart runs
    private static let model = LocalModelType.current
    
    // MARK: - Initialization
    
    public init(
        configuration: EngineConfiguration? = nil
    ) {
        self.configuration = configuration ?? EngineConfiguration(tier: .local)
        self.llamaContext = LlamaContext()
        self.modelFileManager = ModelFileManager()
        
        #if DEBUG
        print("ℹ️ [LocalEngine] Using character-based token estimation (conservative) - MLX tokenizer not available. Formula: chars ÷ 3.5")
        #endif
    }
    
    // MARK: - Token Estimation Utilities
    
    /// Estimate token count for text using conservative character-based formula
    /// Over-estimates to trigger more chunking, ensuring safety within token limits
    /// Note: the tokenizer lives inside the MLX model container, so counts are estimated from characters
    private func estimateTokenCount(_ text: String) -> Int {
        // Conservative estimate: 1 token ≈ 3.5 characters for English text
        // Over-estimating is safer than under-estimating (triggers more chunking)
        return Int(Double(text.count) / 3.5)
    }

    
    // MARK: - SummarizationEngine Protocol
    
    /// Check if local AI is available (model downloaded and ready)
    public func isAvailable() async -> Bool {
        // A model downloaded by an earlier version on a phone that can't run it doesn't count
        guard Self.isSupportedOnThisDevice else { return false }
        return await modelFileManager.isModelDownloaded(Self.model)
    }
    
    /// Check if the model is loaded and ready for inference
    public func isModelLoaded() async -> Bool {
        return await llamaContext.isReady()
    }
    
    /// Load the model into memory
    public func loadModel() async throws {
        try await llamaContext.loadModel(Self.model)
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
        
        // Compute hash of transcript text for smart regeneration
        let textHash = computeHash(of: transcriptText)
        
        // Check if we already have a cached summary for this exact text
        if let cachedHash = chunkHashes[chunkId],
           cachedHash == textHash,
           let cachedSummary = chunkSummaries[chunkId] {
            #if DEBUG
            print("✅ [LocalEngine] Using cached summary for chunk \(chunkId) (text unchanged)")
            #endif
            return cachedSummary
        }
        
        // Ensure model is loaded
        if !(await llamaContext.isReady()) {
            #if DEBUG
            print("📥 [LocalEngine] Model not loaded, loading now...")
            #endif
            try await loadModel()
        }
        
        // Clean-up prompt: instructions as the system message, transcript as the user message
        let cleanupPrompt = buildCleanupPrompt(text: transcriptText)
        
        // Generate summary with error handling
        let summary: String
        do {
            // The cleaned text is about as long as the transcript, so the limit scales with it
            let rawSummary = try await llamaContext.generate(
                system: cleanupPrompt.system,
                prompt: cleanupPrompt.user,
                maxTokens: cleanupTokenLimit(for: transcriptText)
            )
            
            // Post-process: aggressively strip any meta-commentary patterns
            summary = cleanupMetaCommentary(rawSummary)
            
            #if DEBUG
            print("✅ [LocalEngine] Chunk \(chunkId) summarized: \(summary.prefix(60))...")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [LocalEngine] MLX generation failed: \(error)")
            #endif
            #if DEBUG
            print("🔄 [LocalEngine] Falling back to extractive summary")
            #endif
            summary = extractiveSummary(from: transcriptText)
        }
        
        // Cache the chunk summary with its hash
        chunkSummaries[chunkId] = summary
        chunkHashes[chunkId] = textHash
        if !chunkOrder.contains(chunkId) {
            chunkOrder.append(chunkId)
        }
        chunksProcessed += 1
        
        let processingTime = Date().timeIntervalSince(startTime)
        totalProcessingTime += processingTime
        
        #if DEBUG
        print("🤖 [LocalEngine] Chunk \(chunkId) processed in \(String(format: "%.2f", processingTime))s")
        print("   - Input: \(transcriptText.prefix(50))...")
        print("   - Output: \(summary.prefix(100))...")
        #endif
        
        return summary
    }
    
    /// Get the cached summary for a chunk
    public func getChunkSummary(chunkId: UUID) -> String? {
        return chunkSummaries[chunkId]
    }
    
    
    // MARK: - Meta-Commentary Cleanup
    
    /// Aggressively strip meta-commentary patterns from model output
    /// Model sometimes adds "(Note: ...)" or explanatory paragraphs despite instructions
    private func cleanupMetaCommentary(_ text: String) -> String {
        var cleaned = text
        
        // Pattern 0: Remove surrounding quotes if the entire text is wrapped
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        
        // Pattern 1: Remove "(no changes...)" or "(no filler words...)" explanations
        let noChangesPattern = #"\(no changes.*?\)"#
        if let noChangesRegex = try? NSRegularExpression(pattern: noChangesPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = noChangesRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        
        // Pattern 2: Remove "(Note: ...)" with any content inside
        // Use non-greedy matching to handle multiple notes
        let notePattern = #"\(Note:.*?\)"#
        if let noteRegex = try? NSRegularExpression(pattern: notePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = noteRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        
        // Pattern 3: Remove sentences starting with "Note:" or "Note that"
        let noteSentencePattern = #"Note(:| that).*?[.!?]"#
        if let noteSentenceRegex = try? NSRegularExpression(pattern: noteSentencePattern, options: [.caseInsensitive]) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = noteSentenceRegex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        
        // Pattern 4: Remove whole explanatory sentences the model sometimes adds.
        // Only full model-speak sentences are removed. Short phrases like "grammar issues" used to be
        // removed anywhere, which also deleted them from what the person actually said.
        let explanatorySentences = [
            "The transcript has been cleaned up for clarity",
            "The above response removes filler words",
            "Filler words have been removed",
            "This is a cleaned-up version"
        ]
        for phrase in explanatorySentences {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: "", options: [.caseInsensitive])
        }
        
        // Pattern 4b: Remove a label at the very start ("Cleaned transcript:", "Summary:")
        cleaned = cleaned.replacingOccurrences(
            of: #"^\s*(Cleaned transcript|Summary)\s*:\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Pattern 5: Remove lines that are purely parenthetical notes or explanations
        let lines = cleaned.components(separatedBy: .newlines)
        let filteredLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep line if it doesn't match note patterns or explanatory patterns
            return !trimmed.hasPrefix("(Note") 
                && !trimmed.hasPrefix("Note:") 
                && !trimmed.hasPrefix("(no changes")
                && !(trimmed.hasPrefix("(") && trimmed.contains("no filler words"))
        }
        cleaned = filteredLines.joined(separator: "\n")
        
        // Final cleanup: trim excessive whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Collapse multiple spaces/newlines
        cleaned = cleaned.replacingOccurrences(of: #"\n\n+"#, with: "\n\n", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"  +"#, with: " ", options: .regularExpression)
        
        // Remove any remaining quotes at start/end after cleanup
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        
        // Debug logging if cleanup occurred
        if cleaned != text {
            #if DEBUG
            print("🧹 [LocalEngine] Stripped meta-commentary:")
            #endif
            #if DEBUG
            print("   Before: \(text.prefix(150))...")
            #endif
            #if DEBUG
            print("   After: \(cleaned.prefix(150))...")
            #endif
        }
        
        return cleaned
    }
    
    /// Clear cached chunk summaries for a session (old method - clears all)

    public func clearChunkSummaries(for chunkIds: [UUID]) {
        #if DEBUG
        print("🗑️ [LocalEngine] Clearing ALL \(chunkIds.count) cached chunk summaries")
        #endif
        for id in chunkIds {
            chunkSummaries.removeValue(forKey: id)
            chunkHashes.removeValue(forKey: id)
        }
    }
    
    /// Smart clear: Only clear chunks whose transcript has changed
    /// Returns the IDs of chunks that need reprocessing
    public func clearChangedChunkSummaries(for chunks: [(id: UUID, text: String)]) -> [UUID] {
        var changedChunkIds: [UUID] = []
        
        for chunk in chunks {
            let newHash = computeHash(of: chunk.text)
            
            // Check if hash changed or chunk is new
            if let existingHash = chunkHashes[chunk.id] {
                if existingHash != newHash {
                    // Text changed - clear cache
                    #if DEBUG
                    print("🔄 [LocalEngine] Chunk \(chunk.id) text changed, clearing cache")
                    #endif
                    chunkSummaries.removeValue(forKey: chunk.id)
                    chunkHashes.removeValue(forKey: chunk.id)
                    changedChunkIds.append(chunk.id)
                } else {
                    #if DEBUG
                    print("✅ [LocalEngine] Chunk \(chunk.id) text unchanged, keeping cached summary")
                    #endif
                }
            } else {
                // New chunk - needs processing
                #if DEBUG
                print("🆕 [LocalEngine] Chunk \(chunk.id) is new, needs processing")
                #endif
                changedChunkIds.append(chunk.id)
            }
        }
        
        #if DEBUG
        print("📊 [LocalEngine] Smart clear: \(changedChunkIds.count) of \(chunks.count) chunks need reprocessing")
        #endif
        return changedChunkIds
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
        
        // Get cached chunk summaries IN ORDER
        var aggregatedSummaries: [String] = []
        
        if !chunkIds.isEmpty {
            // Use provided chunk IDs in order
            for chunkId in chunkIds {
                if let cachedSummary = chunkSummaries[chunkId] {
                    aggregatedSummaries.append(cachedSummary)
                }
            }
        } else {
            // No specific chunk IDs provided - use insertion order from chunkOrder array
            for chunkId in chunkOrder {
                if let cachedSummary = chunkSummaries[chunkId] {
                    aggregatedSummaries.append(cachedSummary)
                }
            }
        }
        
        // If we have cached chunk summaries, aggregate them
        // Otherwise, intelligently chunk and process the full transcript
        let finalSummary: String
        
        // Check if we should use cached summaries or re-chunk
        let shouldUseCache = !aggregatedSummaries.isEmpty && (
            // Either we have all requested chunks cached...
            (!chunkIds.isEmpty && aggregatedSummaries.count == chunkIds.count) ||
            // ...or we have all chunks in order cached
            (chunkIds.isEmpty && aggregatedSummaries.count == chunkOrder.count)
        )
        
        if shouldUseCache {
            // Combine cached chunk summaries into final summary with deduplication
            #if DEBUG
            print("✅ [LocalEngine] Using \(aggregatedSummaries.count) cached chunk summaries (all cached, skipping re-chunking)")
            #endif
            finalSummary = aggregateSummaries(aggregatedSummaries)
        } else {
            // No cached summaries - intelligently chunk the transcript and process each
            #if DEBUG
            print("🔄 [LocalEngine] No cached summaries found - intelligently chunking transcript for processing")
            #endif
            #if DEBUG
            print("📊 [LocalEngine] Total words: \(wordCount), will chunk into ~120-word segments")
            #endif
            
            // Ensure model is loaded before processing
            if !(await llamaContext.isReady()) {
                #if DEBUG
                print("📥 [LocalEngine] Model not loaded, loading now...")
                #endif
                do {
                    try await llamaContext.loadModel(Self.model)
                    #if DEBUG
                    print("✅ [LocalEngine] Model loaded successfully")
                    #endif
                } catch let error {
                    #if DEBUG
                    print("❌ [LocalEngine] Failed to load model: \(error), using extractive fallback")
                    #endif
                    finalSummary = extractiveSummary(from: transcriptText)
                    // Continue with the rest of the method...
                    let topics = extractTopics(from: finalSummary)
                    let sentiment = analyzeSentiment(from: transcriptText)
                    let entities = extractEntities(from: transcriptText)
                    
                    let processingTime = Date().timeIntervalSince(startTime)
                    summariesGenerated += 1
                    totalProcessingTime += processingTime
                    
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
            }
            
            // Chunk the transcript intelligently (aim for ~120 words per chunk, ~60 seconds at 2 words/sec)
            let words = transcriptText.split(separator: " ")
            let chunkSize = 120  // ~60 seconds of speech at 2 words/sec
            var chunkSummaries: [String] = []
            
            // Process in chunks
            var currentIndex = 0
            var chunkNumber = 1
            while currentIndex < words.count {
                let endIndex = min(currentIndex + chunkSize, words.count)
                let chunkWords = words[currentIndex..<endIndex]
                let chunkText = chunkWords.joined(separator: " ")
                
                #if DEBUG
                print("🧩 [LocalEngine] Processing chunk \(chunkNumber): words \(currentIndex+1)-\(endIndex) of \(words.count)")
                #endif
                
                // Generate summary with error handling
                let chunkSummary: String
                do {
                    let cleanupPrompt = buildCleanupPrompt(text: chunkText)
                    let rawSummary = try await llamaContext.generate(
                        system: cleanupPrompt.system,
                        prompt: cleanupPrompt.user,
                        maxTokens: cleanupTokenLimit(for: chunkText)
                    )
                    
                    // Post-process: aggressively strip any meta-commentary patterns
                    chunkSummary = cleanupMetaCommentary(rawSummary)
                    
                    #if DEBUG
                    print("✅ [LocalEngine] Chunk \(chunkNumber) summarized: \(chunkSummary.prefix(60))...")
                    #endif
                } catch let error {
                    #if DEBUG
                    print("⚠️ [LocalEngine] MLX generation failed for chunk \(chunkNumber): \(error)")
                    #endif
                    #if DEBUG
                    print("🔄 [LocalEngine] Falling back to extractive summary for chunk")
                    #endif
                    chunkSummary = extractiveSummary(from: chunkText)
                }
                chunkSummaries.append(chunkSummary)
                
                currentIndex = endIndex
                chunkNumber += 1
            }
            
            // Aggregate all chunk summaries
            #if DEBUG
            print("🔗 [LocalEngine] Aggregating \(chunkSummaries.count) chunk summaries")
            #endif
            finalSummary = aggregateSummaries(chunkSummaries)
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
    
    /// Summarize a time period using LLM for Year Wrap, basic aggregation for others
    public func summarizePeriod(
        periodType: PeriodType,
        sessionSummaries: [SessionIntelligence],
        periodStart: Date,
        periodEnd: Date,
        categoryContext: String? = nil
    ) async throws -> PeriodIntelligence {
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
        
        // Period rollups are simple aggregation (BasicEngine style).
        // Year Wrap is built from month digests by YearWrapBuilder.
        return aggregatePeriodSummaries(
            periodType: periodType,
            sessionSummaries: sessionSummaries,
            periodStart: periodStart,
            periodEnd: periodEnd
        )
    }
    
    /// Aggregate period summaries (for non-Year Wrap periods)
    private func aggregatePeriodSummaries(
        periodType: PeriodType,
        sessionSummaries: [SessionIntelligence],
        periodStart: Date,
        periodEnd: Date
    ) -> PeriodIntelligence {
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
        
        // Clean and deduplicate summaries while preserving order
        var cleanedSummaries: [String] = []
        var seenSentences: Set<String> = []
        
        for summary in summaries {
            // Split into sentences to check for duplicates at sentence level
            let sentences = summary.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            var uniqueSentences: [String] = []
            for sentence in sentences {
                let normalized = sentence.lowercased()
                // Only add if we haven't seen a very similar sentence
                if !seenSentences.contains(where: { existing in
                    // Check for substantial overlap (>70% similarity)
                    let commonWords = Set(existing.split(separator: " ")).intersection(Set(normalized.split(separator: " ")))
                    let similarity = Double(commonWords.count) / Double(max(existing.split(separator: " ").count, normalized.split(separator: " ").count))
                    return similarity > 0.7
                }) {
                    uniqueSentences.append(sentence)
                    seenSentences.insert(normalized)
                }
            }
            
            if !uniqueSentences.isEmpty {
                cleanedSummaries.append(uniqueSentences.joined(separator: ". "))
            }
        }
        
        // Join all unique summaries
        let combined = cleanedSummaries.joined(separator: ". ")
        return combined.isEmpty ? "Recording captured." : (combined.hasSuffix(".") ? combined : combined + ".")
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
    
    /// Compute hash of text for smart caching
    private func computeHash(of text: String) -> String {
        let data = Data(text.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Clean-up prompt for one chunk of transcript.
    /// Returned as two parts: the instructions go in the system message, the transcript in the user message.
    /// The model's chat template adds its own tags, so none are written here.
    private func buildCleanupPrompt(text: String) -> (system: String, user: String) {
        let system = """
        You clean up voice recordings. Output ONLY the cleaned text directly. Never wrap in quotes. Never add explanations.
        """
        let user = """
        Clean up this voice recording transcript:
        - Remove filler words (um, uh, like, you know)
        - Fix obvious grammar issues
        - Keep the original meaning and tone
        - Preserve first-person perspective
        
        CRITICAL RULES:
        1. Output the cleaned text directly
        2. NO quotes around the output
        3. NO explanations about what you changed or didn't change
        4. NO meta-commentary like "(no changes...)"
        5. If the text is already clean, just output it as-is

        WRONG:
        "I went to the store."
        "Text here" (no changes as there are no filler words...)
        I went to the store. (Note: cleaned for clarity)

        CORRECT:
        I went to the store.
        I'm thinking about what to eat for dinner.

        Transcript:
        \(text)
        """
        return (system, user)
    }
    
    /// Output limit for cleaning up a piece of transcript.
    /// The cleaned text is about as long as the original, so a fixed small limit cut longer parts off
    /// mid-sentence. Allow 30% more than the estimated input, between 128 and 1,024 tokens.
    private func cleanupTokenLimit(for text: String) -> Int32 {
        let estimated = estimateTokenCount(text) * 13 / 10 + 32
        return Int32(min(max(estimated, 128), 1024))
    }
    
    /// Check if the local AI model is downloaded
    public func isModelDownloaded() async -> Bool {
        return await modelFileManager.isModelDownloaded(Self.model)
    }
    
    /// Download the local AI model with progress tracking
    /// - Parameter progress: Closure called with download progress (0.0-1.0)
    public func downloadModel(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        // Never download 2.3 GB the device can't run
        guard Self.isSupportedOnThisDevice else {
            throw LlamaError.deviceNotSupported
        }
        try await modelFileManager.downloadModel(Self.model, progress: progress)
    }
    
    /// Delete the local AI model
    public func deleteModel() async throws {
        try await modelFileManager.deleteModel(Self.model)
        // Unload from memory if loaded
        await llamaContext.unloadModel()
    }
    
    /// Delete models that earlier versions downloaded and Smart no longer uses (Phi-3.5).
    /// Safe to call on every launch; does nothing if there's nothing to remove.
    /// - Returns: true if an old model was deleted
    public func removeRetiredModels() async -> Bool {
        return await modelFileManager.deleteRetiredModels(keeping: Self.model)
    }
    
    /// Get the size of the downloaded model in bytes, or nil if not downloaded
    public func modelSizeBytes() async -> Int64? {
        return await modelFileManager.modelSize(Self.model)
    }
    
    /// Get formatted model size string: "Downloaded (2173 MB)" or "Not Downloaded"
    public func modelSizeFormatted() async -> String {
        if let size = await modelFileManager.modelSize(Self.model) {
            let sizeMB = size / (1024 * 1024)
            return "Downloaded (\(sizeMB) MB)"
        }
        return "Not Downloaded"
    }
    
    /// Download size to show before downloading, for example "~2.3 GB"
    public static var modelDownloadSize: String {
        LocalModelType.current.downloadSizeDescription
    }
    
    /// Name of the model Smart runs, for display
    public static var modelDisplayName: String {
        LocalModelType.current.displayName
    }

    /// Whether this device has enough memory to run Smart. When false, Smart isn't offered.
    public static var isSupportedOnThisDevice: Bool {
        DeviceMemory.canRun(model)
    }
    
    /// UserDefaults key set when an old model was removed and the new one hasn't been downloaded yet
    public static let modelReplacedNoticeKey = "localModelReplacedNotice"
}

// MARK: - TextGenerating

extension LocalEngine: TextGenerating {
    // 4,096-token window: about 700 for instructions, 1,900 for content, 700 for the answer
    public nonisolated var inputTokenBudget: Int { 1_900 }
    public nonisolated var outputTokenBudget: Int { 700 }

    public func generateText(system: String, user: String, maxTokens: Int) async throws -> String {
        if !(await llamaContext.isReady()) {
            try await loadModel()
        }
        let output = try await llamaContext.generate(system: system, prompt: user, maxTokens: Int32(maxTokens))
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
