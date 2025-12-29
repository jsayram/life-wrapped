// =============================================================================
// AppCoordinator — Central orchestrator for Life Wrapped
// =============================================================================

import Foundation
import SwiftUI
import UIKit
import AVFoundation
import Speech
import CryptoKit
import SharedModels
import Summarization
import Storage
import AudioCapture
import Transcription
import Summarization
import InsightsRollup
import WidgetCore
import WidgetKit

// MARK: - App Coordinator Error

public enum AppCoordinatorError: Error, Sendable {
    case notInitialized
    case recordingInProgress
    case noActiveRecording
    case transcriptionFailed(Error)
    case storageFailed(Error)
    case summarizationFailed(Error)
    case rollupFailed(Error)
    
    public var localizedDescription: String {
        switch self {
        case .notInitialized:
            return "App coordinator is not initialized"
        case .recordingInProgress:
            return "A recording is already in progress"
        case .noActiveRecording:
            return "No active recording to stop"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .storageFailed(let error):
            return "Storage failed: \(error.localizedDescription)"
        case .summarizationFailed(let error):
            return "Summarization failed: \(error.localizedDescription)"
        case .rollupFailed(let error):
            return "Rollup generation failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Recording State

public enum RecordingState: Sendable, Equatable {
    case idle
    case recording(startTime: Date)
    case processing
    case completed(chunkId: UUID)
    case failed(String)
    
    public var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
    
    public var isProcessing: Bool {
        if case .processing = self { return true }
        return false
    }
}

// MARK: - Day Stats

public struct DayStats: Sendable, Equatable {
    public let date: Date
    public let segmentCount: Int
    public let wordCount: Int
    public let totalDuration: TimeInterval
    
    public init(date: Date, segmentCount: Int, wordCount: Int, totalDuration: TimeInterval) {
        self.date = date
        self.segmentCount = segmentCount
        self.wordCount = wordCount
        self.totalDuration = totalDuration
    }
    
    public var totalMinutes: Int {
        Int(totalDuration / 60)
    }
    
    public static let empty = DayStats(
        date: Date(),
        segmentCount: 0,
        wordCount: 0,
        totalDuration: 0
    )
}

// MARK: - App Coordinator

/// Central coordinator that orchestrates all app functionality.
/// Connects: AudioCapture → Transcription → Storage → Summarization → InsightsRollup → Widget
@MainActor
public final class AppCoordinator: ObservableObject {
    
    // MARK: - Published State
    
    @Published public private(set) var recordingState: RecordingState = .idle
    @Published public private(set) var currentStreak: Int = 0
    @Published public private(set) var todayStats: DayStats = .empty
    @Published public private(set) var isInitialized: Bool = false
    @Published public private(set) var initializationError: Error?
    @Published public var needsPermissions: Bool = false
    @Published public var currentToast: Toast?
    @Published public private(set) var isDownloadingLocalModel: Bool = false
    @Published public private(set) var yearWrapNewSessionCount: Int = 0
    
    // MARK: - Dependencies
    
    private var databaseManager: DatabaseManager?
    public let audioCapture: AudioCaptureManager
    public let audioPlayback: AudioPlaybackManager
    private var transcriptionManager: TranscriptionManager?
    private var transcriptionCoordinator: TranscriptionCoordinator?
    private var dataCoordinator: DataCoordinator?
    private var summaryCoordinator: SummaryCoordinator?
    public var recordingCoordinator: RecordingCoordinator?
    private var widgetCoordinator: WidgetCoordinator?
    private var permissionsCoordinator: PermissionsCoordinator?
    private var localModelCoordinator: LocalModelCoordinator?
    public private(set) var summarizationCoordinator: SummarizationCoordinator?
    private var insightsManager: InsightsManager?
    private let widgetDataManager: WidgetDataManager
    
    // MARK: - Transcription Status Tracking
    
    @Published public private(set) var transcribingChunkIds: Set<UUID> = []  // Currently transcribing
    @Published public private(set) var transcribedChunkIds: Set<UUID> = []   // Successfully completed
    @Published public private(set) var failedChunkIds: Set<UUID> = []         // Failed transcription
    
    // MARK: - Initialization
    
    public init(
        widgetDataManager: WidgetDataManager = .shared
    ) {
        self.audioCapture = AudioCaptureManager()
        self.audioPlayback = AudioPlaybackManager()
        self.widgetDataManager = widgetDataManager
        
        // Setup chunk completion callback
        setupAudioCaptureCallback()
    }
    
    private func setupAudioCaptureCallback() {
        audioCapture.onChunkCompleted = { [weak self] chunk in
            print("✅ [AppCoordinator] Audio chunk received: \(chunk.id) (chunk \(chunk.chunkIndex) of session \(chunk.sessionId))")
            await self?.processCompletedChunk(chunk)
        }
    }
    
    /// Process a completed chunk (called from auto-chunking or final stop)
    private func processCompletedChunk(_ chunk: AudioChunk) async {
        do {
            // Save the audio chunk to storage
            print("💾 [AppCoordinator] Saving audio chunk to database...")
            guard let dbManager = databaseManager else {
                print("❌ [AppCoordinator] DatabaseManager not available")
                return
            }
            try await dbManager.insertAudioChunk(chunk)
            print("✅ [AppCoordinator] Audio chunk saved")
            
            // If this is the first chunk (index 0), create/update session metadata with category
            if chunk.chunkIndex == 0, let category = recordingCoordinator?.currentCategory {
                print("📂 [AppCoordinator] First chunk - creating session metadata with category: \(category.displayName)")
                let metadata = DatabaseManager.SessionMetadata(
                    sessionId: chunk.sessionId,
                    category: category
                )
                try await dbManager.upsertSessionMetadata(metadata)
                print("✅ [AppCoordinator] Session metadata with category saved")
            }
            
            // Delegate to transcription coordinator for parallel processing
            print("📝 [AppCoordinator] Delegating chunk \(chunk.chunkIndex) to TranscriptionCoordinator")
            transcriptionCoordinator?.enqueueChunk(chunk.id)
        } catch {
            print("❌ [AppCoordinator] Failed to process chunk: \(error)")
        }
    }
    
    // MARK: - Async Initialization
    
    /// Initialize minimal components needed for model download (before permissions)
    public func initializeForModelDownload() async {
        print("🔧 [AppCoordinator] Initializing minimal setup for model download...")
        
        // Only initialize if not already done
        guard localModelCoordinator == nil else {
            print("✅ [AppCoordinator] LocalModelCoordinator already initialized")
            return
        }
        
        do {
            // Initialize database (needed for summarization coordinator)
            if databaseManager == nil {
                print("📦 [AppCoordinator] Initializing DatabaseManager for model download...")
                let dbManager = try await DatabaseManager()
                self.databaseManager = dbManager
                print("✅ [AppCoordinator] DatabaseManager initialized")
            }
            
            // Initialize SummarizationCoordinator (needed for LocalModelCoordinator)
            if summarizationCoordinator == nil {
                print("📝 [AppCoordinator] Initializing SummarizationCoordinator for model download...")
                let coordinator = SummarizationCoordinator(storage: databaseManager!)
                self.summarizationCoordinator = coordinator
                print("✅ [AppCoordinator] SummarizationCoordinator initialized")
            }
            
            // Initialize LocalModelCoordinator
            print("🧠 [AppCoordinator] Initializing LocalModelCoordinator...")
            let localModelCoord = LocalModelCoordinator(summarizationCoordinator: summarizationCoordinator!)
            localModelCoord.onSuccess = { [weak self] message in
                self?.showSuccess(message)
            }
            localModelCoord.onError = { [weak self] message in
                self?.showError(message)
            }
            localModelCoord.$isDownloadingLocalModel.assign(to: &self.$isDownloadingLocalModel)
            self.localModelCoordinator = localModelCoord
            print("✅ [AppCoordinator] LocalModelCoordinator initialized for download")
            
        } catch {
            print("❌ [AppCoordinator] Failed to initialize for model download: \(error)")
        }
    }
    
    /// Initialize the app coordinator and load initial state
    public func initialize() async {
        print("🚀 [AppCoordinator] Starting initialization...")
        guard !isInitialized else {
            print("⚠️ [AppCoordinator] Already initialized, skipping")
            return
        }
        
        // Initialize PermissionsCoordinator (before checking permissions)
        print("🔐 [AppCoordinator] Initializing PermissionsCoordinator...")
        self.permissionsCoordinator = PermissionsCoordinator()
        print("✅ [AppCoordinator] PermissionsCoordinator initialized")
        
        // Check permissions first
        let hasPermissions = await checkPermissions()
        if !hasPermissions {
            print("⚠️ [AppCoordinator] Permissions not granted, showing permissions UI")
            needsPermissions = true
            return
        }
        
        do {
            // Initialize database
            print("📦 [AppCoordinator] Initializing DatabaseManager...")
            let dbManager = try await DatabaseManager()
            self.databaseManager = dbManager
            print("✅ [AppCoordinator] DatabaseManager initialized")
            
            // Load user settings
            print("⚙️ [AppCoordinator] Loading user settings...")
            let savedChunkDuration = UserDefaults.standard.double(forKey: "autoChunkDuration")
            if savedChunkDuration > 0 {
                audioCapture.autoChunkDuration = savedChunkDuration
                print("✅ [AppCoordinator] Loaded chunk duration: \(Int(savedChunkDuration))s")
            } else {
                // Set and save default
                audioCapture.autoChunkDuration = 30  // 30 seconds default for fast processing
                UserDefaults.standard.set(30.0, forKey: "autoChunkDuration")
                print("✅ [AppCoordinator] Using default chunk duration: 30s")
            }
            
            // Initialize managers that need storage
            print("🎤 [AppCoordinator] Initializing TranscriptionManager...")
            self.transcriptionManager = TranscriptionManager(storage: dbManager)
            print("📝 [AppCoordinator] Initializing SummarizationCoordinator...")
            let coordinator = SummarizationCoordinator(storage: dbManager)
            self.summarizationCoordinator = coordinator
            // Restore saved engine preference (auto-selects Local AI if available)
            await coordinator.restoreSavedPreference()
            print("📊 [AppCoordinator] Initializing InsightsManager...")
            self.insightsManager = InsightsManager(storage: dbManager)
            print("✅ [AppCoordinator] All managers initialized")
            
            // Initialize DataCoordinator
            print("📊 [AppCoordinator] Initializing DataCoordinator...")
            self.dataCoordinator = DataCoordinator(databaseManager: dbManager, insightsManager: InsightsManager(storage: dbManager))
            print("✅ [AppCoordinator] DataCoordinator initialized")
            
            // Initialize TranscriptionCoordinator
            print("🎯 [AppCoordinator] Initializing TranscriptionCoordinator...")
            guard let transcription = self.transcriptionManager else {
                print("❌ [AppCoordinator] TranscriptionManager not available for coordinator")
                throw AppCoordinatorError.notInitialized
            }
            let transcriptCoord = TranscriptionCoordinator(
                databaseManager: dbManager,
                transcriptionManager: transcription
            )
            transcriptCoord.onStatusUpdate = { [weak self] transcribingIds, transcribedIds, failedIds in
                self?.transcribingChunkIds = transcribingIds
                self?.transcribedChunkIds = transcribedIds
                self?.failedChunkIds = failedIds
            }
            transcriptCoord.onSessionComplete = { [weak self] sessionId in
                await self?.handleSessionTranscriptionComplete(sessionId: sessionId)
            }
            self.transcriptionCoordinator = transcriptCoord
            print("✅ [AppCoordinator] TranscriptionCoordinator initialized")
            
            // Initialize SummaryCoordinator
            print("📝 [AppCoordinator] Initializing SummaryCoordinator...")
            let summaryCoord = SummaryCoordinator(
                databaseManager: dbManager,
                summarizationEngine: coordinator,
                insightsManager: InsightsManager(storage: dbManager)
            )
            summaryCoord.onPeriodSummariesUpdated = { [weak self] in
                await self?.updateWidgetData()
            }
            self.summaryCoordinator = summaryCoord
            print("✅ [AppCoordinator] SummaryCoordinator initialized")
            
            // Initialize RecordingCoordinator
            print("🎙️ [AppCoordinator] Initializing RecordingCoordinator...")
            let recordingCoord = RecordingCoordinator(audioCapture: audioCapture)
            recordingCoord.onStateChanged = { [weak self] newState in
                self?.recordingState = newState
            }
            recordingCoord.onWidgetUpdateNeeded = { [weak self] in
                await self?.updateWidgetData()
            }
            recordingCoord.onChunkCompleted = { [weak self] chunk in
                await self?.processCompletedChunk(chunk)
            }
            self.recordingCoordinator = recordingCoord
            print("✅ [AppCoordinator] RecordingCoordinator initialized")
            
            // Initialize WidgetCoordinator
            print("🧩 [AppCoordinator] Initializing WidgetCoordinator...")
            let widgetCoord = WidgetCoordinator(databaseManager: dbManager, widgetDataManager: widgetDataManager)
            self.widgetCoordinator = widgetCoord
            print("✅ [AppCoordinator] WidgetCoordinator initialized")
            
            // Initialize LocalModelCoordinator
            print("🧠 [AppCoordinator] Initializing LocalModelCoordinator...")
            let localModelCoord = LocalModelCoordinator(summarizationCoordinator: coordinator)
            localModelCoord.onSuccess = { [weak self] message in
                self?.showSuccess(message)
            }
            localModelCoord.onError = { [weak self] message in
                self?.showError(message)
            }
            // Sync isDownloadingLocalModel state
            localModelCoord.$isDownloadingLocalModel.assign(to: &self.$isDownloadingLocalModel)
            self.localModelCoordinator = localModelCoord
            print("✅ [AppCoordinator] LocalModelCoordinator initialized")
            
            // Load current streak
            print("🔥 [AppCoordinator] Loading current streak...")
            await refreshStreak()
            print("✅ [AppCoordinator] Streak loaded: \(currentStreak)")
            
            // Load today's stats
            print("📈 [AppCoordinator] Loading today's stats...")
            await refreshTodayStats()
            print("✅ [AppCoordinator] Today's stats loaded: \(todayStats.segmentCount) entries")
            
            // Update widget
            print("🧩 [AppCoordinator] Updating widget data...")
            await updateWidgetData()
            print("✅ [AppCoordinator] Widget updated")
            
            isInitialized = true
            initializationError = nil
            print("🎉 [AppCoordinator] Initialization complete!")
            
        } catch {
            print("❌ [AppCoordinator] Initialization failed: \(error.localizedDescription)")
            print("❌ [AppCoordinator] Error details: \(error)")
            initializationError = error
            isInitialized = false
        }
    }
    
    // MARK: - Lifecycle Management
    
    /// Handle app becoming active (foreground)
    public func handleAppBecameActive() async {
        print("🟢 [AppCoordinator] App became active")
        // Resume any paused operations if needed
        // Widget updates happen here since they need to be current
        await updateWidgetData()
    }
    
    /// Handle app becoming inactive (transition state)
    public func handleAppBecameInactive() async {
        print("🟡 [AppCoordinator] App became inactive")
        // Prepare for potential background entry
        // Save any pending state if needed
    }
    
    /// Handle app entering background
    public func handleAppEnteredBackground() async {
        print("🔴 [AppCoordinator] App entered background")
        
        // If recording, audio will continue in background thanks to background mode
        if recordingState.isRecording {
            print("🎙️ [AppCoordinator] Recording continues in background")
        }
        
        // Save current state
        await refreshTodayStats()
        await updateWidgetData()
        print("💾 [AppCoordinator] State saved for background")
    }
    
    // MARK: - Permissions
    
    /// Check if all required permissions are granted
    public func checkPermissions() async -> Bool {
        guard let perms = permissionsCoordinator else {
            // Fallback if coordinator not initialized yet
            let perms = PermissionsCoordinator()
            self.permissionsCoordinator = perms
            let hasAll = await perms.checkPermissions()
            await MainActor.run {
                needsPermissions = !hasAll
            }
            return hasAll
        }
        
        let hasAll = await perms.checkPermissions()
        await MainActor.run {
            needsPermissions = !hasAll
        }
        return hasAll
    }
    
    /// Called when user completes permission flow
    public func permissionsGranted() async {
        print("✅ [AppCoordinator] Permissions granted, initializing...")
        
        do {
            // Initialize with error handling
            await initialize()
            
            // Only close permissions sheet after successful initialization
            if isInitialized {
                needsPermissions = false
                print("✅ [AppCoordinator] Successfully initialized, closing permissions sheet")
            } else {
                print("⚠️ [AppCoordinator] Initialization did not complete, keeping permissions sheet open")
            }
        }
    }
    
    // MARK: - User Feedback
    
    /// Show a toast notification
    public func showToast(_ toast: Toast) {
        withAnimation {
            currentToast = toast
        }
    }
    
    /// Provide haptic feedback
    public func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    /// Show success feedback (toast + haptic)
    public func showSuccess(_ message: String) {
        triggerHaptic(.light)
        showToast(Toast(style: .success, message: message))
    }
    
    /// Show error feedback (toast + haptic)
    public func showError(_ message: String) {
        triggerHaptic(.heavy)
        showToast(Toast(style: .error, message: message))
    }
    
    /// Show info feedback (toast only)
    public func showInfo(_ message: String) {
        showToast(Toast(style: .info, message: message))
    }
    
    // MARK: - Data Management
    
    /// Get database manager for export/import operations
    public func getDatabaseManager() -> DatabaseManager? {
        return databaseManager
    }
    
    /// Get local model coordinator for model operations
    public func getLocalModelCoordinator() -> LocalModelCoordinator? {
        return localModelCoordinator
    }
    
    /// Get data coordinator for data operations
    public func getDataCoordinator() -> DataCoordinator? {
        return dataCoordinator
    }
    
    /// Get database file path for debugging
    public func getDatabasePath() async -> String? {
        guard let dbManager = databaseManager else { return nil }
        return await dbManager.getDatabasePath()
    }
    
    /// Delete all user data
    public func deleteAllData() async {
        guard let dbManager = databaseManager else { return }
        
        do {
            // Delete all audio chunks and files
            let chunks = try await dbManager.fetchAllAudioChunks()
            for chunk in chunks {
                try? FileManager.default.removeItem(at: chunk.fileURL)
                try await dbManager.deleteAudioChunk(id: chunk.id)
            }
            
            // Delete all summaries
            let summaries = try await dbManager.fetchAllSummaries()
            for summary in summaries {
                try await dbManager.deleteSummary(id: summary.id)
            }
            
            // Delete all insight rollups
            try await dbManager.deleteAllInsightRollups()
            
            // Delete all session metadata
            try await dbManager.deleteAllSessionMetadata()
            
            // Delete all control events
            try await dbManager.deleteAllControlEvents()
            
            // Delete API keys from Keychain
            KeychainHelper.delete(key: "openai_api_key")
            KeychainHelper.delete(key: "anthropic_api_key")
            
            // Delete local AI model
            if let modelCoordinator = localModelCoordinator {
                try? await modelCoordinator.deleteLocalModel()
            }
            
            // Refresh stats
            await refreshStreak()
            await refreshTodayStats()
            await updateWidgetData()
            
            print("🗑️ [AppCoordinator] All data deleted")
        } catch {
            print("❌ [AppCoordinator] Failed to delete data: \(error)")
            showError("Failed to delete data")
        }
    }
    
    /// Fetch recent recordings for history view
    public func fetchRecentRecordings(limit: Int = 50) async throws -> [AudioChunk] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        return try await dbManager.fetchRecentAudioChunks(limit: limit)
    }
    
    /// Fetch recent recording sessions with all their chunks
    public func fetchRecentSessions(limit: Int = 50) async throws -> [RecordingSession] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        // Get session metadata
        let sessionMetadata = try await dbManager.fetchSessions(limit: limit)
        
        // Fetch chunks and metadata for each session and build RecordingSession objects
        var sessions: [RecordingSession] = []
        for (sessionId, _, _) in sessionMetadata {
            let chunks = try await dbManager.fetchChunksBySession(sessionId: sessionId)
            let metadata = try await dbManager.fetchSessionMetadata(sessionId: sessionId)
            let session = RecordingSession(
                sessionId: sessionId, 
                chunks: chunks,
                title: metadata?.title,
                notes: metadata?.notes,
                isFavorite: metadata?.isFavorite ?? false,
                category: metadata?.category
            )
            sessions.append(session)
        }
        
        return sessions
    }
    
    /// Fetch specific sessions by IDs
    public func fetchSessions(ids: [UUID]) async throws -> [RecordingSession] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        // Fetch chunks and metadata for each session and build RecordingSession objects
        var sessions: [RecordingSession] = []
        for sessionId in ids {
            let chunks = try await dbManager.fetchChunksBySession(sessionId: sessionId)
            if !chunks.isEmpty {
                let metadata = try await dbManager.fetchSessionMetadata(sessionId: sessionId)
                let session = RecordingSession(
                    sessionId: sessionId, 
                    chunks: chunks,
                    title: metadata?.title,
                    notes: metadata?.notes,
                    isFavorite: metadata?.isFavorite ?? false,
                    category: metadata?.category
                )
                sessions.append(session)
            }
        }
        
        return sessions
    }
    
