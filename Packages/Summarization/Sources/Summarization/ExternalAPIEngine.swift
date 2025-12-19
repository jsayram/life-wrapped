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
/// - OpenAI (GPT-4, GPT-3.5)
/// - Anthropic (Claude 3.5 Sonnet, Claude 3 Opus)
public actor ExternalAPIEngine: SummarizationEngine {
    
    // MARK: - Types
    
    public enum Provider: String, Codable, CaseIterable, Sendable {
        case openai = "OpenAI"
        case anthropic = "Anthropic"
        
        public var displayName: String { rawValue }
        
        public var defaultModel: String {
            switch self {
            case .openai: return "gpt-4.1"
            case .anthropic: return "claude-sonnet-4-5"
            }
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
    
    // Configuration (nonisolated for UserDefaults access in init)
    private nonisolated let initialProvider: Provider
    private var selectedProvider: Provider
    private var selectedModel: String
    
    // Statistics tracking
    private var summariesGenerated: Int = 0
    private var totalProcessingTime: TimeInterval = 0.0
    private var totalTokensUsed: Int = 0
    
    // MARK: - Initialization
    
    public init(storage: DatabaseManager, keychainManager: KeychainManager = .shared) {
        self.storage = storage
        self.keychainManager = keychainManager
        
        // Load saved preferences (must be done before actor isolation begins)
        let savedProvider = UserDefaults.standard.string(forKey: "externalAPIProvider")
            .flatMap { Provider(rawValue: $0) } ?? Provider.openai
        self.initialProvider = savedProvider
        self.selectedProvider = savedProvider
        self.selectedModel = UserDefaults.standard.string(forKey: "externalAPIModel")
            ?? savedProvider.defaultModel
    }
    
    // MARK: - SummarizationEngine Protocol
    
    public nonisolated var tier: EngineTier {
        .external
    }
    
    public func isAvailable() async -> Bool {
        // Check if API key is configured
        let hasAPIKey = await keychainManager.hasAPIKey(for: selectedProvider)
        
        // Check internet connectivity (simple check)
        let hasInternet = await checkInternetConnectivity()
        
        return hasAPIKey && hasInternet
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
        
        // Build prompt using universal schema
        let prompt = UniversalPrompt.build(
            level: .session,
            input: transcriptText,
            metadata: ["duration": Int(duration), "wordCount": transcriptText.split(separator: " ").count]
        )
        
        // Call API
        let response = try await callAPI(prompt: prompt, apiKey: apiKey)
        
        // Parse response
        let intelligence = try parseSessionResponse(response, sessionId: sessionId, duration: duration, languageCodes: languageCodes)
        
        // Update token usage
        if let tokens = response["usage"] as? [String: Any],
           let totalTokens = tokens["total_tokens"] as? Int {
            totalTokensUsed += totalTokens
        }
        
        return intelligence
    }
    
    public func summarizePeriod(
        periodType: PeriodType,
        sessionSummaries: [SessionIntelligence],
        periodStart: Date,
        periodEnd: Date
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
        
        // Build prompt using universal schema
        let prompt = UniversalPrompt.build(
            level: summaryLevel,
            input: inputJSON,
            metadata: ["sessionCount": sessionSummaries.count, "periodType": periodType.rawValue]
        )
        
        // Call API
        let response = try await callAPI(prompt: prompt, apiKey: apiKey)
        
        // Parse response
        let intelligence = try parsePeriodResponse(response, periodType: periodType, periodStart: periodStart, periodEnd: periodEnd, sessionSummaries: sessionSummaries)
        
        // Update token usage
        if let tokens = response["usage"] as? [String: Any],
           let totalTokens = tokens["total_tokens"] as? Int {
            totalTokensUsed += totalTokens
        }
        
        return intelligence
    }
    
    // MARK: - Configuration
    
    public func setProvider(_ provider: Provider, model: String? = nil) {
        self.selectedProvider = provider
        self.selectedModel = model ?? provider.defaultModel
        
        // Save preferences
        UserDefaults.standard.set(provider.rawValue, forKey: "externalAPIProvider")
        UserDefaults.standard.set(selectedModel, forKey: "externalAPIModel")
    }
    
    public func getProvider() -> (provider: Provider, model: String) {
        return (selectedProvider, selectedModel)
    }
    
    // MARK: - API Calls
    
    private func callAPI(prompt: String, apiKey: String) async throws -> [String: Any] {
        let url = URL(string: selectedProvider.endpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request body based on provider
        let requestBody: [String: Any]
        switch selectedProvider {
        case .openai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            requestBody = [
                "model": selectedModel,
                "messages": [
                    ["role": "user", "content": prompt]
                ],
                "temperature": 0.7,
                "response_format": ["type": "json_object"]
            ]
            
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            requestBody = [
                "model": selectedModel,
                "messages": [
                    ["role": "user", "content": prompt]
                ],
                "max_tokens": 2000,
                "temperature": 0.7
            ]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummarizationError.summarizationFailed("Invalid response from API")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
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
            "Session \(index + 1): \(summary.summary)"
        }.joined(separator: "\n")
        
        return """
        Analyze these \(sessionSummaries.count) session summaries from a \(periodType.displayName) period.
        
        Summaries:
        \(summariesText)
        
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
            guard let content = response["content"] as? [[String: Any]],
                  let firstContent = content.first,
                  let text = firstContent["text"] as? String else {
                throw SummarizationError.decodingFailed("Failed to extract content from Anthropic response")
            }
            contentText = text
        }
        
        // Parse JSON content
        print("🔍 [ExternalAPIEngine] Raw API response content:")
        print("📄 [ExternalAPIEngine] \(contentText.prefix(500))...")
        
        guard let jsonData = contentText.data(using: .utf8) else {
            print("❌ [ExternalAPIEngine] Failed to convert content to UTF-8 data")
            throw SummarizationError.decodingFailed("Failed to convert content to UTF-8 data")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("❌ [ExternalAPIEngine] Content is not valid JSON - using as plain text summary")
            print("📝 [ExternalAPIEngine] Falling back to plain text: \(contentText.prefix(200))...")
            
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
        
        print("✅ [ExternalAPIEngine] Successfully parsed JSON response")
        
        // Try multiple field names for summary (API might use different conventions)
        let summary = json["summary"] as? String 
            ?? json["session_summary"] as? String
            ?? json["text"] as? String
            ?? "No summary available"
        
        print("📝 [ExternalAPIEngine] Extracted summary (\(summary.count) chars): \(summary.prefix(100))...")
        let topics = json["topics"] as? [String] ?? []
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
            keyMoments: keyMoments
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
            guard let content = response["content"] as? [[String: Any]],
                  let firstContent = content.first,
                  let text = firstContent["text"] as? String else {
                throw SummarizationError.decodingFailed("Failed to extract content from Anthropic response")
            }
            contentText = text
        }
        
        // Parse JSON content
        print("🔍 [ExternalAPIEngine] Raw period API response content:")
        print("📄 [ExternalAPIEngine] \(contentText.prefix(500))...")
        
        guard let jsonData = contentText.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw SummarizationError.decodingFailed("Failed to parse content as JSON")
        }
        
        print("✅ [ExternalAPIEngine] Successfully parsed period JSON response")
        print("🔑 [ExternalAPIEngine] Available keys: \(Array(json.keys))")
        
        // Try multiple field names for summary (API might use different conventions)
        // Break into smaller expressions to help the compiler
        let summary: String
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
        
        print("📝 [ExternalAPIEngine] Extracted period summary (\(summary.count) chars): \(summary.prefix(100))...")
        
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
    
    /// Validates an API key by making a minimal test request to the provider
    /// - Parameters:
    ///   - apiKey: The API key to validate
    ///   - provider: The provider (OpenAI or Anthropic)
    /// - Returns: A validation result with success message or error description
    public func validateAPIKey(_ apiKey: String, for provider: Provider) async -> APIKeyValidationResult {
        // First, check format
        let formatValid: Bool
        switch provider {
        case .openai:
            formatValid = apiKey.hasPrefix("sk-") && apiKey.count > 20
        case .anthropic:
            formatValid = apiKey.hasPrefix("sk-ant-") && apiKey.count > 20
        }
        
        guard formatValid else {
            return .invalid(reason: "Invalid API key format for \(provider.displayName)")
        }
        
        // Make a minimal API request to validate the key
        do {
            switch provider {
            case .openai:
                return try await validateOpenAIKey(apiKey)
            case .anthropic:
                return try await validateAnthropicKey(apiKey)
            }
        } catch {
            return .invalid(reason: "Network error: \(error.localizedDescription)")
        }
    }
    
    private func validateOpenAIKey(_ apiKey: String) async throws -> APIKeyValidationResult {
        // Use the models endpoint - minimal request, just lists available models
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            return .invalid(reason: "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return .invalid(reason: "Invalid response")
        }
        
        switch httpResponse.statusCode {
        case 200:
            // Parse to get model count for a nice message
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["data"] as? [[String: Any]] {
                return .valid(message: "✅ Valid! Access to \(models.count) models")
            }
            return .valid(message: "✅ API key is valid")
        case 401:
            return .invalid(reason: "Invalid API key - authentication failed")
        case 403:
            return .invalid(reason: "API key lacks required permissions")
        case 429:
            return .valid(message: "✅ Valid (rate limited, but key works)")
        default:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any],
               let message = error["message"] as? String {
                return .invalid(reason: "API Error: \(message)")
            }
            return .invalid(reason: "HTTP \(httpResponse.statusCode)")
        }
    }
    
    private func validateAnthropicKey(_ apiKey: String) async throws -> APIKeyValidationResult {
        // Anthropic doesn't have a models endpoint, so we make a minimal completion request
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            return .invalid(reason: "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        
        // Minimal request - 1 token max to minimize cost
        let body: [String: Any] = [
            "model": "claude-3-haiku-20240307",  // Cheapest model
            "max_tokens": 1,
            "messages": [
                ["role": "user", "content": "Hi"]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return .invalid(reason: "Invalid response")
        }
        
        switch httpResponse.statusCode {
        case 200:
            return .valid(message: "✅ API key is valid")
        case 401:
            return .invalid(reason: "Invalid API key - authentication failed")
        case 403:
            return .invalid(reason: "API key lacks required permissions")
        case 429:
            return .valid(message: "✅ Valid (rate limited, but key works)")
        case 400:
            // Check if it's a billing/quota error (key is valid but account issue)
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any],
               let errorType = error["type"] as? String {
                if errorType == "invalid_request_error" {
                    return .valid(message: "✅ API key is valid (request validation passed)")
                }
            }
            return .invalid(reason: "Bad request")
        default:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any],
               let message = error["message"] as? String {
                return .invalid(reason: "API Error: \(message)")
            }
            return .invalid(reason: "HTTP \(httpResponse.statusCode)")
        }
    }
    
    // MARK: - Performance Monitoring
    
    public func getStatistics() async -> (summariesGenerated: Int, averageTime: TimeInterval, totalTime: TimeInterval, totalTokens: Int) {
        let average = summariesGenerated > 0 ? totalProcessingTime / Double(summariesGenerated) : 0.0
        return (summariesGenerated, average, totalProcessingTime, totalTokensUsed)
    }
    
    public func logPerformanceMetrics() async {
        let stats = await getStatistics()
        print("📊 [ExternalAPIEngine] Performance Metrics:")
        print("   - Provider: \(selectedProvider.displayName) (\(selectedModel))")
        print("   - Summaries Generated: \(stats.summariesGenerated)")
        print("   - Average Processing Time: \(String(format: "%.2f", stats.averageTime))s")
        print("   - Total Processing Time: \(String(format: "%.2f", stats.totalTime))s")
        print("   - Total Tokens Used: \(stats.totalTokens)")
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
