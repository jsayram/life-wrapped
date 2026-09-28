//
//  ExternalAPIEngine.swift
//  Summarization
//
//  Created by Life Wrapped on 12/17/2025.
//

import Foundation
import SharedModels
import Storage

/// External API engine using cloud services (OpenAI, Anthropic)
///
/// **Privacy Warning**: This engine sends transcript data to external servers.
/// Requires user-provided API keys and internet connection.
///
/// **Supported Providers**:
/// - OpenAI and Anthropic. The model is free text (see `ExternalModelSettings`),
///   so any current model ID from either provider can be used.
public actor ExternalAPIEngine: SummarizationEngine {
    
    // MARK: - Types
    
    public enum Provider: String, Codable, CaseIterable, Sendable {
        case openai = "OpenAI"
        case anthropic = "Anthropic"
        
        public var displayName: String { rawValue }
        
        public var defaultModel: String {
            ExternalModelSettings.defaultModel(for: self)
        }
        
        public var endpoint: String {
            switch self {
            case .openai: return "https://api.openai.com/v1/chat/completions"
            case .anthropic: return "https://api.anthropic.com/v1/messages"
            }
        }
    }
    
    /// Result of API key validation
    public enum APIKeyValidationResult: Sendable {
        case valid(message: String)
        case invalid(reason: String)
        
        public var isValid: Bool {
            switch self {
            case .valid: return true
            case .invalid: return false
            }
        }
        
        public var message: String {
            switch self {
            case .valid(let message): return message
            case .invalid(let reason): return reason
            }
        }
    }
    
    // MARK: - Properties
    
    private let storage: DatabaseManager
    private let keychainManager: KeychainManager
    
    // Configuration is read from ExternalModelSettings on every use, so changes made
    // in Settings take effect immediately without relaunching the app.
    private var selectedProvider: Provider { ExternalModelSettings.provider() }
    private var selectedModel: String { ExternalModelSettings.model(for: selectedProvider) }
    
    // Statistics tracking
    private var summariesGenerated: Int = 0
    private var totalProcessingTime: TimeInterval = 0.0
    private var totalTokensUsed: Int = 0
    
    // MARK: - Initialization
    
    public init(storage: DatabaseManager, keychainManager: KeychainManager = .shared) {
        self.storage = storage
        self.keychainManager = keychainManager
        
        // Move a model saved by older builds into the per-provider settings (runs once)
        ExternalModelSettings.migrateIfNeeded()
    }
    
    // MARK: - SummarizationEngine Protocol
    
    public nonisolated var tier: EngineTier {
        .external
    }
    
    public func isAvailable() async -> Bool {
        // Check if API key is configured. Without one, stay offline: the privacy policy
        // promises no network use unless Cloud AI is set up.
        guard await keychainManager.hasAPIKey(for: selectedProvider) else { return false }

        // Check internet connectivity (simple check)
        return await checkInternetConnectivity()
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
        
        // Log summarization request details
        logSummarizationRequest(
            level: .session,
            provider: selectedProvider,
            model: selectedModel,
            inputSize: transcriptText.count,
            sessionId: sessionId
        )
        
        // Get API key
        guard let apiKey = await keychainManager.getAPIKey(for: selectedProvider) else {
            throw SummarizationError.configurationError("No API key configured for \(selectedProvider.displayName)")
        }
        
        // Build prompt using universal schema with separated messages
        let messages = UniversalPrompt.buildMessages(
            level: .session,
            input: transcriptText,
            metadata: ["duration": Int(duration), "wordCount": transcriptText.split(separator: " ").count]
        )
        
        // Call API with proper message structure
        let response = try await callAPI(systemPrompt: messages.system, userMessage: messages.user, apiKey: apiKey)
        
        // Parse response
        let intelligence = try parseSessionResponse(response, sessionId: sessionId, duration: duration, languageCodes: languageCodes)
        
        // Update token usage
        totalTokensUsed += Self.tokensUsed(response)
        
        return intelligence
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
        
        // Convert PeriodType to SummaryLevel for logging
        let summaryLevel = SummaryLevel.from(periodType: periodType)
        
        // Log summarization request details
        logSummarizationRequest(
            level: summaryLevel,
            provider: selectedProvider,
            model: selectedModel,
            inputSize: sessionSummaries.count,
            sessionId: nil
        )
        
        // Get API key
        guard let apiKey = await keychainManager.getAPIKey(for: selectedProvider) else {
            throw SummarizationError.configurationError("No API key configured for \(selectedProvider.displayName)")
        }
        
        // Prepare input JSON from session summaries
        let inputData = sessionSummaries.map { session in
            [
                "summary": session.summary,
                "topics": session.topics,
                "sentiment": session.sentiment
            ] as [String: Any]
        }
        let inputJSON = (try? JSONSerialization.data(withJSONObject: inputData))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        
        // Build prompt using universal schema with separated messages
        let messages = UniversalPrompt.buildMessages(
            level: summaryLevel,
            input: inputJSON,
            metadata: ["sessionCount": sessionSummaries.count, "periodType": periodType.rawValue],
            categoryContext: categoryContext
        )
        
        // Call API with proper message structure
        let response = try await callAPI(systemPrompt: messages.system, userMessage: messages.user, apiKey: apiKey)
        
        // Parse response
        let intelligence = try parsePeriodResponse(response, periodType: periodType, periodStart: periodStart, periodEnd: periodEnd, sessionSummaries: sessionSummaries)
        
        // Update token usage
        totalTokensUsed += Self.tokensUsed(response)
        
        return intelligence
    }
    
    // MARK: - Configuration
    
    public func setProvider(_ provider: Provider, model: String? = nil) {
        ExternalModelSettings.setProvider(provider)
        if let model {
            ExternalModelSettings.setModel(model, for: provider)
        }
    }
    
    public func getProvider() -> (provider: Provider, model: String) {
        return (selectedProvider, selectedModel)
    }
    
    // MARK: - API Calls
    
    private func callAPI(systemPrompt: String, userMessage: String, apiKey: String, maxTokens: Int = 2000) async throws -> [String: Any] {
        let url = URL(string: selectedProvider.endpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request body based on provider with proper message structure
        switch selectedProvider {
        case .openai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        }
        let requestBody = Self.buildRequestBody(
            provider: selectedProvider,
            model: selectedModel,
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            maxTokens: maxTokens
        )
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummarizationError.summarizationFailed("Invalid response from API")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if Self.isModelNotFound(statusCode: httpResponse.statusCode, data: data) {
                throw SummarizationError.configurationError(
                    "Model \"\(selectedModel)\" isn't available from \(selectedProvider.displayName). Update the model in Settings > AI."
                )
            }
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummarizationError.summarizationFailed("API error (\(httpResponse.statusCode)): \(errorMessage)")
        }
        
        // Parse JSON response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SummarizationError.decodingFailed("Failed to parse API response as JSON")
        }
        
        return json
    }
    
    // MARK: - Prompt Building
    
    private func buildSessionPrompt(transcriptText: String, duration: TimeInterval) -> String {
        """
        Analyze the following audio transcript and generate a structured JSON summary.
        
        Transcript (duration: \(Int(duration))s):
        \(transcriptText)
        
        IMPORTANT: Return ONLY a JSON object with these EXACT field names (do not rename or add prefixes):
        {
          "summary": "A concise 2-3 sentence summary",
          "topics": ["topic1", "topic2", ...],
          "entities": [
            {"name": "entity name", "type": "person|location|organization|event|dateTime|other", "confidence": 0.0-1.0}
          ],
          "sentiment": -1.0 to 1.0 (negative to positive),
          "keyMoments": [
            {"timestamp": seconds, "description": "what happened"}
          ]
        }
        
        Use "summary" not "session_summary" or any other variation.
        """
    }
    
    private func buildPeriodPrompt(periodType: PeriodType, sessionSummaries: [SessionIntelligence]) -> String {
        let summariesText = sessionSummaries.enumerated().map { index, summary in
            var sessionLine = "Session \(index + 1)"
            if let category = summary.category {
                sessionLine += " [\(category.rawValue.uppercased())]"
            }
            sessionLine += ": \(summary.summary)"
            return sessionLine
        }.joined(separator: "\n")
        
        // Build category context summary
        let categoryContext: String
        let workCount = sessionSummaries.filter { $0.category == .work }.count
        let personalCount = sessionSummaries.filter { $0.category == .personal }.count
        let uncategorizedCount = sessionSummaries.filter { $0.category == nil }.count
        
        if workCount > 0 || personalCount > 0 {
            var categoryParts: [String] = []
            if workCount > 0 {
                categoryParts.append("\(workCount) work session\(workCount == 1 ? "" : "s")")
            }
            if personalCount > 0 {
                categoryParts.append("\(personalCount) personal session\(personalCount == 1 ? "" : "s")")
            }
            if uncategorizedCount > 0 {
                categoryParts.append("\(uncategorizedCount) uncategorized")
            }
            categoryContext = "\n\nSESSION CATEGORIES: The user has marked " + categoryParts.joined(separator: ", ") + ". Use [WORK] or [PERSONAL] tags shown above to classify each insight item."
        } else {
            categoryContext = ""
        }
        
        return """
        Analyze these \(sessionSummaries.count) session summaries from a \(periodType.displayName) period.
        
        Summaries:
        \(summariesText)\(categoryContext)
        
        IMPORTANT: Return ONLY a JSON object with these EXACT field names (do not rename or add prefixes):
        {
          "summary": "An overarching summary of the entire period",
          "topics": ["main topic themes across all sessions"],
          "trends": ["observed patterns or changes over time"]
        }
        
        Use "summary" not "daily_summary", "weekly_summary", "period_summary" or any other variation.
        """
    }
    
    // MARK: - Response Parsing
    
    private func parseSessionResponse(
        _ response: [String: Any],
        sessionId: UUID,
        duration: TimeInterval,
        languageCodes: [String]
    ) throws -> SessionIntelligence {
        
        // Extract content based on provider
        let contentText: String
        switch selectedProvider {
        case .openai:
            guard let choices = response["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw SummarizationError.decodingFailed("Failed to extract content from OpenAI response")
            }
            contentText = content
            
        case .anthropic:
            contentText = try Self.anthropicText(from: response)
        }
        
        // Parse JSON content
        #if DEBUG
        print("🔍 [ExternalAPIEngine] Raw API response content:")
        #endif
        #if DEBUG
        print("📄 [ExternalAPIEngine] \(contentText.prefix(500))...")
        #endif
        
        guard let json = ModelJSON.object(from: contentText) else {
            #if DEBUG
            print("❌ [ExternalAPIEngine] Content is not valid JSON - using as plain text summary")
            #endif
            #if DEBUG
            print("📝 [ExternalAPIEngine] Falling back to plain text: \(contentText.prefix(200))...")
            #endif
            
            // If not JSON, use the plain text as the summary
            return SessionIntelligence(
                sessionId: sessionId,
                summary: contentText,
                topics: [],
                entities: [],
                sentiment: 0.0,
                duration: duration,
                wordCount: contentText.split(separator: " ").count,
                languageCodes: languageCodes,
                keyMoments: nil
            )
        }
        
        #if DEBUG
        print("✅ [ExternalAPIEngine] Successfully parsed JSON response")
        #endif
        
        // Extract summary based on schema structure
        // Session schema has: title, key_insights[], main_themes[], thought_process, etc.
        let summary: String
        if let keyInsights = json["key_insights"] as? [String] {
            // Build paragraph narrative with first-person voice (matching LocalEngine format)
            var paragraphs: [String] = []
            
            // Add key insights if present
            if !keyInsights.isEmpty {
                let insights = keyInsights.joined(separator: ". ")
                paragraphs.append(insights)
            }
            
            // Add thought process if available
            if let thoughtProcess = json["thought_process"] as? String, !thoughtProcess.isEmpty {
                paragraphs.append(thoughtProcess)
            }
            
            // Add action items if available
            if let actionItems = json["action_items"] as? [String], !actionItems.isEmpty {
                let actions = "My next steps: " + actionItems.joined(separator: ", ") + "."
                paragraphs.append(actions)
            }
            
            // Add open questions if available
            if let openQuestions = json["open_questions"] as? [String], !openQuestions.isEmpty {
                let questions = "I'm still figuring out: " + openQuestions.joined(separator: "; ") + "."
                paragraphs.append(questions)
            }
            
            // Join all paragraphs with periods and spaces
            summary = paragraphs.joined(separator: " ")
        } else {
            // Fallback to simple field extraction
            summary = json["summary"] as? String 
                ?? json["session_summary"] as? String
                ?? json["text"] as? String
                ?? json["thought_process"] as? String
                ?? "No summary available"
        }
        
        #if DEBUG
        print("📝 [ExternalAPIEngine] Extracted summary (\(summary.count) chars): \(summary.prefix(100))...")
        #endif
        
        // Extract topics from main_themes or topics field
        let topics = (json["main_themes"] as? [String]) ?? (json["topics"] as? [String]) ?? []
        let sentiment = json["sentiment"] as? Double ?? 0.0
        
        // Parse entities
        let entities: [Entity]
        if let entitiesArray = json["entities"] as? [[String: Any]] {
            entities = entitiesArray.compactMap { dict in
                guard let name = dict["name"] as? String,
                      let typeString = dict["type"] as? String,
                      let type = EntityType(rawValue: typeString),
                      let confidence = dict["confidence"] as? Double else {
                    return nil
                }
                return Entity(name: name, type: type, confidence: confidence)
            }
        } else {
            entities = []
        }
        
        // Parse key moments
        let keyMoments: [KeyMoment]?
        if let momentsArray = json["keyMoments"] as? [[String: Any]] {
            keyMoments = momentsArray.compactMap { dict -> KeyMoment? in
                guard let timestamp = dict["timestamp"] as? TimeInterval,
                      let description = dict["description"] as? String else {
                    return nil
                }
                let importance = dict["importance"] as? Double ?? 0.5
                return KeyMoment(timestamp: timestamp, description: description, importance: importance)
            }
        } else {
            keyMoments = nil
        }
        
        // Calculate word count
        let wordCount = summary.split(separator: " ").count
        
        return SessionIntelligence(
            sessionId: sessionId,
            summary: summary,
            topics: topics,
            entities: entities,
            sentiment: sentiment,
            duration: duration,
            wordCount: wordCount,
            languageCodes: languageCodes,
            keyMoments: keyMoments,
            title: json["title"] as? String
        )
    }
    
    private func parsePeriodResponse(
        _ response: [String: Any],
        periodType: PeriodType,
        periodStart: Date,
        periodEnd: Date,
        sessionSummaries: [SessionIntelligence]
    ) throws -> PeriodIntelligence {
        
        // Extract content based on provider
        let contentText: String
        switch selectedProvider {
        case .openai:
            guard let choices = response["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw SummarizationError.decodingFailed("Failed to extract content from OpenAI response")
            }
            contentText = content
            
        case .anthropic:
            contentText = try Self.anthropicText(from: response)
        }
        
        // Parse JSON content
        #if DEBUG
        print("🔍 [ExternalAPIEngine] Raw period API response content:")
        #endif
        #if DEBUG
        print("📄 [ExternalAPIEngine] \(contentText.prefix(500))...")
        #endif
        
        guard let json = ModelJSON.object(from: contentText) else {
            throw SummarizationError.decodingFailed("Failed to parse content as JSON")
        }
        
        #if DEBUG
        print("✅ [ExternalAPIEngine] Successfully parsed period JSON response")
        #endif
        #if DEBUG
        print("🔑 [ExternalAPIEngine] Available keys: \(Array(json.keys))")
        #endif
        
        // For Year Wrap, preserve the entire JSON structure
        let summary: String
        if periodType == .yearWrap {
            // Store the complete JSON as the summary text for Year Wrap
            let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            summary = String(data: jsonData, encoding: .utf8) ?? "No summary available"
            #if DEBUG
            print("📊 [ExternalAPIEngine] Year Wrap: Preserving full JSON structure (\(summary.count) chars)")
            #endif
        } else {
            // For other period types, extract just the summary field
            // Try multiple field names for summary (API might use different conventions)
            if let s = json["summary"] as? String {
                summary = s
            } else if let s = json["period_summary"] as? String {
                summary = s
            } else if let s = json["day_summary"] as? String {
                summary = s
            } else if let s = json["daily_summary"] as? String {
                summary = s
            } else if let s = json["week_summary"] as? String {
                summary = s
            } else if let s = json["weekly_summary"] as? String {
                summary = s
            } else if let s = json["month_summary"] as? String {
                summary = s
            } else if let s = json["monthly_summary"] as? String {
                summary = s
            } else if let s = json["year_summary"] as? String {
                summary = s
            } else if let s = json["yearly_summary"] as? String {
                summary = s
            } else if let s = json["session_summary"] as? String {
                summary = s
            } else if let s = json["text"] as? String {
                summary = s
            } else {
                summary = "No summary available"
            }
            #if DEBUG
            print("📝 [ExternalAPIEngine] Extracted period summary (\(summary.count) chars): \(summary.prefix(100))...")
            #endif
        }
        
        let topics = json["topics"] as? [String] ?? []
        let trends = json["trends"] as? [String]
        
        // Aggregate data from sessions
        let totalDuration = sessionSummaries.reduce(0) { $0 + $1.duration }
        let totalWords = sessionSummaries.reduce(0) { $0 + $1.wordCount }
        let avgSentiment = sessionSummaries.map { $0.sentiment }.reduce(0, +) / Double(sessionSummaries.count)
        
        // Collect all entities
        var entityMap: [String: Entity] = [:]
        for session in sessionSummaries {
            for entity in session.entities {
                entityMap[entity.name] = entity
            }
        }
        
        return PeriodIntelligence(
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            summary: summary,
            topics: topics,
            entities: Array(entityMap.values),
            sentiment: avgSentiment,
            sessionCount: sessionSummaries.count,
            totalDuration: totalDuration,
            totalWordCount: totalWords,
            trends: trends
        )
    }
    
    // MARK: - Utilities
    
    private func checkInternetConnectivity() async -> Bool {
        // Simple connectivity check - try to reach a reliable host
        guard let url = URL(string: "https://www.apple.com") else {
            return false
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    // MARK: - API Key Validation
    
    /// Tests the API key and the model together by sending a tiny real request
    /// with that model, so "Connected" means summaries will actually work.
    /// - Parameters:
    ///   - apiKey: The API key to test
    ///   - provider: The provider (OpenAI or Anthropic)
    ///   - model: The model ID to test. Defaults to the saved model for the provider.
    public func validateAPIKey(_ apiKey: String, for provider: Provider, model: String? = nil) async -> APIKeyValidationResult {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = ExternalModelSettings.normalize(model ?? ExternalModelSettings.model(for: provider))
        
        guard !modelID.isEmpty else {
            return .invalid(reason: "Enter a model ID to test")
        }
        
        let formatValid: Bool
        switch provider {
        case .openai: formatValid = key.hasPrefix("sk-") && key.count > 20
        case .anthropic: formatValid = key.hasPrefix("sk-ant-") && key.count > 20
        }
        guard formatValid else {
            return .invalid(reason: "Invalid API key format for \(provider.displayName)")
        }
        
        guard let url = URL(string: provider.endpoint) else {
            return .invalid(reason: "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        switch provider {
        case .openai:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: Self.buildTestRequestBody(provider: provider, model: modelID))
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .invalid(reason: "Invalid response")
            }
            return Self.interpretTestResponse(statusCode: httpResponse.statusCode, data: data, provider: provider, model: modelID)
        } catch {
            return .invalid(reason: "Network error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Request building and response interpretation (pure, unit tested)
    
    static let anthropicVersion = "2023-06-01"

    /// Thinking counts toward `max_tokens`, so the small caps sized for on-device models
    /// would leave a thinking model no room to answer. Only the Anthropic request uses this floor.
    static let anthropicMinOutputTokens = 16_000
    
    /// Body for a summary request. No `temperature`: newer models (GPT-6 and later)
    /// reject it, and the default works well for summaries.
    static func buildRequestBody(provider: Provider, model: String, systemPrompt: String, userMessage: String, maxTokens: Int = 2000) -> [String: Any] {
        switch provider {
        case .openai:
            return [
                "model": model,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userMessage]
                ],
                "response_format": ["type": "json_object"]
            ]
        case .anthropic:
            return [
                "model": model,
                "system": systemPrompt,
                "messages": [
                    ["role": "user", "content": userMessage]
                ],
                "max_tokens": max(maxTokens, anthropicMinOutputTokens)
            ]
        }
    }
    
    /// Text of an Anthropic reply. Newer models put `thinking` blocks before the answer,
    /// so read every `text` block rather than the first block.
    static func anthropicText(from response: [String: Any]) throws -> String {
        switch response["stop_reason"] as? String {
        case "refusal":
            throw SummarizationError.summarizationFailed("Anthropic declined this request")
        case "max_tokens":
            throw SummarizationError.summarizationFailed("Anthropic reply was cut off at the token limit")
        default:
            break
        }
        let blocks = response["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else {
            throw SummarizationError.decodingFailed("Failed to extract content from Anthropic response")
        }
        return text
    }

    /// OpenAI reports `total_tokens`; Anthropic reports `input_tokens` and `output_tokens`.
    static func tokensUsed(_ response: [String: Any]) -> Int {
        guard let usage = response["usage"] as? [String: Any] else { return 0 }
        if let total = usage["total_tokens"] as? Int { return total }
        return (usage["input_tokens"] as? Int ?? 0) + (usage["output_tokens"] as? Int ?? 0)
    }

    /// Smallest possible request that still proves the key and model work.
    static func buildTestRequestBody(provider: Provider, model: String) -> [String: Any] {
        switch provider {
        case .openai:
            return [
                "model": model,
                "messages": [["role": "user", "content": "Hi"]],
                "max_completion_tokens": 16
            ]
        case .anthropic:
            return [
                "model": model,
                "messages": [["role": "user", "content": "Hi"]],
                "max_tokens": 1
            ]
        }
    }
    
    static func interpretTestResponse(statusCode: Int, data: Data, provider: Provider, model: String) -> APIKeyValidationResult {
        let error = Self.errorInfo(from: data)
        let lowerMessage = error.message?.lowercased() ?? ""
        
        switch statusCode {
        case 200...299:
            return .valid(message: "Connected. \(model) is working.")
        case 401:
            return .invalid(reason: "Invalid API key. Check it and try again.")
        case 402:
            return .invalid(reason: "Billing problem on your \(provider.displayName) account. Check your plan or credits.")
        case 429:
            if error.code == "insufficient_quota" || error.type == "insufficient_quota" {
                return .invalid(reason: "Your \(provider.displayName) account is out of credits or quota.")
            }
            return .valid(message: "Key and model accepted, but you're rate limited right now. Try again in a minute.")
        default:
            break
        }
        
        if isModelNotFound(statusCode: statusCode, data: data) {
            return .invalid(reason: "Model \"\(model)\" wasn't found or isn't available on your account. Check the spelling in the model list.")
        }
        if statusCode == 403 {
            return .invalid(reason: "Your key doesn't have access to \(model).")
        }
        if lowerMessage.contains("credit balance") || lowerMessage.contains("billing") {
            return .invalid(reason: "Billing problem on your \(provider.displayName) account. Check your plan or credits.")
        }
        if statusCode >= 500 {
            return .invalid(reason: "\(provider.displayName) is having problems right now (HTTP \(statusCode)). Try again later.")
        }
        if let message = error.message {
            return .invalid(reason: "\(provider.displayName) error: \(message)")
        }
        return .invalid(reason: "HTTP \(statusCode)")
    }
    
    /// True when the provider says the requested model doesn't exist or can't be used.
    static func isModelNotFound(statusCode: Int, data: Data) -> Bool {
        let error = errorInfo(from: data)
        if error.code == "model_not_found" { return true }
        if statusCode == 404 { return true }
        guard statusCode == 400, let message = error.message?.lowercased() else { return false }
        return message.contains("model") && (message.contains("not found") || message.contains("does not exist") || message.contains("invalid model"))
    }
    
    /// Extracts `error.type`, `error.code` and `error.message` from an OpenAI or Anthropic error body.
    static func errorInfo(from data: Data) -> (type: String?, code: String?, message: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return (nil, nil, nil)
        }
        return (error["type"] as? String, error["code"] as? String, error["message"] as? String)
    }
    
    // MARK: - Performance Monitoring
    
    public func getStatistics() async -> (summariesGenerated: Int, averageTime: TimeInterval, totalTime: TimeInterval, totalTokens: Int) {
        let average = summariesGenerated > 0 ? totalProcessingTime / Double(summariesGenerated) : 0.0
        return (summariesGenerated, average, totalProcessingTime, totalTokensUsed)
    }
    
    public func logPerformanceMetrics() async {
        let stats = await getStatistics()
        #if DEBUG
        print("📊 [ExternalAPIEngine] Performance Metrics:")
        #endif
        #if DEBUG
        print("   - Provider: \(selectedProvider.displayName) (\(selectedModel))")
        #endif
        #if DEBUG
        print("   - Summaries Generated: \(stats.summariesGenerated)")
        #endif
        #if DEBUG
        print("   - Average Processing Time: \(String(format: "%.2f", stats.averageTime))s")
        #endif
        #if DEBUG
        print("   - Total Processing Time: \(String(format: "%.2f", stats.totalTime))s")
        #endif
        #if DEBUG
        print("   - Total Tokens Used: \(stats.totalTokens)")
        #endif
    }
}