    // MARK: - Recording
    
    /// Start a new recording session
    @MainActor
    public func startRecording() async throws {
        guard isInitialized else {
            throw AppCoordinatorError.notInitialized
        }
        
        // Delegate to RecordingCoordinator
        try await recordingCoordinator?.startRecording()
    }
    
    /// Stop the current recording and process it through the pipeline
    @MainActor
    public func stopRecording() async throws {
        guard isInitialized else {
            throw AppCoordinatorError.notInitialized
        }
        
        // Delegate to RecordingCoordinator
        try await recordingCoordinator?.stopRecording()
    }
    
    /// Cancel the current recording without saving
    public func cancelRecording() async {
        await recordingCoordinator?.cancelRecording()
    }
    
    /// Set the recording category from a deep link string
    public func setRecordingCategory(from string: String) {
        guard let category = SessionCategory(rawValue: string) else {
            print("⚠️ [AppCoordinator] Invalid category string: \(string)")
            return
        }
        recordingCoordinator?.selectedCategory = category
        print("📂 [AppCoordinator] Recording category set to: \(category.displayName)")
    }
    
    /// Reset to idle state after viewing completed/failed state
    public func resetRecordingState() {
        recordingCoordinator?.resetRecordingState()
        if case .processing = recordingState { return }
        recordingState = .idle
    }
    
