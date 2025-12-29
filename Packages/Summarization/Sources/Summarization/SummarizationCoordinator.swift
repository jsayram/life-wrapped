//
//  SummarizationCoordinator.swift
//  Summarization
//
//  Created by Life Wrapped on 12/16/2025.
//

import Foundation
import SharedModels
import Storage
import LocalLLM

/// Orchestrates summarization across multiple engines (Basic, Local, Apple, External)
/// Selects the appropriate engine based on availability and user settings
public actor SummarizationCoordinator {
    
    // MARK: - Properties
    
    private let storage: DatabaseManager
    private let keychainManager: KeychainManager
    
    // Available engines
    private var basicEngine: BasicEngine
    private var localEngine: LocalEngine
    private var appleEngine: (any SummarizationEngine)?
    private var externalEngine: (any SummarizationEngine)?
    
    // Current active engine
    private var activeEngine: any SummarizationEngine
    
    // User preference for engine tier (can be overridden by availability)
    private var preferredTier: EngineTier = .basic
    
    // Key for persisting engine preference
    private static let preferredEngineKey = "preferredIntelligenceEngine"
    
    // MARK: - Initialization
    
    public init(storage: DatabaseManager, keychainManager: KeychainManager = .shared) {
        self.storage = storage
        self.keychainManager = keychainManager
        
        // Initialize basic engine (always available)
        self.basicEngine = BasicEngine(storage: storage)
        self.activeEngine = basicEngine
        
        // Initialize local LLM engine (Phi-3.5)
        self.localEngine = LocalEngine()
        
        // Initialize Apple Intelligence engine (Phase 2B - iOS 18.1+)
        if #available(iOS 18.1, *) {
            self.appleEngine = AppleEngine(storage: storage)
        }
        
        // Initialize external API engine (Phase 2C)
        self.externalEngine = ExternalAPIEngine(storage: storage)
        
        // Load saved preference synchronously (will apply properly in restoreSavedPreference)
        if let savedPreference = UserDefaults.standard.string(forKey: Self.preferredEngineKey),
           let tier = EngineTier(rawValue: savedPreference) {
            self.preferredTier = tier
            print("📝 [SummarizationCoordinator] Loaded saved preference: \(tier.displayName)")
        }
    }
    
    /// Restore saved preference and select appropriate engine
    /// Call this after initialization to properly set up the active engine
    public func restoreSavedPreference() async {
        // Load saved preference from UserDefaults
        if let savedPreference = UserDefaults.standard.string(forKey: Self.preferredEngineKey),
           let tier = EngineTier(rawValue: savedPreference) {
            preferredTier = tier
            print("📝 [SummarizationCoordinator] Restoring saved preference: \(tier.displayName)")
        } else {
            // No saved preference - default to External if API key exists, else Basic
            if let external = externalEngine, await external.isAvailable() {
                preferredTier = .external
                UserDefaults.standard.set(EngineTier.external.rawValue, forKey: Self.preferredEngineKey)
                print("🧠 [SummarizationCoordinator] No preference set - defaulting to External AI")
            } else {
                preferredTier = .basic
                print("🧠 [SummarizationCoordinator] No preference set - defaulting to Basic")
            }
        }
        
        await selectBestAvailableEngine()
        print("✅ [SummarizationCoordinator] Active engine: \(activeEngine.tier.displayName)")
    }
    
    // MARK: - Engine Management
    
    /// Get the currently active engine
    public func getActiveEngine() -> EngineTier {
        return activeEngine.tier
    }
    
    /// Get all available engine tiers
    public func getAvailableEngines() async -> [EngineTier] {
        var available: [EngineTier] = []
        
        if await basicEngine.isAvailable() {
            available.append(.basic)
        }
        
        if await localEngine.isAvailable() {
            available.append(.local)
        }
        
        if let apple = appleEngine, await apple.isAvailable() {
            available.append(.apple)
        }
        
        if let external = externalEngine, await external.isAvailable() {
            available.append(.external)
        }
        
        return available
    }
    
    /// Validate an external API key by making a test request
    /// - Parameters:
    ///   - apiKey: The API key to validate
    ///   - provider: The provider (OpenAI or Anthropic)
    /// - Returns: Validation result with success message or error
    public func validateExternalAPIKey(_ apiKey: String, for provider: ExternalAPIEngine.Provider) async -> ExternalAPIEngine.APIKeyValidationResult {
        guard let external = externalEngine as? ExternalAPIEngine else {
            return .invalid(reason: "External API engine not available")
        }
        return await external.validateAPIKey(apiKey, for: provider)
    }
    
    /// Set the preferred engine tier
    /// Will fall back to highest available engine if preferred tier is unavailable
    /// Only persists the preference if the engine is actually available
    public func setPreferredEngine(_ tier: EngineTier) async {
        preferredTier = tier
        
        // Check if the preferred tier is actually available
        let isAvailable = await checkEngineAvailability(tier)
        
        // Only persist if available, otherwise fallback without persisting
        if isAvailable {
            UserDefaults.standard.set(tier.rawValue, forKey: Self.preferredEngineKey)
            print("💾 [SummarizationCoordinator] Saved engine preference: \(tier.displayName)")
        } else {
            print("⚠️ [SummarizationCoordinator] Engine \(tier.displayName) not available, falling back without persisting")
            // Find highest available engine to persist instead
            let fallbackTier = await determineFallbackEngine()
            UserDefaults.standard.set(fallbackTier.rawValue, forKey: Self.preferredEngineKey)
            print("💾 [SummarizationCoordinator] Persisting fallback: \(fallbackTier.displayName)")
        }
        
        await selectBestAvailableEngine()
    }
    
    /// Check if a specific engine tier is available
    private func checkEngineAvailability(_ tier: EngineTier) async -> Bool {
        switch tier {
        case .basic:
            return true // Always available
        case .local:
            return await localEngine.isAvailable()
        case .apple:
            guard let apple = appleEngine else { return false }
            return await apple.isAvailable()
        case .external:
            guard let external = externalEngine else { return false }
            return await external.isAvailable()
        }
    }
    
    /// Determine the highest available fallback engine
    private func determineFallbackEngine() async -> EngineTier {
        if await localEngine.isAvailable() {
            return .local
        } else if let apple = appleEngine, await apple.isAvailable() {
            return .apple
        } else {
            return .basic
        }
    }
    
    /// Select the best available engine based on user preference
    private func selectBestAvailableEngine() async {
        // Try preferred engine first
        switch preferredTier {
        case .basic:
            activeEngine = basicEngine
            return
            
        case .local:
            if await localEngine.isAvailable() {
                activeEngine = localEngine
                return
            }
            
        case .apple:
            if let apple = appleEngine, await apple.isAvailable() {
                activeEngine = apple
                return
            }
            
        case .external:
            if let external = externalEngine, await external.isAvailable() {
                activeEngine = external
                return
            }
        }
        
        // Fallback to basic if preferred unavailable
        activeEngine = basicEngine
    }
    
    // MARK: - Chunk-Level Summarization (Local AI)
    
    /// Summarize a single chunk using the local LLM engine
    /// Called after transcription completes for each chunk when using Local AI tier
    /// - Parameters:
    ///   - chunkId: The UUID of the audio chunk
    ///   - transcriptText: The transcribed text for this chunk
    /// - Returns: AI-generated summary of the chunk
    /// - Throws: Error if summarization fails
    public func summarizeChunk(
        chunkId: UUID,
        transcriptText: String
    ) async throws -> String {
        // Only use local engine for chunk summarization
        let isLocalAvailable = await localEngine.isAvailable()
        if preferredTier == .local && isLocalAvailable {
            return try await localEngine.summarizeChunk(
                chunkId: chunkId,
                transcriptText: transcriptText
            )
        }
        
        // For other tiers, skip per-chunk summarization
        // (full text will be summarized at session level)
        return ""
    }
    
    /// Check if the active tier supports per-chunk AI processing
    public func supportsChunkProcessing() -> Bool {
        return preferredTier == .local
    }
    
    /// Get the local engine for direct access (for loading model, etc.)
    public func getLocalEngine() -> LocalEngine {
        return localEngine
    }
    
    // MARK: - Session Summarization
    
    /// Generate a session-level summary from transcript segments
    /// - Parameters:
    ///   - sessionId: The UUID of the recording session
    ///   - segments: Array of transcript segments
    /// - Returns: Summary object ready for database storage
    /// - Throws: SummarizationError if generation fails
    public func generateSessionSummary(
        sessionId: UUID,
        segments: [TranscriptSegment]
    ) async throws -> Summary {
        guard !segments.isEmpty else {
            throw SummarizationError.noTranscriptData
        }
        
        // Check if preferred engine is available
        if activeEngine.tier != preferredTier {
            print("⚠️ [SummarizationCoordinator] Preferred engine (\(preferredTier.displayName)) unavailable, using \(activeEngine.tier.displayName)")
            
            // If user selected external but it's not available, throw clear error
            if preferredTier == .external {
                if let external = externalEngine, await !external.isAvailable() {
                    // Check specific reason
                    let externalAPIEngine = external as? ExternalAPIEngine
                    let provider = await externalAPIEngine?.getProvider().provider ?? .openai
                    let hasAPIKey = await keychainManager.hasAPIKey(for: provider)
                    if !hasAPIKey {
                        throw SummarizationError.configurationError("Year Wrapped Pro AI requires an API key. Please add your OpenAI or Anthropic key in Settings → AI & Intelligence.")
                    } else {
                        throw SummarizationError.configurationError("Year Wrapped Pro AI requires internet connection.")
                    }
                }
            }
        }
        
        // Combine transcript text
        let transcriptText = segments.map { $0.text }.joined(separator: " ")
        
        // Calculate duration from segments
        let duration = segments.map { $0.duration }.reduce(0, +)
        
        // Extract language codes
        let languageCodes = Array(Set(segments.map { $0.languageCode }))
        
        // Try active engine first, with automatic fallback on failure
        var lastError: Error?
        var engineToTry = activeEngine
        
        // Define fallback chain: External → Local → Basic
        // Apple Intelligence is not in automatic fallback - user must explicitly select it
        let fallbackChain: [EngineTier] = [.external, .local, .basic]
        var triedEngines: [EngineTier] = []
        
        for tier in fallbackChain {
            // Skip if we've already tried this tier
            if triedEngines.contains(tier) {
                continue
            }
            
            // Get the engine for this tier
            if tier == activeEngine.tier {
                engineToTry = activeEngine
            } else if tier == .local {
                engineToTry = localEngine
            } else if tier == .apple, let apple = appleEngine {
                engineToTry = apple
            } else if tier == .external, let external = externalEngine {
                engineToTry = external
            } else if tier == .basic {
                engineToTry = basicEngine
            } else {
                continue // Skip unavailable engines
            }
            
            // Check if engine is available
            let isAvailable = await engineToTry.isAvailable()
            if !isAvailable {
                print("⚠️ [SummarizationCoordinator] \(tier.displayName) unavailable, trying next engine...")
                triedEngines.append(tier)
                continue
            }
            
            triedEngines.append(tier)
            
            do {
                print("🧠 [SummarizationCoordinator] Attempting summarization with \(tier.displayName)...")
                
                // Generate intelligence using this engine
                let intelligence = try await engineToTry.summarizeSession(
                    sessionId: sessionId,
                    transcriptText: transcriptText,
                    duration: duration,
                    languageCodes: languageCodes
                )
                
                // Success! Convert to Summary and return
                print("✅ [SummarizationCoordinator] Successfully generated summary with \(tier.displayName)")
                return try convertToSummary(intelligence: intelligence)
                
            } catch {
                print("❌ [SummarizationCoordinator] \(tier.displayName) failed: \(error.localizedDescription)")
                lastError = error
                
                // If this is External API and failed, try fallback immediately
                if tier == .external {
                    print("🔄 [SummarizationCoordinator] Network error detected, falling back to on-device engines...")
                    continue
                }
                
                // For other engines, if there are more to try, continue
                if triedEngines.count < fallbackChain.count {
                    continue
                } else {
                    // All engines failed
                    throw error
                }
            }
        }
        
        // If we get here, all engines failed
        if let error = lastError {
            throw error
        } else {
            throw SummarizationError.summarizationFailed("All summarization engines unavailable")
        }
    }
    
    // MARK: - Period Summarization
    
    /// Generate a daily summary by aggregating session summaries
    /// - Parameter date: The date to summarize
    /// - Returns: Summary object ready for database storage
    /// - Throws: SummarizationError if generation fails
    public func generateDailySummary(for date: Date) async throws -> Summary {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw SummarizationError.invalidDateRange(start: startOfDay, end: date)
        }
        
        return try await generatePeriodSummary(
            periodType: .day,
            startDate: startOfDay,
            endDate: endOfDay
        )
    }
    
    /// Generate a weekly summary by aggregating daily summaries
    /// - Parameter date: A date within the week to summarize
    /// - Returns: Summary object ready for database storage
    /// - Throws: SummarizationError if generation fails
    public func generateWeeklySummary(for date: Date) async throws -> Summary {
        let calendar = Calendar.current
        
        // Get start of week (Sunday)
        let weekday = calendar.component(.weekday, from: date)
        let daysToSubtract = weekday - 1
        guard let startOfWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: date) else {
            throw SummarizationError.invalidDateRange(start: date, end: date)
        }
        let startOfWeekDay = calendar.startOfDay(for: startOfWeek)
        
        // Get end of week
        guard let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeekDay) else {
            throw SummarizationError.invalidDateRange(start: startOfWeekDay, end: date)
        }
        
        return try await generatePeriodSummary(
            periodType: .week,
            startDate: startOfWeekDay,
            endDate: endOfWeek
        )
    }
    
    /// Generate a monthly summary by aggregating weekly summaries
    /// - Parameter date: A date within the month to summarize
    /// - Returns: Summary object ready for database storage
    /// - Throws: SummarizationError if generation fails
    public func generateMonthlySummary(for date: Date) async throws -> Summary {
        let calendar = Calendar.current
        
        // Get start of month
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let startOfMonth = calendar.date(from: components) else {
            throw SummarizationError.invalidDateRange(start: date, end: date)
        }
        
        // Get end of month (start of next month)
        guard let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            throw SummarizationError.invalidDateRange(start: startOfMonth, end: date)
        }
        
        return try await generatePeriodSummary(
            periodType: .month,
            startDate: startOfMonth,
            endDate: endOfMonth
        )
    }

    // MARK: - Yearly Summarization
    
    /// Generate a yearly summary by aggregating monthly summaries
    /// - Parameter date: A date within the year to summarize
    /// - Returns: Summary object ready for database storage
    /// - Throws: SummarizationError if generation fails
    public func generateYearlySummary(for date: Date) async throws -> Summary {
        let calendar = Calendar.current
        
        // Get start of year
        let components = calendar.dateComponents([.year], from: date)
        guard let startOfYear = calendar.date(from: components) else {
            throw SummarizationError.invalidDateRange(start: date, end: date)
        }
        
        // Get end of year (start of next year)
        guard let endOfYear = calendar.date(byAdding: .year, value: 1, to: startOfYear) else {
            throw SummarizationError.invalidDateRange(start: startOfYear, end: date)
        }
        
        return try await generatePeriodSummary(
            periodType: .year,
            startDate: startOfYear,
            endDate: endOfYear
        )
    }

    /// Generate a Year Wrap summary using the specified engine (External or Local AI)
    public func generateYearWrapSummary(
        startOfYear: Date,
        endOfYear: Date,
        sourceSummaries: [Summary],
        workSessionCount: Int,
        personalSessionCount: Int,
        useLocalAI: Bool = false
    ) async throws -> Summary {
        guard !sourceSummaries.isEmpty else {
            throw SummarizationError.noTranscriptData
        }

        // Select engine based on user choice
        let engine: any SummarizationEngine
        let engineTier: String
        
        if useLocalAI {
            // Use Local AI (Phi-3.5 Mini)
            guard await localEngine.isAvailable() else {
                throw SummarizationError.summarizationFailed("Local AI engine not available. Please download the model first.")
            }
            engine = localEngine
            engineTier = EngineTier.local.rawValue
            print("🤖 [SummarizationCoordinator] Using Local AI for Year Wrap")
        } else {
            // Use External API (OpenAI/Anthropic)
            guard let external = externalEngine else {
                throw SummarizationError.summarizationFailed("External engine not available for Year Wrap")
            }
            guard await external.isAvailable() else {
                throw SummarizationError.summarizationFailed("External engine unavailable or missing credentials for Year Wrap")
            }
            engine = external
            engineTier = EngineTier.external.rawValue
            print("☁️ [SummarizationCoordinator] Using External API for Year Wrap")
        }

        let previousEngine = activeEngine
        activeEngine = engine
        defer { activeEngine = previousEngine }

        let intelligences = sourceSummaries.map { summary -> SessionIntelligence in
            let topics = (try? [String].fromTopicsJSON(summary.topicsJSON)) ?? []
            let entities = (try? [Entity].fromEntitiesJSON(summary.entitiesJSON)) ?? []
            let wordCount = summary.text.split(separator: " ").count

            return SessionIntelligence(
                sessionId: summary.id,
                summary: summary.text,
                topics: topics,
                entities: entities,
                sentiment: 0.0,
                duration: summary.periodEnd.timeIntervalSince(summary.periodStart),
                wordCount: wordCount,
                languageCodes: ["en-US"],
                category: nil  // Monthly summaries don't have single category
            )
        }

        // Build category context from session counts
        let categoryContext = buildCategoryContext(workCount: workSessionCount, personalCount: personalSessionCount)

        let intelligence = try await engine.summarizePeriod(
            periodType: .yearWrap,
            sessionSummaries: intelligences,
            periodStart: startOfYear,
            periodEnd: endOfYear,
            categoryContext: categoryContext
        )

        return try convertToSummary(periodIntelligence: intelligence)
    }
    
    /// Build category context string for AI prompt
    private func buildCategoryContext(workCount: Int, personalCount: Int) -> String? {
        guard workCount > 0 || personalCount > 0 else { return nil }
        
        let total = workCount + personalCount
        let workPercent = total > 0 ? Int((Double(workCount) / Double(total)) * 100) : 0
        let personalPercent = total > 0 ? Int((Double(personalCount) / Double(total)) * 100) : 0
        
        return """
        SESSION CATEGORY DISTRIBUTION:
        - Work sessions: \(workCount) (\(workPercent)%)
        - Personal sessions: \(personalCount) (\(personalPercent)%)
        
        CLASSIFICATION RULES (MANDATORY):
        1. Classify ~\(workPercent)% of items as "work" and ~\(personalPercent)% as "personal"
        2. Work items: professional topics, projects, meetings, career-related
        3. Personal items: hobbies, family, health, personal goals, non-work activities
        4. Use "both" ONLY if an item genuinely spans both domains (rare, <10% of items)
        5. When uncertain, use the proportional split as a guide
        """
    }
    
    /// Generate a period summary by aggregating session-level summaries
    private func generatePeriodSummary(
        periodType: PeriodType,
        startDate: Date,
        endDate: Date
    ) async throws -> Summary {
        // Fetch all session summaries for this period from database
        let sessionSummaries = try await storage.fetchSummaries(periodType: .session)
            .filter { summary in
                guard summary.sessionId != nil else { return false }
                // Check if session's period overlaps with our date range
                return summary.periodStart >= startDate && summary.periodStart < endDate
            }
        
        guard !sessionSummaries.isEmpty else {
            throw SummarizationError.noTranscriptData
        }
        
        // Convert Summary objects to SessionIntelligence
        let intelligences = sessionSummaries.compactMap { summary -> SessionIntelligence? in
            guard let sessionId = summary.sessionId else { return nil }
            
            // Parse topics and entities from JSON
            let topics = try? [String].fromTopicsJSON(summary.topicsJSON)
            let entities = try? [Entity].fromEntitiesJSON(summary.entitiesJSON)
            
            // Calculate duration and word count (we need to fetch from segments)
            // For now, use defaults - can be enhanced to fetch actual values
            let duration: TimeInterval = 0  // Will be calculated from segments if needed
            let wordCount = summary.text.split(separator: " ").count
            
            return SessionIntelligence(
                sessionId: sessionId,
                summary: summary.text,
                topics: topics ?? [],
                entities: entities ?? [],
                sentiment: 0.0,  // Default neutral
                duration: duration,
                wordCount: wordCount,
                languageCodes: ["en-US"]
            )
        }
        
        // Generate period intelligence using active engine
        let intelligence = try await activeEngine.summarizePeriod(
            periodType: periodType,
            sessionSummaries: intelligences,
            periodStart: startDate,
            periodEnd: endDate,
            categoryContext: nil
        )
        
        // Convert to Summary for database storage
        return try convertToSummary(periodIntelligence: intelligence)
    }
    
    // MARK: - Conversion Helpers
    
    /// Convert SessionIntelligence to Summary for database storage
    private func convertToSummary(intelligence: SessionIntelligence) throws -> Summary {
        let topicsJSON = try intelligence.topicsJSON()
        let entitiesJSON = try intelligence.entitiesJSON()
        
        return Summary(
            periodType: .session,
            periodStart: Date(),  // Will be updated by caller
            periodEnd: Date(),
            text: intelligence.summary,
            createdAt: Date(),
            sessionId: intelligence.sessionId,
            topicsJSON: topicsJSON,
            entitiesJSON: entitiesJSON,
            engineTier: activeEngine.tier.rawValue
        )
    }
    
    /// Convert PeriodIntelligence to Summary for database storage
    private func convertToSummary(periodIntelligence: PeriodIntelligence) throws -> Summary {
        let topicsJSON = try periodIntelligence.topicsJSON()
        let entitiesJSON = try periodIntelligence.entitiesJSON()
        
        return Summary(
            periodType: periodIntelligence.periodType,
            periodStart: periodIntelligence.periodStart,
            periodEnd: periodIntelligence.periodEnd,
            text: periodIntelligence.summary,
            createdAt: Date(),
            sessionId: nil,  // Period summaries don't have sessionId
            topicsJSON: topicsJSON,
            entitiesJSON: entitiesJSON,
            engineTier: activeEngine.tier.rawValue
        )
    }
    
    // MARK: - Statistics
    
    /// Get statistics from the active engine
    public func getStatistics() async -> (summariesGenerated: Int, averageProcessingTime: TimeInterval) {
        // For now, only BasicEngine has statistics
        if activeEngine.tier == .basic {
            return await basicEngine.getStatistics()
        }
        return (0, 0)
    }
    
    /// Reset statistics for the active engine
    public func resetStatistics() async {
        if activeEngine.tier == .basic {
            await basicEngine.resetStatistics()
        }
    }
}

// MARK: - Engine Registration (for future use)

extension SummarizationCoordinator {
    
    /// Register Apple Intelligence engine (when implemented)
    public func registerAppleEngine(_ engine: any SummarizationEngine) async {
        guard engine.tier == .apple else { return }
        self.appleEngine = engine
        await selectBestAvailableEngine()
    }
    
    /// Register external API engine (when implemented)
    public func registerExternalEngine(_ engine: any SummarizationEngine) async {
        guard engine.tier == .external else { return }
        self.externalEngine = engine
        await selectBestAvailableEngine()
    }
}
