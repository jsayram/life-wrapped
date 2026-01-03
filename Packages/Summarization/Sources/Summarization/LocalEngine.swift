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
    
    // Track per-chunk AI summaries with hashing for smart regeneration
    private var chunkSummaries: [UUID: String] = [:]
    private var chunkHashes: [UUID: String] = [:]  // Hash of transcript text for each chunk
    private var chunkOrder: [UUID] = []  // Maintain insertion order for correct aggregation
    
    // Concurrency control: Prevent simultaneous LLM generation calls
    private var isGenerating: Bool = false
    
    // MARK: - Token Estimation Constants
    
    // Phi-3.5 Mini token limits and safety margins
    private let MAX_CONTEXT_TOKENS = 2048          // Phi-3.5 Mini context window
    private let FIXED_OVERHEAD_TOKENS = 700        // System prompt + schema + rules
    private let AVAILABLE_INPUT_TOKENS = 1200      // Safe room for input summaries
    private let SAFETY_BUFFER_TOKENS = 148         // Extra margin for safety
    private let INTERMEDIATE_OUTPUT_TOKENS = 128   // For quarterly/intermediate summaries
    private let FINAL_OUTPUT_TOKENS = 256          // For final Year Wrap JSON
    private let MAX_RECURSION_DEPTH = 12           // Safety limit for pathological cases
    
    // Performance tracking for Year Wrap generation
    private var totalLLMCalls = 0
    private var maxDepthReached = 0
    private var generationStartTime: Date?
    
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
    /// Note: MLX/llama.cpp does not expose tokenizer API, so we use approximation
    private func estimateTokenCount(_ text: String) -> Int {
        // Conservative estimate: 1 token ≈ 3.5 characters for English text
        // Over-estimating is safer than under-estimating (triggers more chunking)
        return Int(Double(text.count) / 3.5)
    }
    
    /// Calculate total estimated token count for array of texts
    private func totalTokenCount(_ texts: [String]) -> Int {
        return texts.reduce(0) { $0 + estimateTokenCount($1) }
    }
    
    // MARK: - Recursive Chunking Engine
    
    /// Recursively chunk summaries into groups that fit within token limit
    /// Returns array of chunks where each chunk's total tokens ≤ maxTokens
    private func recursiveChunk(
        summaries: [SessionIntelligence],
        maxTokens: Int,
        level: Int
    ) async -> [[SessionIntelligence]] {
        var chunks: [[SessionIntelligence]] = []
        var currentChunk: [SessionIntelligence] = []
        var currentTokenCount = 0
        
        for summary in summaries {
            let summaryTokens = estimateTokenCount(summary.summary)
            
            // If adding this summary exceeds limit, start new chunk
            if currentTokenCount + summaryTokens > maxTokens && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = []
                currentTokenCount = 0
            }
            
            currentChunk.append(summary)
            currentTokenCount += summaryTokens
        }
        
        // Add final chunk if not empty
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        // Log chunking details
        #if DEBUG
        let chunkTokens = chunks.map { chunk in
            chunk.reduce(0) { $0 + estimateTokenCount($1.summary) }
        }
        let totalChars = summaries.reduce(0) { $0 + $1.summary.count }
        let totalTokens = summaries.reduce(0) { $0 + estimateTokenCount($1.summary) }
        print("🔍 [LocalEngine] Level \(level): Total \(totalTokens)t (\(totalChars)c) → \(chunks.count) chunks: \(chunkTokens.map { "\($0)t" }.joined(separator: ", "))")
        #endif
        
        return chunks
    }
    
    /// Recursively synthesize summaries with unlimited depth chunking
    /// Ensures ALL data is processed regardless of size by sub-chunking as needed
    /// ARC cleanup: Intermediate summaries released at await boundaries between recursion levels
    private func synthesizeWithRecursiveChunking(
        summaries: [SessionIntelligence],
        label: String,
        level: Int,
        categoryLabel: String
    ) async throws -> String {
        // Safety check: Prevent pathological infinite recursion
        guard level <= MAX_RECURSION_DEPTH else {
            #if DEBUG
            print("❌ [LocalEngine] EMERGENCY BAILOUT: Recursion depth \(level) exceeds safety limit (\(MAX_RECURSION_DEPTH)). Switching to basic fallback.")
            #endif
            throw NSError(
                domain: "LocalEngine",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Recursion depth exceeded safety limit"]
            )
        }
        
        // Track maximum depth reached
        maxDepthReached = max(maxDepthReached, level)
        
        // Log depth warning at level 5
        if level == 5 {
            #if DEBUG
            print("⚠️ [LocalEngine] Recursion depth \(level) reached for \(label) - this is unusually deep (not an error, diagnostic only)")
            #endif
        }
        
        // Calculate total token count for all summaries
        let summaryTexts = summaries.map { $0.summary }
        let totalTokens = totalTokenCount(summaryTexts)
        
        #if DEBUG
        print("📊 [LocalEngine] \(label) Level \(level): Processing \(summaries.count) summaries (\(totalTokens)t)")
        #endif
        
        // Base case: If all summaries fit in one generation, generate directly
        if totalTokens <= AVAILABLE_INPUT_TOKENS {
            #if DEBUG
            print("✅ [LocalEngine] \(label) Level \(level): Fits in context, generating directly")
            #endif
            
            // Build combined summaries text
            let combinedText = summaryTexts
                .map { "- \($0)" }
                .joined(separator: "\n")
            
            // Build simplified prompt for intermediate synthesis
            let prompt = buildQuarterlySummaryPrompt(
                summaries: combinedText,
                quarterLabel: label,
                categoryLabel: categoryLabel
            )
            
            // Generate with LLM
            let output = try await llamaContext.generate(prompt: prompt, maxTokens: Int32(INTERMEDIATE_OUTPUT_TOKENS))
            totalLLMCalls += 1
            
            // Cooldown after generation to prevent CPU/memory exhaustion
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            #if DEBUG
            print("✅ [LocalEngine] \(label) Level \(level): Generated \(estimateTokenCount(output))t output")
            #endif
            
            return output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        
        // Recursive case: Chunk and recursively synthesize
        #if DEBUG
        print("🔄 [LocalEngine] \(label) Level \(level): Exceeds limit, chunking required")
        #endif
        
        let chunks = await recursiveChunk(
            summaries: summaries,
            maxTokens: AVAILABLE_INPUT_TOKENS,
            level: level
        )
        
        #if DEBUG
        print("📊 [LocalEngine] \(label) Level \(level): Processing \(chunks.count) sub-groups")
        #endif
        
        // Recursively synthesize each chunk (ARC cleans up originals at await boundaries)
        var intermediates: [String] = []
        for (index, chunk) in chunks.enumerated() {
            let subLabel = "\(label)-\(index + 1)"
            
            // Convert chunk back to SessionIntelligence array for recursion
            let intermediate = try await synthesizeWithRecursiveChunking(
                summaries: chunk,
                label: subLabel,
                level: level + 1,
                categoryLabel: categoryLabel
            )
            
            intermediates.append(intermediate)
            
            // Unload model between recursive chunks to free memory (if more chunks remaining)
            if index < chunks.count - 1 {
                #if DEBUG
                print("🧹 [LocalEngine] \(label) Level \(level): Unloading model between chunks \(index + 1)/\(chunks.count)...")
                #endif
                await llamaContext.unloadModel()
                await Task.yield()
                
                // Brief cooldown between recursive chunks (500ms)
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        
        // Combine intermediates into final summary
        #if DEBUG
        let intermediateTokens = totalTokenCount(intermediates)
        print("✅ [LocalEngine] \(label) Level \(level): Combining \(intermediates.count) intermediates (\(intermediateTokens)t)")
        #endif
        
        let combinedIntermediates = intermediates
            .map { "- \($0)" }
            .joined(separator: "\n")
        
        let combinePrompt = buildQuarterlySummaryPrompt(
            summaries: combinedIntermediates,
            quarterLabel: label,
            categoryLabel: categoryLabel
        )
        
        let finalOutput = try await llamaContext.generate(prompt: combinePrompt, maxTokens: Int32(INTERMEDIATE_OUTPUT_TOKENS))
        totalLLMCalls += 1
        
        // Cooldown after generation
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        #if DEBUG
        print("✅ [LocalEngine] \(label) Level \(level): Final synthesis complete (\(estimateTokenCount(finalOutput))t)")
        #endif
        
        return finalOutput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
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
        
        // Use simplified prompt for Local AI
        let simplePrompt = buildSimplifiedPrompt(text: transcriptText)
        
        // Generate summary with error handling
        let summary: String
        do {
            // Use shorter max tokens for more concise, focused summaries
            let rawSummary = try await llamaContext.generate(prompt: simplePrompt, maxTokens: 128)
            
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
        
        // Pattern 4: Remove common explanatory phrases
        let explanatoryPhrases = [
            "The transcript has been cleaned up for clarity",
            "The above response removes filler words",
            "Filler words have been removed",
            "This is a cleaned-up version",
            "Cleaned transcript:",
            "Summary:",
            "no changes as there are no",
            "no filler words",
            "grammar issues",
            "unnecessary notes"
        ]
        for phrase in explanatoryPhrases {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: "", options: [.caseInsensitive])
        }
        
        // Pattern 5: Remove lines that are purely parenthetical notes or explanations
        let lines = cleaned.components(separatedBy: .newlines)
        let filteredLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep line if it doesn't match note patterns or explanatory patterns
            return !trimmed.hasPrefix("(Note") 
                && !trimmed.hasPrefix("Note:") 
                && !trimmed.hasPrefix("(no changes")
                && !trimmed.contains("no filler words")
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
                    try await llamaContext.loadModel(.phi35)
                    #if DEBUG
                    print("✅ [LocalEngine] Model loaded successfully")
                    #endif
                } catch {
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
                    // Use simplified prompt for Local AI (less memory intensive)
                    let simplePrompt = buildSimplifiedPrompt(text: chunkText)
                    let rawSummary = try await llamaContext.generate(prompt: simplePrompt, maxTokens: 128)
                    
                    // Post-process: aggressively strip any meta-commentary patterns
                    chunkSummary = cleanupMetaCommentary(rawSummary)
                    
                    #if DEBUG
                    print("✅ [LocalEngine] Chunk \(chunkNumber) summarized: \(chunkSummary.prefix(60))...")
                    #endif
                } catch {
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
        
        // For Year Wrap, use LLM to generate structured JSON
        if periodType == .yearWrap || periodType == .yearWrapWork || periodType == .yearWrapPersonal {
            return try await generateYearWrapWithLLM(
                periodType: periodType,
                sessionSummaries: sessionSummaries,
                periodStart: periodStart,
                periodEnd: periodEnd,
                categoryContext: categoryContext
            )
        }
        
        // For other period types, use simple aggregation (BasicEngine style)
        return aggregatePeriodSummaries(
            periodType: periodType,
            sessionSummaries: sessionSummaries,
            periodStart: periodStart,
            periodEnd: periodEnd
        )
    }
    
    /// Generate Year Wrap using LLM with simplified JSON schema
    private func generateYearWrapWithLLM(
        periodType: PeriodType,
        sessionSummaries: [SessionIntelligence],
        periodStart: Date,
        periodEnd: Date,
        categoryContext: String?
    ) async throws -> PeriodIntelligence {
        #if DEBUG
        print("🎁 [LocalEngine] === YEAR WRAP GENERATION START ===")
        print("📊 [LocalEngine] Period: \(periodType.displayName)")
        print("📊 [LocalEngine] Summaries count: \(sessionSummaries.count)")
        #endif
        
        // CRITICAL: Prevent concurrent LLM usage
        guard !isGenerating else {
            #if DEBUG
            print("❌ [LocalEngine] BLOCKED: Concurrent generation detected, failing safely")
            #endif
            throw NSError(
                domain: "LocalEngine",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Model busy - concurrent generation not allowed"]
            )
        }
        
        isGenerating = true
        defer {
            isGenerating = false
            
            // CRITICAL: Unload model at the end of each Year Wrap variant to free memory
            Task {
                await llamaContext.unloadModel()
                #if DEBUG
                print("🧹 [LocalEngine] Model unloaded at end of Year Wrap generation (cleanup)")
                #endif
            }
        }
        
        #if DEBUG
        print("✅ [LocalEngine] Generation lock acquired")
        #endif
        
        // Start performance tracking
        generationStartTime = Date()
        totalLLMCalls = 0
        maxDepthReached = 0
        
        // Calculate aggregates
        let totalDuration = sessionSummaries.reduce(0) { $0 + $1.duration }
        let totalWordCount = sessionSummaries.reduce(0) { $0 + $1.wordCount }
        let averageSentiment = sessionSummaries.reduce(0.0) { $0 + $1.sentiment } / Double(sessionSummaries.count)
        
        // Collect all topics
        var topicCounts: [String: Int] = [:]
        for session in sessionSummaries {
            for topic in session.topics {
                topicCounts[topic, default: 0] += 1
            }
        }
        let topTopics = topicCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
        
        // Collect all entities
        var allEntities: [Entity] = []
        for session in sessionSummaries {
            allEntities.append(contentsOf: session.entities)
        }
        
        // Ensure model is loaded (with crash protection)
        do {
            if !(await llamaContext.isReady()) {
                #if DEBUG
                print("📥 [LocalEngine] Model not loaded, loading for Year Wrap...")
                #endif
                try await loadModel()
                #if DEBUG
                print("✅ [LocalEngine] Model loaded successfully for Year Wrap")
                #endif
            }
        } catch let modelError {
            #if DEBUG
            print("❌ [LocalEngine] CRITICAL: Model loading failed for Year Wrap: \(modelError)")
            print("❌ [LocalEngine] Model error type: \(type(of: modelError))")
            #endif
            // Fall back to aggregation immediately if model won't load
            let fallbackJSON = buildFallbackYearWrapJSON(
                sessionSummaries: sessionSummaries,
                topTopics: topTopics,
                categoryLabel: periodType == .yearWrapWork ? "WORK" : (periodType == .yearWrapPersonal ? "PERSONAL" : "ALL")
            )
            return PeriodIntelligence(
                periodType: periodType,
                periodStart: periodStart,
                periodEnd: periodEnd,
                summary: fallbackJSON,
                topics: Array(topTopics),
                entities: allEntities,
                sentiment: averageSentiment,
                sessionCount: sessionSummaries.count,
                totalDuration: totalDuration,
                totalWordCount: totalWordCount,
                trends: nil
            )
        }
        
        // Group month summaries into quarters (every 3 summaries = 1 quarter, or less for partial years)
        #if DEBUG
        print("📅 [LocalEngine] Grouping \(sessionSummaries.count) month summaries into quarters")
        #endif
        
        var quarterGroups: [[SessionIntelligence]] = []
        var currentQuarter: [SessionIntelligence] = []
        
        for (index, summary) in sessionSummaries.enumerated() {
            currentQuarter.append(summary)
            
            // Every 3 months or at the end, complete the quarter
            if currentQuarter.count == 3 || index == sessionSummaries.count - 1 {
                quarterGroups.append(currentQuarter)
                currentQuarter = []
            }
        }
        
        #if DEBUG
        print("📊 [LocalEngine] Created \(quarterGroups.count) quarters with \(quarterGroups.map { String($0.count) }.joined(separator: ", ")) months each")
        #endif
        
        // Generate quarterly summaries using recursive chunking
        var quarterlySummaries: [String] = []
        let categoryLabel = periodType == .yearWrapWork ? "WORK" : (periodType == .yearWrapPersonal ? "PERSONAL" : "ALL")
        
        for (index, monthsInQuarter) in quarterGroups.enumerated() {
            let quarter = index + 1
            
            #if DEBUG
            print("🔄 [LocalEngine] Processing Q\(quarter) with \(monthsInQuarter.count) months")
            #endif
            
            do {
                let quarterlySummary = try await synthesizeWithRecursiveChunking(
                    summaries: monthsInQuarter,
                    label: "Q\(quarter)",
                    level: 1,
                    categoryLabel: categoryLabel
                )
                
                quarterlySummaries.append("Q\(quarter): \(quarterlySummary)")
                
                #if DEBUG
                print("✅ [LocalEngine] Q\(quarter) synthesis complete")
                #endif
                
                // Unload model between quarters to free memory (if more quarters remaining)
                if quarter < quarterGroups.count {
                    #if DEBUG
                    print("🧹 [LocalEngine] Unloading model between Q\(quarter) and Q\(quarter + 1)...")
                    #endif
                    await llamaContext.unloadModel()
                    await Task.yield()
                    
                    // Add longer cooldown between quarters (2s instead of 1s)
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            } catch {
                #if DEBUG
                print("⚠️ [LocalEngine] Q\(quarter) synthesis failed: \(error), using fallback")
                #endif
                // Fallback: Use first month summary as representative
                let fallbackText = monthsInQuarter.first?.summary ?? "No data"
                quarterlySummaries.append("Q\(quarter): \(fallbackText)")
            }
        }
        
        #if DEBUG
        print("✅ [LocalEngine] All quarterly summaries generated (\(quarterlySummaries.count) quarters)")
        #endif
        
        // REMOVED: Don't unload model here - keep it loaded to avoid reload memory spike
        // The defer block will unload at the end of the function
        
        // Brief cooldown before final generation (1s instead of 3s + reload)
        #if DEBUG
        print("⏳ [LocalEngine] Brief cooldown before final Year Wrap generation...")
        #endif
        try await Task.sleep(nanoseconds: 1_000_000_000)
        await Task.yield()
        
        // Build combined quarterly summaries for final Year Wrap
        let combinedQuarterlySummaries = quarterlySummaries
            .map { "- \($0)" }
            .joined(separator: "\n")
        
        // Model already loaded from quarterly synthesis - no reload needed
        // This avoids the memory spike from unload + reload cycle
        
        #if DEBUG
        print("🤖 [LocalEngine] Generating \(categoryLabel) Year Wrap with multi-prompt approach...")
        print("🔄 [LocalEngine] Model already loaded, using existing instance")
        #endif
        
        // MULTI-PROMPT STRATEGY: Generate different aspects separately to stay within memory limits
        // Each prompt is small (~400-600 chars) and focused on one aspect
        var yearWrapComponents: [String: Any] = [:]
        
        do {
            // 1. Generate title + summary (most important)
            #if DEBUG
            print("📝 [LocalEngine] Step 1/5: Generating title and summary...")
            #endif
            let titleSummaryPrompt = buildTitleSummaryPrompt(summaries: combinedQuarterlySummaries, topTopics: topTopics, categoryLabel: categoryLabel)
            let titleSummary = try await llamaContext.generate(prompt: titleSummaryPrompt, maxTokens: 128)  // Doubled for scaling
            totalLLMCalls += 1
            try await Task.sleep(nanoseconds: 500_000_000)
            
            // 2. Generate wins and challenges
            #if DEBUG
            print("📝 [LocalEngine] Step 2/5: Generating wins and challenges...")
            #endif
            let winsPrompt = buildWinsChallengesPrompt(summaries: combinedQuarterlySummaries, categoryLabel: categoryLabel)
            let wins = try await llamaContext.generate(prompt: winsPrompt, maxTokens: 64)
            totalLLMCalls += 1
            try await Task.sleep(nanoseconds: 500_000_000)
            
            // 3. Generate projects
            #if DEBUG
            print("📝 [LocalEngine] Step 3/5: Generating projects...")
            #endif
            let projectsPrompt = buildProjectsPrompt(summaries: combinedQuarterlySummaries, categoryLabel: categoryLabel)
            let projects = try await llamaContext.generate(prompt: projectsPrompt, maxTokens: 64)
            totalLLMCalls += 1
            try await Task.sleep(nanoseconds: 500_000_000)
            
            // 4. Generate topics and actions
            #if DEBUG
            print("📝 [LocalEngine] Step 4/5: Generating topics and actions...")
            #endif
            let topicsPrompt = buildTopicsActionsPrompt(summaries: combinedQuarterlySummaries, categoryLabel: categoryLabel)
            let topics = try await llamaContext.generate(prompt: topicsPrompt, maxTokens: 64)
            totalLLMCalls += 1
            try await Task.sleep(nanoseconds: 500_000_000)
            
            // 5. Generate people and places (if mentioned)
            #if DEBUG
            print("📝 [LocalEngine] Step 5/5: Generating people and places...")
            #endif
            let peoplePrompt = buildPeoplePrompt(summaries: combinedQuarterlySummaries)
            let people = try await llamaContext.generate(prompt: peoplePrompt, maxTokens: 32)
            totalLLMCalls += 1
            
            // Combine all components into final JSON
            #if DEBUG
            print("🔗 [LocalEngine] Combining \(totalLLMCalls) prompts into Year Wrap JSON...")
            #endif
            
            let wrappedJSON = assembleYearWrapFromComponents(
                titleSummary: titleSummary,
                wins: wins,
                projects: projects,
                topics: topics,
                people: people,
                topTopics: topTopics,
                categoryLabel: categoryLabel
            )
            
            // Log performance metrics
            if let startTime = generationStartTime {
                let duration = Date().timeIntervalSince(startTime)
                #if DEBUG
                print("⏱️ [LocalEngine] Year Wrap generation completed in \(String(format: "%.1f", duration))s with \(totalLLMCalls) LLM calls at max depth \(maxDepthReached)")
                #endif
            }
            
            return PeriodIntelligence(
                periodType: periodType,
                periodStart: periodStart,
                periodEnd: periodEnd,
                summary: wrappedJSON,
                topics: Array(topTopics),
                entities: allEntities,
                sentiment: averageSentiment,
                sessionCount: sessionSummaries.count,
                totalDuration: totalDuration,
                totalWordCount: totalWordCount,
                trends: nil
            )
        } catch let generateError {
            #if DEBUG
            print("❌ [LocalEngine] Multi-prompt generation failed: \(generateError)")
            #endif
            
            // Immediate fallback if generation crashes
            let fallbackJSON = buildFallbackYearWrapJSON(
                sessionSummaries: sessionSummaries,
                topTopics: topTopics,
                categoryLabel: categoryLabel
            )
            return PeriodIntelligence(
                periodType: periodType,
                periodStart: periodStart,
                periodEnd: periodEnd,
                summary: fallbackJSON,
                topics: Array(topTopics),
                entities: allEntities,
                sentiment: averageSentiment,
                sessionCount: sessionSummaries.count,
                totalDuration: totalDuration,
                totalWordCount: totalWordCount,
                trends: nil
            )
        }
    }
    
    // MARK: - Multi-Prompt Helper Functions for Local AI
    
    /// Build focused prompt for title and summary (Step 1/5)
    private func buildTitleSummaryPrompt(summaries: String, topTopics: [String], categoryLabel: String) -> String {
        let topicsStr = topTopics.prefix(2).joined(separator: ", ")
        return """
        Summarize this year in 2-3 sentences based ONLY on the summaries below.
        CATEGORY: \(categoryLabel)
        TOPICS: \(topicsStr)
        
        SUMMARIES:
        \(summaries)
        
        CRITICAL: Only mention what's actually in the summaries. Do not make up or infer content.
        """
    }
    
    /// Build focused prompt for wins and challenges (Step 2/5)
    private func buildWinsChallengesPrompt(summaries: String, categoryLabel: String) -> String {
        return """
        List biggest wins and challenges found in the summaries below (2-3 each, or fewer if not enough data).
        CATEGORY: \(categoryLabel)
        
        SUMMARIES:
        \(summaries)
        
        CRITICAL: Only list what's explicitly mentioned. If no wins/challenges found, output "None found".
        """
    }
    
    /// Build focused prompt for projects (Step 3/5)
    private func buildProjectsPrompt(summaries: String, categoryLabel: String) -> String {
        return """
        List projects found in the summaries below (2-3 each: finished and unfinished, or fewer if not enough data).
        CATEGORY: \(categoryLabel)
        
        SUMMARIES:
        \(summaries)
        
        CRITICAL: Only list projects explicitly mentioned. If none found, output "None found".
        """
    }
    
    /// Build focused prompt for topics and actions (Step 4/5)
    private func buildTopicsActionsPrompt(summaries: String, categoryLabel: String) -> String {
        return """
        Extract main topics from the summary below. List only what's explicitly mentioned (2-3 items).
        CATEGORY: \(categoryLabel)
        
        SUMMARY:
        \(summaries.prefix(400))
        
        Output format: Simple bullet list like:
        - Topic 1
        - Topic 2
        
        CRITICAL: Extract only actual topics/themes from the summary. If nothing clear, output "None".
        """
    }
    
    /// Build focused prompt for people (Step 5/5)
    private func buildPeoplePrompt(summaries: String) -> String {
        return """
        List people mentioned in the summaries below (1-2, or fewer if not enough data).
        
        SUMMARIES:
        \(summaries.prefix(200))
        
        CRITICAL: Only list people explicitly mentioned by name. If none found, output "None found".
        """
    }
    
    /// Assemble Year Wrap JSON from multiple prompt outputs
    private func assembleYearWrapFromComponents(
        titleSummary: String,
        wins: String,
        projects: String,
        topics: String,
        people: String,
        topTopics: [String],
        categoryLabel: String
    ) -> String {
        // Determine primary category
        let primaryCategory = categoryLabel == "PERSONAL" ? "personal" : "work"
        let secondaryCategory = categoryLabel == "PERSONAL" ? "work" : "personal"
        
        // Parse outputs and create classified items
        let winsItems = parseItemsFromText(wins, count: 3, primaryCategory: primaryCategory, secondaryCategory: secondaryCategory, isAll: categoryLabel == "ALL")
        let projectsItems = parseItemsFromText(projects, count: 3, primaryCategory: primaryCategory, secondaryCategory: secondaryCategory, isAll: categoryLabel == "ALL")
        let topicsItems = parseItemsFromText(topics, count: 3, primaryCategory: primaryCategory, secondaryCategory: secondaryCategory, isAll: categoryLabel == "ALL")
        
        // Build JSON - increased summary limit to 800 chars to match 128 token output (~400-500 chars)
        let cleanSummary = titleSummary.replacingOccurrences(of: "\"", with: "'").prefix(800)
        
        return """
        {"year_title":"Year in Review","year_summary":"\(cleanSummary)","major_arcs":[],"biggest_wins":[\(winsItems)],"biggest_losses":[],"biggest_challenges":[],"finished_projects":[\(projectsItems)],"unfinished_projects":[],"top_worked_on_topics":[\(topicsItems)],"top_talked_about_things":[],"valuable_actions_taken":[],"opportunities_missed":[],"people_mentioned":[],"places_visited":[]}
        """
    }
    
    /// Parse items from text and create classified JSON items
    private func parseItemsFromText(_ text: String, count: Int, primaryCategory: String, secondaryCategory: String, isAll: Bool) -> String {
        // Check if AI returned "None found" or similar empty signals
        let lowercased = text.lowercased()
        if lowercased.contains("none found") || lowercased.contains("no data") || lowercased.contains("not enough") {
            return ""  // Return empty string to avoid fabricated items
        }
        
        // Split by common delimiters
        let lines = text.components(separatedBy: CharacterSet(charactersIn: ".\n-•"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                // Filter out common fabrication patterns and prompt echoes
                let lower = line.lowercased()
                return !line.isEmpty 
                    && line.count > 5 
                    && !lower.contains("none found")
                    && !lower.contains("no data")
                    && !lower.contains("for the given")
                    && !lower.contains("here are")
                    && !lower.contains("instruction")
                    && !lower.contains("provided topics")
                    && !lower.contains("under the")
                    && !lower.contains("related to")
                    && !lower.hasPrefix("**")  // Skip markdown headers
                    && !lower.contains("description:")  // Skip meta descriptions
                    && !lower.contains("topic:")
                    && !lower.contains("action:")
            }
            .prefix(count)
        
        // If no valid lines after filtering, return empty
        if lines.isEmpty {
            return ""
        }
        
        return lines.enumerated().map { index, line in
            let category: String
            if isAll {
                category = index % 2 == 0 ? primaryCategory : secondaryCategory
            } else {
                category = index < 2 ? primaryCategory : secondaryCategory
            }
            let escaped = line.replacingOccurrences(of: "\"", with: "'").prefix(100)
            return "{\"text\":\"\(escaped)\",\"category\":\"\(category)\"}"
        }.joined(separator: ",")
    }
    
    // MARK: - Quarterly Summary Prompt
    
    /// Build simplified quarterly summary prompt for intermediate synthesis
    /// Concise format optimized for recursive chunking - no JSON, just plain text
    private func buildQuarterlySummaryPrompt(summaries: String, quarterLabel: String, categoryLabel: String) -> String {
        return """
        Summarize these month summaries into a concise overview (3-5 sentences).
        
        PERIOD: \(quarterLabel)
        CATEGORY: \(categoryLabel)
        
        SUMMARIES:
        \(summaries)
        
        Output plain text covering what's actually mentioned:
        - Main themes and topics
        - Notable achievements
        - Challenges faced
        - People/entities named
        
        CRITICAL: Only write about what's in the summaries above. Output plain text only.
        """
    }
    
    // MARK: - JSON Parsing and Fallbacks
    
    /// Parse Year Wrap JSON from LLM output (with crash protection)
    private func parseYearWrapJSON(_ output: String) -> String? {
        #if DEBUG
        print("🔍 [LocalEngine] Parsing Year Wrap JSON (output length: \(output.count))")
        #endif
        
        do {
            // Try to find JSON in the output
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Look for JSON object
            guard let startIndex = trimmed.firstIndex(of: "{"),
                  let endIndex = trimmed.lastIndex(of: "}") else {
                #if DEBUG
                print("⚠️ [LocalEngine] No JSON object found in output")
                #endif
                return nil
            }
            
            let jsonString = String(trimmed[startIndex...endIndex])
            
            #if DEBUG
            print("🔍 [LocalEngine] Extracted JSON candidate (length: \(jsonString.count))")
            #endif
            
            // Validate it's actual JSON and contains required fields
            guard let data = jsonString.data(using: .utf8),
                  let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                #if DEBUG
                print("⚠️ [LocalEngine] Invalid JSON structure")
                #endif
                return nil
            }
            
            // Verify required fields exist
            guard jsonObject["year_title"] != nil,
                  jsonObject["year_summary"] != nil else {
                #if DEBUG
                print("⚠️ [LocalEngine] Missing required fields (year_title or year_summary)")
                #endif
                return nil
            }
            
            #if DEBUG
            print("✅ [LocalEngine] Valid JSON with required fields")
            #endif
            
            return jsonString
        } catch {
            #if DEBUG
            print("❌ [LocalEngine] JSON parsing crashed: \(error)")
            #endif
            return nil
        }
    }
    
    /// Wrap plain text in Year Wrap JSON structure (Universal Prompt schema) with crash protection
    private func wrapPlainTextAsYearWrapJSON(text: String, topTopics: [String], sessionCount: Int, categoryLabel: String) -> String {
        #if DEBUG
        print("🔄 [LocalEngine] Wrapping plain text as Year Wrap JSON (fallback mode)")
        #endif
        
        do {
            // Clean the text with extra safety
            let cleanText = text
                .replacingOccurrences(of: "\"", with: "'")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\\", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(500)  // Limit length
            
            // Generate classified items from topics based on categoryLabel
            // ALL: mix of work/personal, WORK: mostly work, PERSONAL: mostly personal
            let primaryCategory: String
            let secondaryCategory: String
            if categoryLabel == "WORK" {
                primaryCategory = "work"
                secondaryCategory = "personal"
            } else if categoryLabel == "PERSONAL" {
                primaryCategory = "personal"
                secondaryCategory = "work"
            } else {
                // ALL: balanced mix
                primaryCategory = "work"
                secondaryCategory = "personal"
            }
            
            let classifiedTopics = topTopics.prefix(3).enumerated().compactMap { index, topic -> String? in
                guard !topic.isEmpty else { return nil }
                // For ALL: alternate, for WORK/PERSONAL: mostly primary category
                let category: String
                if categoryLabel == "ALL" {
                    category = index % 2 == 0 ? primaryCategory : secondaryCategory
                } else {
                    // 80% primary category (index 0,1), 20% secondary (index 2)
                    category = index < 2 ? primaryCategory : secondaryCategory
                }
                let escapedTopic = topic
                    .replacingOccurrences(of: "\"", with: "'")
                    .replacingOccurrences(of: "\\", with: "")
                    .replacingOccurrences(of: "\n", with: " ")
                    .prefix(100)  // Limit topic length
                return "{\"text\":\"\(escapedTopic)\",\"category\":\"\(category)\"}"
            }.joined(separator: ",")
            
            let result = """
            {"year_title":"Year in Review","year_summary":"\(cleanText)","major_arcs":[],"biggest_wins":[\(classifiedTopics)],"biggest_losses":[],"biggest_challenges":[],"finished_projects":[],"unfinished_projects":[],"top_worked_on_topics":[],"top_talked_about_things":[],"valuable_actions_taken":[],"opportunities_missed":[],"people_mentioned":[],"places_visited":[]}
            """
            
            #if DEBUG
            print("✅ [LocalEngine] Wrapped JSON created (length: \(result.count))")
            #endif
            
            return result
        } catch {
            #if DEBUG
            print("❌ [LocalEngine] Text wrapping crashed: \(error)")
            #endif
            // Ultimate fallback - minimal valid JSON
            return "{\"year_title\":\"Year in Review\",\"year_summary\":\"Summary unavailable\",\"major_arcs\":[],\"biggest_wins\":[],\"biggest_losses\":[],\"biggest_challenges\":[],\"finished_projects\":[],\"unfinished_projects\":[],\"top_worked_on_topics\":[],\"top_talked_about_things\":[],\"valuable_actions_taken\":[],\"opportunities_missed\":[],\"people_mentioned\":[],\"places_visited\":[]}"
        }
    }
    
    /// Build fallback Year Wrap JSON from aggregated data (Universal Prompt schema) with crash protection
    private func buildFallbackYearWrapJSON(sessionSummaries: [SessionIntelligence], topTopics: [String], categoryLabel: String) -> String {
        #if DEBUG
        print("🔄 [LocalEngine] Building fallback Year Wrap JSON from \(sessionSummaries.count) summaries")
        #endif
        
        do {
            // Create summary from first few session summaries with safety
            let summaryText: String
            if sessionSummaries.isEmpty {
                summaryText = "No session data available for this period"
            } else {
                summaryText = sessionSummaries.prefix(5)
                    .map { $0.summary }
                    .joined(separator: " ")
                    .prefix(500)
                    .replacingOccurrences(of: "\"", with: "'")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\t", with: " ")
                    .replacingOccurrences(of: "\\", with: "")
            }
            
            // Determine primary category based on variant
            let primaryCategory = categoryLabel == "PERSONAL" ? "personal" : "work"
            let secondaryCategory = categoryLabel == "PERSONAL" ? "work" : "personal"
            
            // Generate classified items from top topics with category awareness
            let classifiedWins: String
            if topTopics.isEmpty {
                classifiedWins = ""
            } else {
                classifiedWins = topTopics.prefix(3).enumerated().compactMap { index, topic -> String? in
                    guard !topic.isEmpty else { return nil }
                    let category: String
                    if categoryLabel == "ALL" {
                        category = index % 2 == 0 ? "work" : "personal"
                    } else {
                        category = index < 2 ? primaryCategory : secondaryCategory
                    }
                    let escapedTopic = topic
                        .replacingOccurrences(of: "\"", with: "'")
                        .replacingOccurrences(of: "\\", with: "")
                        .replacingOccurrences(of: "\n", with: " ")
                        .prefix(100)
                    return "{\"text\":\"Progress in \(escapedTopic)\",\"category\":\"\(category)\"}"
                }.joined(separator: ",")
            }
            
            let classifiedTopics: String
            if topTopics.isEmpty {
                classifiedTopics = ""
            } else {
                classifiedTopics = topTopics.prefix(5).enumerated().compactMap { index, topic -> String? in
                    guard !topic.isEmpty else { return nil }
                    let category: String
                    if categoryLabel == "ALL" {
                        category = index % 2 == 0 ? "work" : "personal"
                    } else {
                        category = index < 3 ? primaryCategory : secondaryCategory
                    }
                    let escapedTopic = topic
                        .replacingOccurrences(of: "\"", with: "'")
                        .replacingOccurrences(of: "\\", with: "")
                        .replacingOccurrences(of: "\n", with: " ")
                        .prefix(100)
                    return "{\"text\":\"\(escapedTopic)\",\"category\":\"\(category)\"}"
                }.joined(separator: ",")
            }
            
            let result = """
            {"year_title":"Year in Review","year_summary":"\(summaryText)","major_arcs":[],"biggest_wins":[\(classifiedWins)],"biggest_losses":[],"biggest_challenges":[],"finished_projects":[],"unfinished_projects":[],"top_worked_on_topics":[\(classifiedTopics)],"top_talked_about_things":[],"valuable_actions_taken":[],"opportunities_missed":[],"people_mentioned":[],"places_visited":[]}
            """
            
            #if DEBUG
            print("✅ [LocalEngine] Fallback JSON created (length: \(result.count))")
            #endif
            
            return result
        } catch {
            #if DEBUG
            print("❌ [LocalEngine] CRITICAL: Fallback JSON generation crashed: \(error)")
            #endif
            // Ultimate emergency fallback - minimal valid JSON
            return "{\"year_title\":\"Year in Review\",\"year_summary\":\"Summary generation failed\",\"major_arcs\":[],\"biggest_wins\":[],\"biggest_losses\":[],\"biggest_challenges\":[],\"finished_projects\":[],\"unfinished_projects\":[],\"top_worked_on_topics\":[],\"top_talked_about_things\":[],\"valuable_actions_taken\":[],\"opportunities_missed\":[],\"people_mentioned\":[],\"places_visited\":[]}"
        }
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
    
    /// Build a simplified prompt optimized for local MLX inference
    /// Uses Phi-3.5 chat template and produces natural, note-style output
    private func buildSimplifiedPrompt(text: String) -> String {
        return """
        <|system|>
        You clean up voice recordings. Output ONLY the cleaned text directly. Never wrap in quotes. Never add explanations.
        <|end|>
        <|user|>
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
        <|end|>
        <|assistant|>
        """
    }
    
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