// MARK: - TextGenerating

extension ExternalAPIEngine: TextGenerating {
    public nonisolated var inputTokenBudget: Int { 60_000 }
    public nonisolated var outputTokenBudget: Int { 4_000 }

    public func generateText(system: String, user: String, maxTokens: Int) async throws -> String {
        guard let apiKey = await keychainManager.getAPIKey(for: selectedProvider) else {
            throw SummarizationError.configurationError("No API key configured for \(selectedProvider.displayName)")
        }
        let response = try await callAPI(systemPrompt: system, userMessage: user, apiKey: apiKey, maxTokens: maxTokens)
        totalTokensUsed += Self.tokensUsed(response)
        switch selectedProvider {
        case .openai:
            guard let choices = response["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw SummarizationError.decodingFailed("Failed to extract content from OpenAI response")
            }
            return content
        case .anthropic:
            return try Self.anthropicText(from: response)
        }
    }
}


// MARK: - Keychain Manager

/// Manages secure storage of API keys in Keychain
public actor KeychainManager {
    
    public static let shared = KeychainManager()
    
    private init() {}
    
    /// Maps provider to the keychain account key used by the UI
    private func keychainAccount(for provider: ExternalAPIEngine.Provider) -> String {
        switch provider {
        case .openai: return "openai_api_key"
        case .anthropic: return "anthropic_api_key"
        }
    }
    
    public func setAPIKey(_ key: String, for provider: ExternalAPIEngine.Provider) async {
        let service = "com.jsayram.lifewrapped"
        let account = keychainAccount(for: provider)
        
        // Delete existing key
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new key
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    public func getAPIKey(for provider: ExternalAPIEngine.Provider) async -> String? {
        let service = "com.jsayram.lifewrapped"
        let account = keychainAccount(for: provider)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    public func hasAPIKey(for provider: ExternalAPIEngine.Provider) async -> Bool {
        return await getAPIKey(for: provider) != nil
    }
    
    public func deleteAPIKey(for provider: ExternalAPIEngine.Provider) async {
        let service = "com.jsayram.lifewrapped"
        let account = keychainAccount(for: provider)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
