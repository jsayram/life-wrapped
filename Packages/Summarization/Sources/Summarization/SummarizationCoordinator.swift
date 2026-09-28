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
        
        // Initialize local LLM engine (Smart tier)
        self.localEngine = LocalEngine()
        
        // Initialize Apple Intelligence engine
        // iOS 26.0+ has Foundation Models API for programmatic access
        // iOS 18.1-25.x has Apple Intelligence but no public API
        if #available(iOS 26.0, macOS 26.0, *) {
            self.appleEngine = AppleEngine(storage: storage)
        } else if #available(iOS 18.1, *) {
            self.appleEngine = AppleEngineLegacy(storage: storage)
        }
        
        // Initialize external API engine (Phase 2C)
        self.externalEngine = ExternalAPIEngine(storage: storage)
        
        // Load saved preference synchronously (will apply properly in restoreSavedPreference)
        if let savedPreference = UserDefaults.standard.string(forKey: Self.preferredEngineKey),
           let tier = EngineTier(rawValue: savedPreference) {
            self.preferredTier = tier
            #if DEBUG
            print("📝 [SummarizationCoordinator] Loaded saved preference: \(tier.displayName)")
            #endif
        }
    }
    
    /// Restore saved preference and select appropriate engine
    /// Call this after initialization to properly set up the active engine
    public func restoreSavedPreference() async {
        // Delete Smart models this device doesn't use: Phi-3.5 from before Qwen3 (about 2.1 GB), or the
        // Qwen3 size meant for other devices (4 GB phones used to get the 2.3 GB Qwen3 4B).
        // If Smart was selected, it falls back to the next tier until the new model is downloaded,
        // and Settings explains why.
        if await localEngine.removeRetiredModels() {
            UserDefaults.standard.set(true, forKey: LocalEngine.modelReplacedNoticeKey)
            #if DEBUG
            print("🧹 [SummarizationCoordinator] Removed a local model this device does not use")
            #endif
        }
        
        // Load saved preference from UserDefaults
        if let savedPreference = UserDefaults.standard.string(forKey: Self.preferredEngineKey),
           let tier = EngineTier(rawValue: savedPreference) {
            preferredTier = tier
            #if DEBUG
            print("📝 [SummarizationCoordinator] Restoring saved preference: \(tier.displayName)")
            #endif
        } else {
            // No saved preference - select best available default
            // Priority: External (user configured) > Apple Intelligence > Local AI > Basic
            if let external = externalEngine, await external.isAvailable() {
                preferredTier = .external
                UserDefaults.standard.set(EngineTier.external.rawValue, forKey: Self.preferredEngineKey)
                #if DEBUG
                print("🧠 [SummarizationCoordinator] No preference set - defaulting to External AI (user configured)")
                #endif
            } else if let apple = appleEngine, await apple.isAvailable() {
                preferredTier = .apple
                UserDefaults.standard.set(EngineTier.apple.rawValue, forKey: Self.preferredEngineKey)
                #if DEBUG
                print("🧠 [SummarizationCoordinator] No preference set - defaulting to Apple Intelligence (on-device)")
                #endif
            } else if await localEngine.isAvailable() {
                preferredTier = .local
                UserDefaults.standard.set(EngineTier.local.rawValue, forKey: Self.preferredEngineKey)
                #if DEBUG
                print("🧠 [SummarizationCoordinator] No preference set - defaulting to Local AI (downloaded)")
                #endif
            } else {
                preferredTier = .basic
                #if DEBUG
                print("🧠 [SummarizationCoordinator] No preference set - defaulting to Key Sentences")
                #endif
            }
        }
        
        await selectBestAvailableEngine()
        #if DEBUG
        print("✅ [SummarizationCoordinator] Active engine: \(activeEngine.tier.displayName)")
        #endif
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
    ///   - model: The model ID to test (defaults to the saved model)
    /// - Returns: Validation result with success message or error
    public func validateExternalAPIKey(_ apiKey: String, for provider: ExternalAPIEngine.Provider, model: String? = nil) async -> ExternalAPIEngine.APIKeyValidationResult {
        guard let external = externalEngine as? ExternalAPIEngine else {
            return .invalid(reason: "External API engine not available")
        }
        return await external.validateAPIKey(apiKey, for: provider, model: model)
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
            #if DEBUG
            print("💾 [SummarizationCoordinator] Saved engine preference: \(tier.displayName)")
            #endif
        } else {
            #if DEBUG
            print("⚠️ [SummarizationCoordinator] Engine \(tier.displayName) not available, falling back without persisting")
            #endif
            // Find highest available engine to persist instead
            let fallbackTier = await determineFallbackEngine()
            UserDefaults.standard.set(fallbackTier.rawValue, forKey: Self.preferredEngineKey)
            #if DEBUG
            print("💾 [SummarizationCoordinator] Persisting fallback: \(fallbackTier.displayName)")
            #endif
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
    /// Priority: Apple Intelligence > Local AI > Basic
    /// Note: External is not included as fallback since it requires user configuration
    private func determineFallbackEngine() async -> EngineTier {
        if let apple = appleEngine, await apple.isAvailable() {
            return .apple
        } else if await localEngine.isAvailable() {
            return .local
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
    ) async throws -> (summary: Summary, title: String?) {
        guard !segments.isEmpty else {
            throw SummarizationError.noTranscriptData
        }
        
        // Check if preferred engine is available
        if activeEngine.tier != preferredTier {
            #if DEBUG
            print("⚠️ [SummarizationCoordinator] Preferred engine (\(preferredTier.displayName)) unavailable, using \(activeEngine.tier.displayName)")
            #endif
            
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
        
        // Start with the engine the user chose, then fall back only to on-device engines.
        // Never escalate to the cloud unless the user picked External.
        let fallbackChain = Self.fallbackChain(for: preferredTier)
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
                #if DEBUG
                print("⚠️ [SummarizationCoordinator] \(tier.displayName) unavailable, trying next engine...")
                #endif
                triedEngines.append(tier)
                continue
            }
            
            triedEngines.append(tier)
            
            do {
                #if DEBUG
                print("🧠 [SummarizationCoordinator] Attempting summarization with \(tier.displayName)...")
                #endif
                
                // Generate intelligence using this engine
                var intelligence = try await engineToTry.summarizeSession(
                    sessionId: sessionId,
                    transcriptText: transcriptText,
                    duration: duration,
                    languageCodes: languageCodes
                )

                // An engine that answers with nothing must not leave the recording with an
                // empty summary. The opening of the transcript is a better record than none.
                if intelligence.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    #if DEBUG
                    print("⚠️ [SummarizationCoordinator] \(tier.displayName) returned an empty summary, using the transcript opening")
                    #endif
                    intelligence = intelligence.replacingSummary(Self.transcriptOpening(transcriptText))
                }

                // Success! Convert to Summary and return
                #if DEBUG
                print("✅ [SummarizationCoordinator] Successfully generated summary with \(tier.displayName)")
                #endif
                return (try convertToSummary(intelligence: intelligence), intelligence.title)
                
            } catch {
                #if DEBUG
                print("❌ [SummarizationCoordinator] \(tier.displayName) failed: \(error.localizedDescription)")
                #endif
                lastError = error
                
                // If this is External API and failed, try fallback immediately
                if tier == .external {
                    #if DEBUG
                    print("🔄 [SummarizationCoordinator] Network error detected, falling back to on-device engines...")
                    #endif
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
    
    // MARK: - Digest and Year Wrap models

    /// The model to build month digests with: the user's chosen engine, or the next
    /// on-device one if it isn't available. Nil means Basic (no model).
    /// Follows the same chain as session summaries, so it never falls back to the cloud.
    public func digestGenerator() async -> (any TextGenerating)? {
        for tier in Self.fallbackChain(for: preferredTier) {
            if let generator = await availableGenerator(for: tier) {
                return generator
            }
        }
        return nil
    }

    /// Engines that can write a Year Wrap on this device right now: Smartest (External) and
    /// Apple Intelligence. Local models are too slow for it and Basic has no model.
    public func yearWrapEngines() async -> [EngineTier] {
        var engines: [EngineTier] = []
        for tier in [EngineTier.external, .apple] where await availableGenerator(for: tier) != nil {
            engines.append(tier)
        }
        return engines
    }

    /// The model for Year Wrap. Only Smartest (External) or Apple Intelligence.
    public func yearWrapGenerator(tier: EngineTier) async throws -> any TextGenerating {
        switch tier {
        case .external:
            guard let external = await availableGenerator(for: .external) else {
                throw SummarizationError.summarizationFailed("Cloud AI needs an API key. Add one in Settings.")
            }
            return external
        case .apple:
            guard let apple = await availableGenerator(for: .apple) else {
                throw SummarizationError.summarizationFailed("Apple Intelligence isn't available on this device.")
            }
            return apple
        case .local, .basic:
            throw SummarizationError.summarizationFailed("Year Wrap needs Apple Intelligence or Cloud AI.")
        }
    }

    private func availableGenerator(for tier: EngineTier) async -> (any TextGenerating)? {
        let engine: (any SummarizationEngine)?
        switch tier {
        case .basic: return nil
        case .local: engine = localEngine
        case .apple: engine = appleEngine
        case .external: engine = externalEngine
        }
        guard let engine, let generator = engine as? any TextGenerating, await engine.isAvailable() else {
            return nil
        }
        return generator
    }

    /// Engines to try, in order, for a session summary.
    /// Starts with the user's choice; falls back to on-device engines only, so a
    /// transcript is never sent to a cloud API unless the user selected External.
    static func fallbackChain(for preferred: EngineTier) -> [EngineTier] {
        switch preferred {
        case .external: return [.external, .local, .basic]
        case .apple: return [.apple, .local, .basic]
        case .local: return [.local, .basic]
        case .basic: return [.basic]
        }
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

// MARK: - Empty summary guard

extension SummarizationCoordinator {
    /// The first words of a transcript, with any "• Dec 22, 2025 12:00 AM:" markers removed.
    /// Used as the summary when an engine returns nothing, so a recording is never left blank.
    nonisolated static func transcriptOpening(_ transcript: String, maxWords: Int = 60) -> String {
        let timestampPattern = #"[•●]?\s*[A-Za-z]+\s+\d{1,2},\s+\d{4}\s+\d{1,2}:\d{2}\s+[AP]M:\s*"#
        let cleaned = transcript
            .replacingOccurrences(of: timestampPattern, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^[•●\s]+"#, with: "", options: .regularExpression)
        let words = cleaned.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let opening = words.prefix(maxWords).joined(separator: " ")
        return words.count > maxWords ? opening + "…" : opening
    }
}

extension SessionIntelligence {
    /// The same result with a different summary text
    func replacingSummary(_ summary: String) -> SessionIntelligence {
        SessionIntelligence(
            sessionId: sessionId,
            summary: summary,
            topics: topics,
            entities: entities,
            sentiment: sentiment,
            duration: duration,
            wordCount: wordCount,
            languageCodes: languageCodes,
            keyMoments: keyMoments,
            category: category,
            title: title
        )
    }
}