    /// Retry transcription for a failed chunk
    public func retryTranscription(chunkId: UUID) async {
        print("🔄 [AppCoordinator] Retrying transcription for chunk: \(chunkId)")
        transcriptionCoordinator?.retryTranscription(chunkId: chunkId, failedChunkIds: &failedChunkIds)
        print("✅ [AppCoordinator] Chunk \(chunkId) delegated to TranscriptionCoordinator for retry")
    }
    
    // MARK: - Private Recording Helpers
    
    /// Handle completion of session transcription (called by TranscriptionCoordinator)
    private func handleSessionTranscriptionComplete(sessionId: UUID) async {
        print("🔔 [AppCoordinator] Session \(sessionId) transcription complete callback received")
        await checkAndGenerateSessionSummary(for: sessionId)
    }
    
    /// Check if all chunks in a session are transcribed and generate session summary
    private func checkAndGenerateSessionSummary(for sessionId: UUID) async {
        print("🔔 [AppCoordinator] === CHECK AND GENERATE SESSION SUMMARY TRIGGERED ===")
        print("📌 [AppCoordinator] Session ID: \(sessionId)")
        
        do {
            // Check if all chunks are transcribed
            print("1️⃣ [AppCoordinator] Checking if session transcription is complete...")
            let isComplete = try await isSessionTranscriptionComplete(sessionId: sessionId)
            print("🔍 [AppCoordinator] Session \(sessionId) transcription complete: \(isComplete)")
            
            guard isComplete else {
                print("⏳ [AppCoordinator] ⏸️  Session \(sessionId) not yet complete, skipping summary generation")
                return
            }
            
            print("✅ [AppCoordinator] Session transcription is complete!")
            
            // Update rollups now that transcription data is available
            print("2️⃣ [AppCoordinator] Updating rollups with new transcription data...")
            await updateRollupsAndStats()
            
            // Delegate to SummaryCoordinator
            print("3️⃣ [AppCoordinator] 🚀 Delegating to SummaryCoordinator...")
            await summaryCoordinator?.checkAndGenerateSessionSummary(for: sessionId)
            print("✅ [AppCoordinator] ✨ Session summary generated and period summaries updated")
            
            // Update widget data with new stats
            await updateWidgetData()
            
            // Unload model after session is complete to free memory
            if let coordinator = self.summarizationCoordinator {
                let localEngine = await coordinator.getLocalEngine()
                print("🧹 [AppCoordinator] Unloading Local AI model after session completion...")
                await localEngine.unloadModel()
                print("✅ [AppCoordinator] Model memory freed, reducing thermal and battery impact")
            }
            
        } catch {
            print("❌ [AppCoordinator] ⚠️ Failed to check/generate session summary: \(error)")
            print("❌ [AppCoordinator] Error details: \(error.localizedDescription)")
        }
    }
    
