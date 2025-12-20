//
//  SummarizationCoordinator.swift
//  Summarization
//
//  Created by Life Wrapped on 12/16/2025.
//

import Foundation
import SharedModels
import Storage
import LocalLLM  // Required for LocalEngine

/// Orchestrates summarization across multiple engines (Basic, Apple, Local, External)
/// Selects the appropriate engine based on availability and user settings
public actor SummarizationCoordinator {
    
    // MARK: - Properties
    
    private let storage: DatabaseManager
    
    // Available engines
    private var basicEngine: BasicEngine
    private var appleEngine: (any SummarizationEngine)?
    private var localEngine: (any SummarizationEngine)?
    private var externalEngine: (any SummarizationEngine)?
    private var localConfiguration: LocalLLMConfiguration = .current()
    
    // Current active engine
    private var activeEngine: any SummarizationEngine
    
    // User preference for engine tier (can be overridden by availability)
    private var preferredTier: EngineTier = .basic
    
    // Key for persisting engine preference
    private static let preferredEngineKey = "preferredIntelligenceEngine"
    
    // MARK: - Initialization
    
    public init(storage: DatabaseManager) {
        self.storage = storage
        
        // Initialize basic engine (always available)
        self.basicEngine = BasicEngine(storage: storage)
        self.activeEngine = basicEngine
        
        // Initialize Apple Intelligence engine (Phase 2B - iOS 18.1+)
        if #available(iOS 18.1, *) {
            self.appleEngine = AppleEngine(storage: storage)
        }
        
        // Initialize local engine (Phase 2A)
        self.localEngine = LocalEngine(storage: storage, configuration: .defaults(for: .local), localConfiguration: localConfiguration)
        
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
        // Check if Local AI model is available - if so, always prefer it
        let modelManager = ModelFileManager.shared
        let localModelAvailable = await modelManager.availableModels().isEmpty == false
        
        if localModelAvailable {
            // Local AI should ALWAYS be the default when model is downloaded
            preferredTier = .local
            UserDefaults.standard.set(EngineTier.local.rawValue, forKey: Self.preferredEngineKey)
            print("🧠 [SummarizationCoordinator] Local AI model available - setting as default")
        } else if let savedPreference = UserDefaults.standard.string(forKey: Self.preferredEngineKey),
                  let tier = EngineTier(rawValue: savedPreference) {
            preferredTier = tier
            print("📝 [SummarizationCoordinator] Restoring saved preference: \(tier.displayName)")
        }
        await applyLocalPreset()
        
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
        
        if let apple = appleEngine, await apple.isAvailable() {
            available.append(.apple)
        }
        
        if let local = localEngine, await local.isAvailable() {
            available.append(.local)
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
    /// Will fall back to basic if preferred tier is unavailable
    /// Persists the preference to UserDefaults
    public func setPreferredEngine(_ tier: EngineTier) async {
        preferredTier = tier
        UserDefaults.standard.set(tier.rawValue, forKey: Self.preferredEngineKey)
        print("💾 [SummarizationCoordinator] Saved engine preference: \(tier.displayName)")
        await selectBestAvailableEngine()
    }

    /// Run a raw prompt through the local engine for debugging
    public func runLocalDebugPrompt(_ prompt: String) async -> String {
        guard let local = localEngine as? LocalEngine else {
            return "Local engine unavailable"
        }
        do {
            return try await local.debugGenerate(prompt: prompt)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    public func setLocalPresetOverride(_ preset: LocalLLMConfiguration.Preset?) async {
        LocalLLMConfiguration.persistPresetOverride(preset)
        await applyLocalPreset()
        await selectBestAvailableEngine()
        await MainActor.run {
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
        }
    }

    public func getLocalConfiguration() -> LocalLLMConfiguration {
        localConfiguration
    }
    
    /// Select the best available engine based on user preference
    private func selectBestAvailableEngine() async {
        // Try preferred engine first
        switch preferredTier {
        case .basic:
            activeEngine = basicEngine
            return
            
        case .apple:
            if let apple = appleEngine, await apple.isAvailable() {
                activeEngine = apple
                return
            }
            
        case .local:
            if let local = localEngine, await local.isAvailable() {
                activeEngine = local
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

    private func applyLocalPreset() async {
        let profile = LocalLLMConfiguration.DeviceProfile.current
        localConfiguration = LocalLLMConfiguration.current(profile: profile)
        if let local = localEngine as? LocalEngine {
            await local.updateLocalConfiguration(localConfiguration)
        }
        print("⚙️ [SummarizationCoordinator] Local preset set to \(localConfiguration.preset.displayName) (\(localConfiguration.tokensDescription))")
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
        
        // Combine transcript text
        let transcriptText = segments.map { $0.text }.joined(separator: " ")
        
        // Calculate duration from segments
        let duration = segments.map { $0.duration }.reduce(0, +)
        
        // Extract language codes
        let languageCodes = Array(Set(segments.map { $0.languageCode }))
        
        // Generate intelligence using active engine
        let intelligence = try await activeEngine.summarizeSession(
            sessionId: sessionId,
            transcriptText: transcriptText,
            duration: duration,
            languageCodes: languageCodes
        )
        
        // Convert to Summary for database storage
        return try convertToSummary(intelligence: intelligence)
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

    /// Generate a Year Wrap summary using the external engine and higher-level rollups
    public func generateYearWrapSummary(
        startOfYear: Date,
        endOfYear: Date,
        sourceSummaries: [Summary]
    ) async throws -> Summary {
        guard !sourceSummaries.isEmpty else {
            throw SummarizationError.noTranscriptData
        }

        guard let external = externalEngine else {
            throw SummarizationError.summarizationFailed("External engine not available for Year Wrap")
        }

        guard await external.isAvailable() else {
            throw SummarizationError.summarizationFailed("External engine unavailable or missing credentials for Year Wrap")
        }

        let previousEngine = activeEngine
        activeEngine = external
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
                languageCodes: ["en-US"]
            )
        }

        let intelligence = try await external.summarizePeriod(
            periodType: .yearWrap,
            sessionSummaries: intelligences,
            periodStart: startOfYear,
            periodEnd: endOfYear
        )

        return try convertToSummary(periodIntelligence: intelligence)
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
            periodEnd: endDate
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
    
    /// Register local model engine (when implemented)
    public func registerLocalEngine(_ engine: any SummarizationEngine) async {
        guard engine.tier == .local else { return }
        self.localEngine = engine
        await selectBestAvailableEngine()
    }
    
    /// Register external API engine (when implemented)
    public func registerExternalEngine(_ engine: any SummarizationEngine) async {
        guard engine.tier == .external else { return }
        self.externalEngine = engine
        await selectBestAvailableEngine()
    }
}
