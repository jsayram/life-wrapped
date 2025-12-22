//
//  LocalEngine.swift
//  Summarization
//
//  Created by Life Wrapped on 12/17/2025.
//

import Foundation
import SharedModels
import Storage
import LocalLLM
#if canImport(Darwin)
import Darwin
#endif

/// Local LLM-based summarization engine (Tier B)
/// Uses on-device llama.cpp with quantized models for privacy-preserving inference
public actor LocalEngine: SummarizationEngine {
    
    public let tier: EngineTier = .local
    
    private let storage: DatabaseManager
    private let configuration: EngineConfiguration
    private var localConfiguration: LocalLLMConfiguration
    private let llamaContext: LlamaContext
    private let modelFileManager: ModelFileManager
    
    // Statistics
    private var summariesGenerated: Int = 0
    private var totalProcessingTime: TimeInterval = 0
    
    // MARK: - Initialization
    
    public init(
        storage: DatabaseManager,
        configuration: EngineConfiguration? = nil,
        localConfiguration: LocalLLMConfiguration = .current()
    ) {
        self.storage = storage
        self.configuration = configuration ?? .defaults(for: .local)
        self.localConfiguration = localConfiguration
        self.llamaContext = LlamaContext(configuration: localConfiguration)
        self.modelFileManager = ModelFileManager.shared
        
        print("🧠 [LocalEngine] Initialized (\(localConfiguration.preset.displayName), \(localConfiguration.tokensDescription))")
    }
    
    // MARK: - SummarizationEngine Protocol
    
    public func isAvailable() async -> Bool {
        // Don't use local LLM on simulator - it's too slow and may crash
        #if targetEnvironment(simulator)
        print("⚠️ [LocalEngine] Local LLM disabled on simulator")
        return false
        #else
        // Check if model file is present
        let hasModel = await modelFileManager.availableModels().isEmpty == false
        
        // Check if llama context is ready
        let isReady = await llamaContext.isReady()
        
        print("ℹ️ [LocalEngine] Availability check: hasModel=\(hasModel), isReady=\(isReady)")
        
        return hasModel || isReady  // Available if model exists (can be loaded) or already loaded
        #endif
    }
    
    public func summarizeSession(
        sessionId: UUID,
        transcriptText: String,
        duration: TimeInterval,
        languageCodes: [String]
    ) async throws -> SessionIntelligence {
        let startTime = Date()
        
        // Log summarization request
        SummarizationLogger.log(
            level: .session,
            engine: .local,
            provider: "SwiftLlama",
            model: localConfiguration.modelName,
            temperature: configuration.temperature,
            maxTokens: min(configuration.maxTokens, localConfiguration.maxTokens),
            inputSize: transcriptText.count,
            sessionId: sessionId
        )

        let preparedTranscript = clampTranscript(transcriptText)
        let wordCount = preparedTranscript.split(separator: " ").count
        
        // Guard against empty or too-short transcripts
        guard wordCount >= configuration.minimumWords else {
            print("⚠️ [LocalEngine] Transcript too short (\(wordCount) words), using extractive fallback")
            return try await extractiveFallback(sessionId: sessionId, transcriptText: transcriptText, duration: duration)
        }

        // Ensure model is loaded; if it fails, drop to extractive fallback instead of erroring out.
        do {
            try await ensureModelLoaded()
        } catch {
            print("⚠️ [LocalEngine] Failed to load local model: \(error.localizedDescription). Using extractive fallback.")
            return try await extractiveFallback(sessionId: sessionId, transcriptText: preparedTranscript, duration: duration)
        }
        
        // Generate prompt using universal template with separated messages
        let messages = UniversalPrompt.buildMessages(
            level: .session,
            input: preparedTranscript,
            metadata: ["duration": Int(duration), "wordCount": wordCount]
        )
        
        // Call LLM with proper system prompt
        let response: String
        do {
            response = try await llamaContext.generate(
                systemPrompt: messages.system,
                userMessage: messages.user
            )
        } catch {
            print("⚠️ [LocalEngine] Generation failed: \(error.localizedDescription). Falling back to extractive summary.")
            return try await extractiveFallback(sessionId: sessionId, transcriptText: preparedTranscript, duration: duration)
        }
        
        // Parse JSON response
        let intelligence = try await parseSessionResponse(response, sessionId: sessionId, transcriptText: preparedTranscript, duration: duration)
        
        // Update statistics
        let processingTime = Date().timeIntervalSince(startTime)
        summariesGenerated += 1
        totalProcessingTime += processingTime
        
        print("✅ [LocalEngine] Session summary generated in \(String(format: "%.2f", processingTime))s")
        
        return intelligence
    }
    
    public func summarizePeriod(
        periodType: PeriodType,
        sessionSummaries: [SessionIntelligence],
        periodStart: Date,
        periodEnd: Date
    ) async throws -> PeriodIntelligence {
        let startTime = Date()
        
        let summaryLevel = SummaryLevel.from(periodType: periodType)
        
        // Log summarization request
        SummarizationLogger.log(
            level: summaryLevel,
            engine: .local,
            provider: "SwiftLlama",
            model: localConfiguration.modelName,
            temperature: configuration.temperature,
            maxTokens: min(configuration.maxTokens, localConfiguration.maxTokens),
            inputSize: sessionSummaries.count,
            sessionId: nil
        )
        
        guard !sessionSummaries.isEmpty else {
            throw SummarizationError.insufficientContent(minimumWords: 1, actualWords: 0)
        }

        // Ensure model is loaded; if unavailable, fall back to extractive merge to keep the app flowing.
        do {
            try await ensureModelLoaded()
        } catch {
            print("⚠️ [LocalEngine] Failed to load local model: \(error.localizedDescription). Returning simple merged summary.")
            return makePeriodFallback(
                sessionSummaries: sessionSummaries,
                periodType: periodType,
                periodStart: periodStart,
                periodEnd: periodEnd
            )
        }
        
        // Prepare input as structured JSON for hierarchical summarization
        let inputData = sessionSummaries.map { session in
            [
                "summary": session.summary,
                "topics": session.topics,
                "sentiment": session.sentiment
            ] as [String: Any]
        }
        let inputJSON = (try? JSONSerialization.data(withJSONObject: inputData))
            .flatMap { String(data: $0, encoding: .utf8) } ?? sessionSummaries.map { $0.summary }.joined(separator: "\n\n")
        
        // Generate prompt using universal template with separated messages
        let messages = UniversalPrompt.buildMessages(
            level: summaryLevel,
            input: inputJSON,
            metadata: ["sessionCount": sessionSummaries.count, "periodType": periodType.rawValue]
        )
        
        // Call LLM with proper system prompt
        let response: String
        do {
            response = try await llamaContext.generate(
                systemPrompt: messages.system,
                userMessage: messages.user
            )
        } catch {
            print("⚠️ [LocalEngine] Period generation failed: \(error.localizedDescription). Using extractive fallback.")
            return makePeriodFallback(
                sessionSummaries: sessionSummaries,
                periodType: periodType,
                periodStart: periodStart,
                periodEnd: periodEnd
            )
        }
        
        // Parse JSON response
        let intelligence = try parsePeriodResponse(
            response,
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            sessionSummaries: sessionSummaries
        )
        
        // Update statistics
        let processingTime = Date().timeIntervalSince(startTime)
        summariesGenerated += 1
        totalProcessingTime += processingTime
        
        print("✅ [LocalEngine] Period summary generated in \(String(format: "%.2f", processingTime))s")
        
        return intelligence
    }
    
    // MARK: - Helper Methods
    
    private func ensureModelLoaded() async throws {
        guard await llamaContext.isReady() else {
            print("📥 [LocalEngine] Loading model...")
            try await llamaContext.loadModel()
            return
        }
    }

    /// Run an arbitrary prompt against the local model for debugging
    public func debugGenerate(prompt: String) async throws -> String {
        try await ensureModelLoaded()
        return try await llamaContext.generate(prompt: prompt)
    }

    public func getLocalConfiguration() -> LocalLLMConfiguration {
        localConfiguration
    }

    /// Update the local LLM configuration and unload any loaded model so it reloads with new caps.
    public func updateLocalConfiguration(_ configuration: LocalLLMConfiguration) async {
        localConfiguration = configuration
        await llamaContext.updateConfiguration(configuration)
    }
    
    private func extractiveFallback(sessionId: UUID, transcriptText: String, duration: TimeInterval) async throws -> SessionIntelligence {
        print("🔄 [LocalEngine] Using extractive fallback for session \(sessionId)")
        
        // Use basic extractive summarization
        let fullText = transcriptText
        
        // Simple sentence extraction
        let sentences = fullText.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let summary = sentences.prefix(3).joined(separator: ". ")
        
        // Extract basic topics (nouns)
        let words = fullText.lowercased().split(separator: " ")
        let topics = Array(Set(words.map(String.init).filter { $0.count > 4 })).prefix(5)
        
        return SessionIntelligence(
            sessionId: sessionId,
            summary: summary.isEmpty ? "No summary available" : summary,
            topics: Array(topics),
            entities: [],
            sentiment: 0.0,
            duration: duration,
            wordCount: fullText.split(separator: " ").count,
            languageCodes: [],
            keyMoments: []
        )
    }
    
    private func parseSessionResponse(_ response: String, sessionId: UUID, transcriptText: String, duration: TimeInterval) async throws -> SessionIntelligence {
        // Log raw response for debugging
        print("📄 [LocalEngine] Raw LLM response (\(response.count) chars):")
        print(response.prefix(500))
        if response.count > 500 {
            print("... (truncated, full length: \(response.count))")
        }
        
        // Check if response looks incomplete (missing closing brace)
        let openBraces = response.filter { $0 == "{" }.count
        let closeBraces = response.filter { $0 == "}" }.count
        if openBraces > closeBraces {
            print("⚠️ [LocalEngine] Incomplete JSON detected (\(openBraces) '{' vs \(closeBraces) '}'), likely hit token limit")
        }
        
        // Try to extract JSON if wrapped in markdown or other text
        let jsonString: String
        if let jsonStart = response.firstIndex(of: "{") {
            // Find the matching closing brace for the first opening brace
            var braceCount = 0
            var jsonEnd: String.Index?
            
            for index in response[jsonStart...].indices {
                let char = response[index]
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        jsonEnd = index
                        break
                    }
                }
            }
            
            if let jsonEnd = jsonEnd, jsonStart < jsonEnd {
                let endIndex = response.index(after: jsonEnd)
                jsonString = String(response[jsonStart..<endIndex])
                print("🔍 [LocalEngine] Extracted JSON from response (from char \(response.distance(from: response.startIndex, to: jsonStart)) to \(response.distance(from: response.startIndex, to: endIndex)))")
            } else {
                // Could not find matching closing brace
                jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
                print("⚠️ [LocalEngine] Could not find matching closing brace, using full response")
            }
        } else {
            // No valid JSON brackets found, use full response
            jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
            print("⚠️ [LocalEngine] Could not find JSON brackets, using full response")
        }
        
        // Parse JSON response from LLM
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ [LocalEngine] Failed to convert response to data")
            throw LocalLLMError.invalidOutput
        }
        
        let decoder = JSONDecoder()
        
        do {
            let parsed = try decoder.decode(LLMSessionResponse.self, from: jsonData)
            
            // Format as paragraph narrative with first-person voice
            var paragraphs: [String] = []
            
            // Add key insights if present
            if !parsed.key_insights.isEmpty {
                let insights = parsed.key_insights.joined(separator: ". ")
                paragraphs.append(insights)
            }
            
            // Add thought process
            if !parsed.thought_process.isEmpty {
                paragraphs.append(parsed.thought_process)
            }
            
            // Add action items if present
            if !parsed.action_items.isEmpty {
                let actions = "My next steps: " + parsed.action_items.joined(separator: ", ") + "."
                paragraphs.append(actions)
            }
            
            // Add open questions if present
            if !parsed.open_questions.isEmpty {
                let questions = "I'm still figuring out: " + parsed.open_questions.joined(separator: "; ") + "."
                paragraphs.append(questions)
            }
            
            // Join all paragraphs with periods and spaces
            let summaryText = paragraphs.joined(separator: " ")
            
            // Determine sentiment from mood_tone
            let sentiment = parseMoodToSentiment(parsed.mood_tone)
            
            return SessionIntelligence(
                sessionId: sessionId,
                summary: summaryText.trimmingCharacters(in: .whitespacesAndNewlines),
                topics: parsed.main_themes,
                entities: [],  // No entities in new schema
                sentiment: sentiment,
                duration: duration,
                wordCount: transcriptText.split(separator: " ").count,
                languageCodes: [],
                keyMoments: []  // No key moments in new schema
            )
        } catch {
            print("⚠️ [LocalEngine] JSON parsing failed: \(error), using fallback")
            return try await extractiveFallback(sessionId: sessionId, transcriptText: transcriptText, duration: duration)
        }
    }
    
    // Convert mood_tone string to sentiment score
    private func parseMoodToSentiment(_ mood: String) -> Double {
        let lowerMood = mood.lowercased()
        if lowerMood.contains("positive") || lowerMood.contains("good") || lowerMood.contains("happy") || lowerMood.contains("excited") {
            return 0.7
        } else if lowerMood.contains("negative") || lowerMood.contains("bad") || lowerMood.contains("sad") || lowerMood.contains("frustrated") {
            return -0.7
        } else {
            return 0.0  // neutral
        }
    }
    
    private func parsePeriodResponse(
        _ response: String,
        periodType: PeriodType,
        periodStart: Date,
        periodEnd: Date,
        sessionSummaries: [SessionIntelligence]
    ) throws -> PeriodIntelligence {
        guard let jsonData = response.data(using: .utf8) else {
            throw LocalLLMError.invalidOutput
        }
        
        let decoder = JSONDecoder()
        let parsed = try decoder.decode(LLMPeriodResponse.self, from: jsonData)
        
        let totalDuration = sessionSummaries.reduce(0.0) { $0 + $1.duration }
        let totalWordCount = sessionSummaries.reduce(0) { $0 + $1.wordCount }
        
        return PeriodIntelligence(
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            summary: parsed.summary,
            topics: parsed.topics,
            entities: parsed.entities,
            sentiment: parsed.sentiment,
            sessionCount: sessionSummaries.count,
            totalDuration: totalDuration,
            totalWordCount: totalWordCount,
            trends: parsed.trends ?? []
        )
    }
    
    // MARK: - Performance Monitoring
    
    /// Get performance statistics
    public func getStatistics() -> (generated: Int, avgTime: TimeInterval, totalTime: TimeInterval) {
        let avgTime = summariesGenerated > 0 ? totalProcessingTime / Double(summariesGenerated) : 0
        return (summariesGenerated, avgTime, totalProcessingTime)
    }
    
    /// Log current performance metrics
    public func logPerformanceMetrics() {
        let stats = getStatistics()
        let memoryUsage = getMemoryUsage()
        
        print("📊 [LocalEngine] Performance Metrics:")
        print("   - Summaries generated: \(stats.generated)")
        print("   - Average time: \(String(format: "%.2f", stats.avgTime))s")
        print("   - Total processing time: \(String(format: "%.2f", stats.totalTime))s")
        print("   - Memory usage: \(String(format: "%.1f", memoryUsage)) MB")
    }

    private func clampTranscript(_ transcript: String) -> String {
        // Reserve tokens for: system prompt (~400), schema (~300), and JSON output (~400-600)
        let reservedForOutput = 1200  // Conservative reserve for complete JSON response
        let availableForInput = min(localConfiguration.contextSize, configuration.maxContextLength) - reservedForOutput
        
        // Roughly 4 characters per token
        let maxCharacters = availableForInput * 4
        guard transcript.count > maxCharacters else { return transcript }
        
        let clamped = String(transcript.prefix(maxCharacters))
        print("✂️ [LocalEngine] Clamped transcript: \(transcript.count) → \(clamped.count) chars")
        print("   Context budget: \(localConfiguration.contextSize) total, \(reservedForOutput) reserved for output, \(availableForInput) for input")
        return clamped
    }

    private func makePeriodFallback(
        sessionSummaries: [SessionIntelligence],
        periodType: PeriodType,
        periodStart: Date,
        periodEnd: Date
    ) -> PeriodIntelligence {
        let summary = sessionSummaries.map { $0.summary }.joined(separator: " \n\n ")
        let totalDuration = sessionSummaries.reduce(0.0) { $0 + $1.duration }
        let totalWordCount = sessionSummaries.reduce(0) { $0 + $1.wordCount }
        return PeriodIntelligence(
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            summary: summary.isEmpty ? "No summary available" : summary.prefix(800).description,
            topics: [],
            entities: [],
            sentiment: 0,
            sessionCount: sessionSummaries.count,
            totalDuration: totalDuration,
            totalWordCount: totalWordCount,
            trends: []
        )
    }
    
    /// Get current memory usage in MB
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return 0.0
        }
        
        return Double(info.resident_size) / 1_048_576.0 // Convert bytes to MB
    }
}

// MARK: - Response Models

private struct LLMSessionResponse: Codable {
    let title: String
    let key_insights: [String]
    let main_themes: [String]
    let action_items: [String]
    let thought_process: String
    let mood_tone: String
    let open_questions: [String]
}

private struct LLMPeriodResponse: Codable {
    let summary: String
    let topics: [String]
    let entities: [Entity]
    let sentiment: Double
    let trends: [String]?
}