    /// Generate a summary for an entire session
    public func generateSessionSummary(sessionId: UUID, forceRegenerate: Bool = false, includeNotes: Bool = false) async throws {
        guard summaryCoordinator != nil else {
            throw AppCoordinatorError.notInitialized
        }
        
        // Delegate to SummaryCoordinator
        try await summaryCoordinator?.generateSessionSummary(sessionId: sessionId, forceRegenerate: forceRegenerate, includeNotes: includeNotes)
    }
    
    // Note: Summary generation is now handled per-session in checkAndGenerateSessionSummary()
    // Transcription is delegated to TranscriptionCoordinator
    
    private func updateRollupsAndStats() async {
        guard let insights = insightsManager else { return }
        
        do {
            // Generate all rollups for today (hour, day, week, month)
            let rollups = try await insights.generateAllRollups(for: Date())
            let types = rollups.map { $0.bucketType.rawValue }.joined(separator: ", ")
            print("✅ [AppCoordinator] Rollups generated: \(types)")
            
        } catch {
            print("❌ [AppCoordinator] Rollup generation failed: \(error)")
        }
        
        // Refresh local stats after rollup generation
        await refreshStreak()
        await refreshTodayStats()
    }
    
    // MARK: - Stats & Data Loading
    
    /// Refresh the current streak count
    public func refreshStreak() async {
        do {
            currentStreak = try await dataCoordinator?.calculateStreak() ?? 0
        } catch {
            print("Failed to refresh streak: \(error)")
            currentStreak = 0
        }
    }
    
    /// Refresh today's stats
    public func refreshTodayStats() async {
        print("📊 [AppCoordinator] refreshTodayStats called")
        
        do {
            todayStats = try await dataCoordinator?.fetchTodayStats() ?? DayStats.empty
            print("✅ [AppCoordinator] Today stats loaded: \(todayStats.segmentCount) entries, \(todayStats.wordCount) words")
        } catch {
            print("❌ [AppCoordinator] Failed to refresh today stats: \(error)")
            todayStats = DayStats.empty
        }
    }
    
    /// Debug method to manually generate rollups for today
    public func generateRollupsForToday() async {
        guard let insights = insightsManager else {
            NSLog("❌ [AppCoordinator] No insights manager")
            return
        }
        
        NSLog("🔧 [AppCoordinator] Manually generating rollups for today...")
        
        do {
            let rollup = try await insights.generateRollup(bucketType: .day, for: Date())
            NSLog("✅ [AppCoordinator] Rollup generated: %d segments, %d words", rollup.segmentCount, rollup.wordCount)
            
            // Refresh stats
            await refreshTodayStats()
            await refreshStreak()
            
        } catch {
            NSLog("❌ [AppCoordinator] Failed to generate rollup: %@", error.localizedDescription)
        }
    }
    
    // MARK: - Widget Updates
    
    /// Update widget data with latest stats
    public func updateWidgetData() async {
        // Delegate to WidgetCoordinator
        await widgetCoordinator?.updateWidgetData()
    }
    
    // MARK: - History & Data Access
    
    /// Fetch transcript segments for an audio chunk
    public func fetchTranscript(for chunkId: UUID) async throws -> [TranscriptSegment] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchTranscriptSegments(audioChunkID: chunkId)
    }
    
    /// Fetch transcript segments for an entire session (all chunks combined)
    public func fetchSessionTranscript(sessionId: UUID) async throws -> [TranscriptSegment] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        // Get all chunks for the session
        let chunks = try await dbManager.fetchChunksBySession(sessionId: sessionId)
        
        // Fetch transcripts for all chunks and combine
        var allSegments: [TranscriptSegment] = []
        for chunk in chunks {
            let segments = try await dbManager.fetchTranscriptSegments(audioChunkID: chunk.id)
            allSegments.append(contentsOf: segments)
        }
        
        // Sort by createdAt to maintain order (segments are already ordered within chunks)
        return allSegments.sorted { $0.createdAt < $1.createdAt }
    }
    
    /// Get total word count for a session
    public func getSessionWordCount(sessionId: UUID) async throws -> Int {
        let transcript = try await fetchSessionTranscript(sessionId: sessionId)
        return transcript.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
    
    /// Check if all chunks in a session have been transcribed
    public func isSessionTranscriptionComplete(sessionId: UUID) async throws -> Bool {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.isSessionTranscriptionComplete(sessionId: sessionId)
    }
    
    /// Fetch summary for a session
    public func fetchSessionSummary(sessionId: UUID) async throws -> Summary? {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchSummaryForSession(sessionId: sessionId)
    }
    
    /// Append user notes to existing session summary without AI regeneration
    public func appendNotesToSessionSummary(sessionId: UUID, notes: String) async throws {
        guard summaryCoordinator != nil else {
            throw AppCoordinatorError.notInitialized
        }
        
        // Delegate to SummaryCoordinator
        try await summaryCoordinator?.appendNotesToSessionSummary(sessionId: sessionId, notes: notes)
    }
    
    /// Fetch recent summaries
    public func fetchRecentSummaries(limit: Int = 10) async throws -> [Summary] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchSummaries(limit: limit)
    }
    
    /// Fetch sessions grouped by hour of day
    public func fetchSessionsByHour() async throws -> [(hour: Int, count: Int, sessionIds: [UUID])] {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.fetchSessionsByHour()
    }
    
    /// Fetch the longest recording session
    public func fetchLongestSession() async throws -> (sessionId: UUID, duration: TimeInterval, date: Date)? {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.fetchLongestSession()
    }
    
    /// Fetch the most active month
    public func fetchMostActiveMonth() async throws -> (year: Int, month: Int, count: Int, sessionIds: [UUID])? {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.fetchMostActiveMonth()
    }
    
    /// Fetch sessions grouped by day of week
    public func fetchSessionsByDayOfWeek() async throws -> [(dayOfWeek: Int, count: Int, sessionIds: [UUID])] {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.fetchSessionsByDayOfWeek()
    }
    
    /// Fetch all transcript text within a date range
    public func fetchTranscriptText(startDate: Date, endDate: Date) async throws -> [String] {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.fetchTranscriptText(startDate: startDate, endDate: endDate)
    }
    
    /// Fetch daily sentiment averages for a date range
    public func fetchDailySentiment(from startDate: Date, to endDate: Date) async throws -> [(date: Date, sentiment: Double)] {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.fetchDailySentiment(from: startDate, to: endDate)
    }
    
    /// Fetch sentiment for a specific session
    public func fetchSessionSentiment(sessionId: UUID) async throws -> Double? {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.fetchSessionSentiment(sessionId: sessionId)
    }
    
    /// Fetch language distribution (language code and word count)
    public func fetchLanguageDistribution() async throws -> [(language: String, wordCount: Int)] {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.fetchLanguageDistribution()
    }
    
    /// Fetch dominant language for a specific session
    public func fetchSessionLanguage(sessionId: UUID) async throws -> String? {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.fetchSessionLanguage(sessionId: sessionId)
    }
    
    // MARK: - Session Metadata
    
    /// Update session title
    public func updateSessionTitle(sessionId: UUID, title: String?) async throws {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        try await data.updateSessionTitle(sessionId: sessionId, title: title)
        print("📝 [AppCoordinator] Updated session title: \(title ?? "nil")")
    }
    
    /// Update session notes
    public func updateSessionNotes(sessionId: UUID, notes: String?) async throws {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        try await data.updateSessionNotes(sessionId: sessionId, notes: notes)
        print("📝 [AppCoordinator] Updated session notes")
    }
    
    /// Toggle session favorite status
    public func toggleSessionFavorite(sessionId: UUID) async throws -> Bool {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        let isFavorite = try await data.toggleSessionFavorite(sessionId: sessionId)
        print("⭐ [AppCoordinator] Session favorite: \(isFavorite)")
        return isFavorite
    }
    
    /// Update session category
    public func updateSessionCategory(sessionId: UUID, category: SessionCategory?) async throws {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        try await data.updateSessionCategory(sessionId: sessionId, category: category)
        print("🏷️ [AppCoordinator] Updated session category: \(category?.displayName ?? "None")")
    }
    
    /// Fetch session metadata
    public func fetchSessionMetadata(sessionId: UUID) async throws -> DatabaseManager.SessionMetadata? {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.fetchSessionMetadata(sessionId: sessionId)
    }
    
    // MARK: - Transcript Editing
    
    /// Update transcript segment text (for user edits)
    public func updateTranscriptText(segmentId: UUID, newText: String) async throws {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        try await data.updateTranscriptText(segmentId: segmentId, newText: newText)
        print("✏️ [AppCoordinator] Updated transcript segment: \(segmentId)")
    }
    
    /// Search for sessions by transcript text
    public func searchSessionsByTranscript(query: String) async throws -> Set<UUID> {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.searchSessionsByTranscript(query: query)
    }

    /// Fetch period summary for a specific date and type
    public func fetchPeriodSummary(type: PeriodType, date: Date) async throws -> Summary? {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchPeriodSummary(type: type, date: date)
    }
    
    // MARK: - Period Summary Updates
    
    /// Update period summaries after a new session summary is created
    /// Follows hierarchical rollup: Session → Day → Week → Month → Year
    private func updatePeriodSummaries(sessionId: UUID, sessionDate: Date) async {
        // Delegate to SummaryCoordinator
        await summaryCoordinator?.updatePeriodSummaries(sessionId: sessionId, sessionDate: sessionDate)
    }
    
    /// Update or create daily summary by aggregating all session summaries for that day using deterministic rollup
    public func updateDailySummary(date: Date, forceRegenerate: Bool = false) async {
        // Delegate to SummaryCoordinator
        await summaryCoordinator?.updateDailySummary(date: date, forceRegenerate: forceRegenerate)
    }
    
    /// Update or create weekly summary by concatenating daily rollups
    public func updateWeeklySummary(date: Date, forceRegenerate: Bool = false) async {
        // Delegate to SummaryCoordinator
        await summaryCoordinator?.updateWeeklySummary(date: date, forceRegenerate: forceRegenerate)
    }
    
    /// Update or create monthly summary by concatenating weekly rollups (or daily when needed)
    public func updateMonthlySummary(date: Date, forceRegenerate: Bool = false) async {
        // Delegate to SummaryCoordinator
        await summaryCoordinator?.updateMonthlySummary(date: date, forceRegenerate: forceRegenerate)
    }
    
    /// Update or create yearly summary by concatenating monthly rollups (no external calls)
    public func updateYearlySummary(date: Date, forceRegenerate: Bool = false) async {
        // Delegate to SummaryCoordinator
        await summaryCoordinator?.updateYearlySummary(date: date, forceRegenerate: forceRegenerate)
    }

    /// Manual Year Wrap using specified AI engine (keeps deterministic rollup as default)
    public func wrapUpYear(date: Date, forceRegenerate: Bool = false, useLocalAI: Bool = false) async {
        // Delegate to SummaryCoordinator
        await summaryCoordinator?.wrapUpYear(date: date, forceRegenerate: forceRegenerate, useLocalAI: useLocalAI)
    }
    
    /// Get count of new sessions created after Year Wrap generation
    public func getNewSessionsSinceYearWrap(yearWrap: Summary, year: Int) async throws -> Int {
        guard let summaryCoordinator = summaryCoordinator else {
            throw AppCoordinatorError.notInitialized
        }
        return try await summaryCoordinator.getNewSessionsSinceYearWrap(yearWrap: yearWrap, year: year)
    }
    
    /// Update Year Wrap staleness count
    public func updateYearWrapNewSessionCount(_ count: Int) {
        yearWrapNewSessionCount = count
    }

    /// Delete a recording and its associated data
    public func deleteRecording(_ chunkId: UUID) async throws {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        // Cascade delete will handle transcript segments via FK
        try await dbManager.deleteAudioChunk(id: chunkId)
        
        // Refresh stats
        await updateRollupsAndStats()
        await updateWidgetData()
    }
    
    /// Delete an entire recording session (all chunks)
    public func deleteSession(_ sessionId: UUID) async throws {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        // Delete entire session - cascade delete handles transcript segments
        try await dbManager.deleteSession(sessionId: sessionId)
        
        // Refresh stats
        await updateRollupsAndStats()
        await updateWidgetData()
    }
    
    // MARK: - Session Query Testing (Step 1)
    
    /// Test session queries - prints all sessions and their chunks
    public func testSessionQueries() async {
        guard let dbManager = databaseManager else {
            print("❌ [SessionTest] No database manager")
            return
        }
        
        print("🧪 [SessionTest] ========== Testing Session Queries ==========")
        
        do {
            // Fetch all sessions
            let sessions = try await dbManager.fetchSessions(limit: 10)
            print("📋 [SessionTest] Found \(sessions.count) sessions:")
            
            for (index, session) in sessions.enumerated() {
                print("\n🎯 [SessionTest] Session \(index + 1):")
                print("   Session ID: \(session.sessionId)")
                print("   First Chunk: \(session.firstChunkTime)")
                print("   Chunk Count: \(session.chunkCount)")
                
                // Fetch all chunks for this session
                let chunks = try await dbManager.fetchChunksBySession(sessionId: session.sessionId)
                print("   📦 Chunks in order:")
                for chunk in chunks {
                    let duration = chunk.endTime.timeIntervalSince(chunk.startTime)
                    print("      • Chunk \(chunk.chunkIndex): \(String(format: "%.1f", duration))s (\(chunk.id))")
                }
            }
            
            print("\n✅ [SessionTest] ========== Test Complete ==========\n")
            
        } catch {
            print("❌ [SessionTest] Error: \(error)")
        }
    }
    
    // MARK: - Local AI Model Management
    
    /// Check if the local AI model is downloaded
    public func isLocalModelDownloaded() async -> Bool {
        guard let localModel = localModelCoordinator else { return false }
        return await localModel.isLocalModelDownloaded()
    }
    
    /// Download the local AI model in the background
    public func startLocalModelDownload() {
        localModelCoordinator?.startLocalModelDownload()
    }
    
    /// Download the local AI model with progress tracking (for setup flow)
    public func downloadLocalModel(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard let localModel = localModelCoordinator else {
            throw AppCoordinatorError.notInitialized
        }
        try await localModel.downloadLocalModel(progress: progress)
    }
    
    /// Delete the local AI model and switch to Basic tier if needed
    public func deleteLocalModel() async throws {
        guard let localModel = localModelCoordinator else {
            throw AppCoordinatorError.notInitialized
        }
        try await localModel.deleteLocalModel()
    }
    
    /// Get formatted model size string
    public func localModelSizeFormatted() async -> String {
        guard let localModel = localModelCoordinator else { return "Not Downloaded" }
        return await localModel.localModelSizeFormatted()
    }
    
    /// Get the expected model size for display before download
    public var expectedLocalModelSizeMB: String {
        localModelCoordinator?.expectedLocalModelSizeMB ?? "~2.3 GB"
    }
    
    /// Get the local model display name
    public var localModelDisplayName: String {
        localModelCoordinator?.localModelDisplayName ?? "Phi-3.5 Mini"
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let periodSummariesUpdated = Notification.Name("PeriodSummariesUpdated")
}

#if DEBUG
extension AppCoordinator {
    /// Create a preview instance with mock state
    static func preview() -> AppCoordinator {
        let coordinator = AppCoordinator()
        coordinator.isInitialized = true
        coordinator.currentStreak = 7
        coordinator.todayStats = DayStats(
            date: Date(),
            segmentCount: 3,
            wordCount: 450,
            totalDuration: 180
        )
        return coordinator
    }
}
#endif

// MARK: - Preview Support

extension AppCoordinator {
    /// Create a preview instance with mock state (available in all build configurations)
    static func previewInstance() -> AppCoordinator {
        let coordinator = AppCoordinator()
        coordinator.isInitialized = true
        coordinator.currentStreak = 7
        coordinator.todayStats = DayStats(
            date: Date(),
            segmentCount: 3,
            wordCount: 450,
            totalDuration: 180
        )
        return coordinator
    }
}
