// =============================================================================
// AppCoordinator — Central orchestrator for Life Wrapped
// =============================================================================

import Foundation
import SwiftUI
import UIKit
import AVFoundation
import Speech
import CryptoKit
import Combine
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
    case permissionDenied
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
        case .permissionDenied:
            return "Required permission was denied"
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
    @Published public private(set) var longestStreak: Int = 0
    @Published public private(set) var todayStats: DayStats = .empty
    @Published public private(set) var isInitialized: Bool = false
    @Published public private(set) var initializationError: Error?
    @Published public var needsPermissions: Bool = false
    @Published public var currentToast: Toast?
    @Published public private(set) var isDownloadingLocalModel: Bool = false
    @Published public private(set) var localModelDownloadProgress: Double = 0
    /// Per wrap filter: how many of that journal's recordings are new or changed since the wrap was built
    @Published public private(set) var yearWrapOutdatedCounts: [ItemFilter: Int] = [:]
    /// The recording that was just saved, for the confirmation on the Record screen. Nil once dismissed
    /// or when a new recording starts.
    @Published public private(set) var lastSavedRecording: SavedRecording?

    public struct SavedRecording: Equatable, Sendable {
        public let sessionId: UUID
        public let journal: SessionCategory
        /// The mic never heard anything loud enough to be speech during this recording
        public let heardNothing: Bool
    }
    /// Current step of a running Year Wrap, nil when none is running
    @Published public private(set) var yearWrapProgress: YearWrapProgress?
    /// How far a bulk upgrade of earlier summaries has got, nil when none is running
    @Published public private(set) var summaryUpgradeProgress: SummaryUpgradeProgress?
    public struct SummaryUpgradeProgress: Equatable {
        public let done: Int
        public let total: Int
    }
    @Published public private(set) var isGeneratingYearWrap: Bool = false
    
    /// Store manager for in-app purchases. Views read it through the coordinator, so its changes are
    /// forwarded below; a nested ObservableObject doesn't refresh them on its own.
    public let storeManager = StoreManager()
    private var storeChanges: AnyCancellable?
    
    // MARK: - Dependencies
    
    private var databaseManager: DatabaseManager?
    public let audioCapture: AudioCaptureManager
    public let audioPlayback: AudioPlaybackManager
    private var transcriptionManager: TranscriptionManager?
    private var transcriptionCoordinator: TranscriptionCoordinator?
    private var dataCoordinator: DataCoordinator?
    private var summaryCoordinator: SummaryCoordinator?
    public var recordingCoordinator: RecordingCoordinator?

    /// The session being recorded right now. Its chunks are transcribed while recording goes on,
    /// so "every saved chunk has a transcript" can be true long before the recording ends.
    /// Its summary waits until recording stops, or it would cover only the first chunks.
    private var sessionStillRecording: UUID?
    /// The session the current recording's chunks belong to
    private var currentRecordingSessionId: UUID?
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
        
        // StoreManager publishes on the main actor, so the forward stays there
        storeChanges = storeManager.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
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

            currentRecordingSessionId = chunk.sessionId

            // Auto-chunks arrive while still recording; the final chunk arrives during stop
            if recordingCoordinator?.isRecording == true {
                sessionStillRecording = chunk.sessionId
            }
            
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
            localModelCoord.$localModelDownloadProgress.assign(to: &self.$localModelDownloadProgress)
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
            summaryCoord.onYearWrapProgressUpdate = { [weak self] progress in
                self?.yearWrapProgress = progress
            }
            summaryCoord.onEngineFallback = { [weak self] chosen, used in
                // Say so, or a lapsed API key quietly turns months of Cloud AI summaries into Key Sentences ones
                self?.showInfo("\(chosen.displayName) wasn't available. This recording was summarized by \(used.displayName).")
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
            // Sync download state
            localModelCoord.$isDownloadingLocalModel.assign(to: &self.$isDownloadingLocalModel)
            localModelCoord.$localModelDownloadProgress.assign(to: &self.$localModelDownloadProgress)
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
            
            // The launch's "became active" event arrives before this point, so run background upkeep now
            Task { await finalizeMonthDigestIfIdle() }
            
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
        // The day may have changed while the app was in the background
        await refreshStreak()
        // Widget updates happen here since they need to be current
        await updateWidgetData()
        
        // Finalize one ended month's digest in the background, without blocking the UI
        Task { await finalizeMonthDigestIfIdle() }
    }
    
    /// True while a foreground digest check is running, so quick app switches don't stack them
    private var isFinalizingMonthDigest = false
    
    private func finalizeMonthDigestIfIdle() async {
        guard isInitialized, !isFinalizingMonthDigest, !isGeneratingYearWrap,
              !recordingState.isRecording, !recordingState.isProcessing else { return }
        isFinalizingMonthDigest = true
        defer { isFinalizingMonthDigest = false }
        await summaryCoordinator?.finalizeNextClosedMonthDigest()
        if await summaryCoordinator?.titleUntitledRecordings() ?? 0 > 0 {
            NotificationCenter.default.post(name: .recordingTitlesUpdated, object: nil)
        }
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
    
    /// Today's recordings, newest first, with titles and journals (for the Record screen)
    public func fetchTodaysSessions() async throws -> [RecordingSession] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        let ids = try await dbManager.fetchSessionsByDate(date: Date()).map(\.sessionId)
        return try await fetchSessions(ids: ids)
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
    /// Requests microphone permission just-in-time if needed
    @MainActor
    public func startRecording() async throws {
        print("\n╔════════════════════════════════════════════════════════╗")
        print("║ [AppCoordinator] START RECORDING CALLED                ║")
        print("╚════════════════════════════════════════════════════════╝")
        print("📍 [AppCoordinator] isInitialized: \(isInitialized)")
        print("📍 [AppCoordinator] recordingState: \(recordingState)\n")
        
        guard isInitialized else {
            print("❌ [AppCoordinator] NOT INITIALIZED")
            throw AppCoordinatorError.notInitialized
        }
        lastSavedRecording = nil
        currentRecordingSessionId = nil
        
        // Request microphone permission just-in-time
        print("🎤 [AppCoordinator] Requesting microphone permission...")
        let hasPermission = await requestMicrophonePermission()
        
        print("\n🎤 [AppCoordinator] *** BACK FROM MICROPHONE PERMISSION ***")
        print("🎤 [AppCoordinator] Permission granted: \(hasPermission)\n")
        
        guard hasPermission else {
            print("❌ [AppCoordinator] Microphone permission DENIED")
            throw AppCoordinatorError.permissionDenied
        }
        
        // Request speech recognition permission just-in-time
        print("🗣️ [AppCoordinator] Requesting speech recognition permission...")
        let hasSpeechPermission = await requestSpeechRecognitionPermission()
        
        print("\n🗣️ [AppCoordinator] *** BACK FROM SPEECH PERMISSION ***")
        print("🗣️ [AppCoordinator] Permission granted: \(hasSpeechPermission)")
        
        if !hasSpeechPermission {
            print("⚠️ [AppCoordinator] Speech recognition DENIED - recording will continue without transcription")
            // Don't block recording, just warn the user
            await MainActor.run {
                showError("Speech recognition denied. Recording will continue, but transcription won't be available.")
            }
        }
        
        print("✅ [AppCoordinator] Starting recording...\n")
        
        // Delegate to RecordingCoordinator
        try await recordingCoordinator?.startRecording()
        
        print("\n╔════════════════════════════════════════════════════════╗")
        print("║ [AppCoordinator] START RECORDING COMPLETED             ║")
        print("╚════════════════════════════════════════════════════════╝\n")
    }
    
    /// Request microphone permission
    /// NOT @MainActor - runs on background to avoid deadlock
    private func requestMicrophonePermission() async -> Bool {
        print("\n════════════════════════════════════════════════════════")
        print("🎤 [AppCoordinator] REQUEST MICROPHONE PERMISSION")
        print("🎤 [AppCoordinator] Running OFF MainActor to avoid deadlock")
        print("════════════════════════════════════════════════════════\n")
        
        let currentStatus = AVAudioApplication.shared.recordPermission
        print("🎤 [AppCoordinator] Current microphone status: \(currentStatus)")
        
        if currentStatus == .granted {
            print("✅ [AppCoordinator] Microphone already granted")
            return true
        }
        
        if currentStatus == .undetermined {
            print("🎤 [AppCoordinator] Requesting authorization...")
            print("🎤 [AppCoordinator] About to call AVAudioApplication.requestRecordPermission()...")
            
            // Call from background context to avoid MainActor deadlock
            let granted = await AVAudioApplication.requestRecordPermission()
            
            print("\n🎤 [AppCoordinator] *** PERMISSION CALLBACK RECEIVED ***")
            print("🎤 [AppCoordinator] Permission granted: \(granted)")
            print("🎤 [AppCoordinator] Verifying permission status...")
            
            // Re-check status to be absolutely sure
            let verifyStatus = AVAudioApplication.shared.recordPermission
            print("🎤 [AppCoordinator] Verified status: \(verifyStatus)")
            
            if !granted || verifyStatus != .granted {
                print("❌ [AppCoordinator] Microphone permission DENIED")
                await MainActor.run {
                    showError("Microphone access is required for recording.")
                }
                return false
            }
            
            print("✅ [AppCoordinator] Microphone permission GRANTED AND VERIFIED!")
            
            // Small delay to ensure system state is stable
            print("⏳ [AppCoordinator] Waiting 200ms for system state to stabilize...")
            try? await Task.sleep(nanoseconds: 200_000_000)
            print("✅ [AppCoordinator] System state should be stable now")
            
            return true
        }
        
        // Denied
        print("❌ [AppCoordinator] Microphone permission DENIED (previously)")
        await MainActor.run {
            showError("Microphone access is required. Please enable it in Settings.")
        }
        return false
    }
    
    /// Request speech recognition permission
    /// Uses Task.detached to completely break from MainActor context and avoid deadlock
    private func requestSpeechRecognitionPermission() async -> Bool {
        print("\n════════════════════════════════════════════════════════")
        print("🗣️ [AppCoordinator] REQUEST SPEECH RECOGNITION PERMISSION")
        print("🗣️ [AppCoordinator] Using Task.detached to avoid MainActor deadlock")
        print("════════════════════════════════════════════════════════\n")
        
        // Use Task.detached to completely break from MainActor context
        return await Task.detached {
            let currentStatus = SFSpeechRecognizer.authorizationStatus()
            print("🗣️ [AppCoordinator] Current speech status: \(currentStatus)")
            
            if currentStatus == .authorized {
                print("✅ [AppCoordinator] Speech recognition already authorized")
                return true
            }
            
            if currentStatus == .notDetermined {
                print("🗣️ [AppCoordinator] Requesting authorization...")
                print("🗣️ [AppCoordinator] About to call SFSpeechRecognizer.requestAuthorization()...")
                
                // No withCheckedContinuation wrapper needed - just call directly
                let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { status in
                        print("🗣️ [CALLBACK] Speech recognition response: \(status)")
                        // Resume directly - we're already detached from MainActor
                        continuation.resume(returning: status)
                    }
                }
                
                print("\n🗣️ [AppCoordinator] *** PERMISSION CALLBACK RECEIVED ***")
                print("🗣️ [AppCoordinator] Permission status: \(status)")
                print("🗣️ [AppCoordinator] Verifying permission status...")
                
                // Re-check status to be absolutely sure
                let verifyStatus = SFSpeechRecognizer.authorizationStatus()
                print("🗣️ [AppCoordinator] Verified status: \(verifyStatus)")
                
                if status != .authorized || verifyStatus != .authorized {
                    print("⚠️ [AppCoordinator] Speech recognition NOT authorized: \(status)")
                    return false
                }
                
                print("✅ [AppCoordinator] Speech recognition AUTHORIZED AND VERIFIED!")
                
                // Small delay to ensure system state is stable
                print("⏳ [AppCoordinator] Waiting 300ms for system state to stabilize...")
                try? await Task.sleep(nanoseconds: 300_000_000)
                print("✅ [AppCoordinator] System state should be stable now")
                
                return true
            }
            
            // Denied or restricted
            print("⚠️ [AppCoordinator] Speech recognition DENIED/RESTRICTED (previously): \(currentStatus)")
            return false
        }.value
    }
    
    /// Stop the current recording and process it through the pipeline
    @MainActor
    public func stopRecording() async throws {
        guard isInitialized else {
            throw AppCoordinatorError.notInitialized
        }
        
        let journal = recordingCoordinator?.currentCategory ?? recordingCoordinator?.selectedCategory ?? .personal

        // Delegate to RecordingCoordinator. Its stop waits for the final chunk to be saved.
        do {
            try await recordingCoordinator?.stopRecording()
        } catch {
            await recordingEnded()
            throw error
        }
        if let sessionId = currentRecordingSessionId {
            lastSavedRecording = SavedRecording(sessionId: sessionId, journal: journal,
                                                heardNothing: !audioCapture.lastRecordingHeardVoice)
        }
        currentRecordingSessionId = nil
        // Count today right away, without waiting for transcription and the summary
        await refreshStreak()
        await recordingEnded()
    }

    /// Hide the saved-recording confirmation
    public func dismissLastSavedRecording() {
        lastSavedRecording = nil
    }

    /// Whether this recording's summary is being written right now
    public func isSummarizing(sessionId: UUID) -> Bool {
        summaryCoordinator?.isSummarizing(sessionId) ?? false
    }

    /// Cancel the current recording without saving
    public func cancelRecording() async {
        currentRecordingSessionId = nil
        await recordingCoordinator?.cancelRecording()
        await recordingEnded()
    }

    /// Recording is over (stopped, cancelled or failed): let its summary run. If every chunk is
    /// already transcribed this writes it now; otherwise the last chunk's transcription will.
    private func recordingEnded() async {
        guard let sessionId = sessionStillRecording else { return }
        sessionStillRecording = nil
        await checkAndGenerateSessionSummary(for: sessionId)
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

        guard sessionId != sessionStillRecording else {
            print("⏳ [AppCoordinator] Session \(sessionId) is still recording, summary waits until it stops")
            return
        }

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
        
        // Update widgets with new data
        await updateWidgetData()
    }
    
    // MARK: - Stats & Data Loading
    
    /// Refresh the current and longest streak
    public func refreshStreak() async {
        do {
            let info = try await dataCoordinator?.calculateStreak()
            currentStreak = info?.currentStreak ?? 0
            longestStreak = info?.longestStreak ?? 0
        } catch {
            print("Failed to refresh streak: \(error)")
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
        NotificationCenter.default.post(name: .sessionMetadataChanged, object: sessionId)
    }
    
    /// Update session notes
    public func updateSessionNotes(sessionId: UUID, notes: String?) async throws {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        try await data.updateSessionNotes(sessionId: sessionId, notes: notes)
        print("📝 [AppCoordinator] Updated session notes")
        NotificationCenter.default.post(name: .sessionMetadataChanged, object: sessionId)
    }
    
    /// Toggle session favorite status
    public func toggleSessionFavorite(sessionId: UUID) async throws -> Bool {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        let isFavorite = try await data.toggleSessionFavorite(sessionId: sessionId)
        print("⭐ [AppCoordinator] Session favorite: \(isFavorite)")
        NotificationCenter.default.post(name: .sessionMetadataChanged, object: sessionId)
        return isFavorite
    }
    
    /// Update session category
    public func updateSessionCategory(sessionId: UUID, category: SessionCategory?) async throws {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        try await data.updateSessionCategory(sessionId: sessionId, category: category)
        print("🏷️ [AppCoordinator] Updated session category: \(category?.displayName ?? "None")")
        NotificationCenter.default.post(name: .sessionMetadataChanged, object: sessionId)
    }
    
    /// Fetch session metadata
    public func fetchSessionMetadata(sessionId: UUID) async throws -> DatabaseManager.SessionMetadata? {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.fetchSessionMetadata(sessionId: sessionId)
    }
    
    // MARK: - Transcript Editing
    
    /// Update transcript segment text (for user edits)
    public func updateTranscriptText(sessionId: UUID, segmentId: UUID, newText: String) async throws {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        try await data.updateTranscriptText(sessionId: sessionId, segmentId: segmentId, newText: newText)
        print("✏️ [AppCoordinator] Updated transcript segment: \(segmentId)")
    }

    /// When the recording's transcript was last edited, or nil if never
    public func fetchTranscriptEditedAt(sessionId: UUID) async throws -> Date? {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.fetchTranscriptEditedAt(sessionId: sessionId)
    }
    
    /// Search for sessions by transcript text
    public func searchSessionsByTranscript(query: String) async throws -> Set<UUID> {
        guard let data = dataCoordinator else { throw AppCoordinatorError.notInitialized }
        return try await data.searchSessionsByTranscript(query: query)
    }

    /// Fetch period summary for a specific date and type
    public func fetchPeriodSummary(type: PeriodType, date: Date, category: SessionCategory? = nil) async throws -> Summary? {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchPeriodSummary(type: type, date: date, category: category)
    }
    
    /// This year's Year Wrap for a filter. Work and Personal are each journal's own wrap; wraps made
    /// before journals were stored as separate types and are read until the next generation.
    public func fetchYearWrap(for filter: ItemFilter, date: Date) async -> Summary? {
        switch filter {
        case .all:
            return try? await fetchPeriodSummary(type: .yearWrap, date: date)
        case .workOnly, .personalOnly:
            let journal: SessionCategory = filter == .workOnly ? .work : .personal
            if let own = try? await fetchPeriodSummary(type: .yearWrap, date: date, category: journal) {
                return own
            }
            return try? await fetchPeriodSummary(type: filter.yearWrapType, date: date)
        }
    }
    
    // MARK: - Year Wrap and Month Digests
    
    /// Engines that can write a Year Wrap here: Smartest (when unlocked and set up) and Apple Intelligence
    public func yearWrapEngines() async -> [EngineTier] {
        let engines = await summarizationCoordinator?.yearWrapEngines() ?? []
        return engines.filter { $0 != .external || storeManager.isSmartestAIUnlocked }
    }

    /// Start a Year Wrap for this year. It runs on its own, so the user can keep using the app;
    /// the Year view shows progress and reloads when it's done. Asks iOS for extra time if the
    /// app is sent to the background mid-run.
    public func startYearWrap(engine: EngineTier, forceRegenerate: Bool = true) {
        guard !isGeneratingYearWrap, let summaryCoordinator else { return }
        isGeneratingYearWrap = true
        yearWrapProgress = YearWrapProgress(step: 1, total: 1, label: "Getting ready")

        Task { @MainActor in
            var backgroundTask: UIBackgroundTaskIdentifier = .invalid
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "YearWrap") {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
            defer {
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
                isGeneratingYearWrap = false
                yearWrapProgress = nil
            }

            do {
                try await summaryCoordinator.wrapUpYear(date: Date(), engine: engine, forceRegenerate: forceRegenerate)
                NotificationCenter.default.post(name: .periodSummariesUpdated, object: nil)
                showSuccess("Your Year Wrap is ready")
            } catch {
                print("❌ [AppCoordinator] Year Wrap failed: \(error)")
                // Our own failures carry a readable reason; show that without the "Summarization failed:" prefix
                if case SummarizationError.summarizationFailed(let reason) = error {
                    showError(reason)
                } else {
                    showError("Year Wrap failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Upgrading earlier summaries

    /// Recordings whose summary was written by an engine weaker than `tier`, oldest first
    public func upgradeableSessionIds(for tier: EngineTier) async -> [UUID] {
        guard let db = databaseManager else { return [] }
        let summaries = (try? await db.fetchSummaries(periodType: .session, limit: 10_000)) ?? []
        let weaker = summaries
            .filter { tier.fidelityRank > EngineTier.fidelityRank(of: $0.engineTier) }
            .sorted { $0.periodStart < $1.periodStart }
            .compactMap(\.sessionId)
        let existing = (try? await db.existingSessionIds(among: weaker)) ?? []
        return weaker.filter(existing.contains)
    }

    /// Rewrite those recordings' summaries with `tier`, one after another, keeping each earlier
    /// text as a version. If the engine doesn't answer and a weaker one steps in, the earlier
    /// summary is put back, so an upgrade never makes anything worse. Months and the Year Wrap
    /// notice the changed summaries and update when opened.
    public func upgradeSummaries(sessionIds: [UUID], with tier: EngineTier) {
        guard summaryUpgradeProgress == nil, let summaryCoordinator, let db = databaseManager, !sessionIds.isEmpty else { return }
        summaryUpgradeProgress = SummaryUpgradeProgress(done: 0, total: sessionIds.count)

        Task { @MainActor in
            var backgroundTask: UIBackgroundTaskIdentifier = .invalid
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SummaryUpgrade") {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
            defer {
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
                summaryUpgradeProgress = nil
            }

            var upgraded = 0
            var kept = 0
            for (index, sessionId) in sessionIds.enumerated() {
                let before = try? await db.fetchSummaryForSession(sessionId: sessionId)
                do {
                    try await summaryCoordinator.generateSessionSummary(sessionId: sessionId, forceRegenerate: true)
                    if let before,
                       let after = try? await db.fetchSummaryForSession(sessionId: sessionId),
                       let used = after.engineTier.flatMap(EngineTier.init(rawValue:)),
                       used.isWeaker(than: before.engineTier),
                       let previous = try? await db.fetchSummaryVersions(for: after).first {
                        _ = try? await db.restoreSummaryVersion(previous, replacing: after)
                        kept += 1
                    } else {
                        upgraded += 1
                    }
                } catch {
                    print("⚠️ [AppCoordinator] Upgrade skipped \(sessionId): \(error.localizedDescription)")
                    kept += 1
                }
                summaryUpgradeProgress = SummaryUpgradeProgress(done: index + 1, total: sessionIds.count)
            }

            NotificationCenter.default.post(name: .periodSummariesUpdated, object: nil)
            let noun = upgraded == 1 ? "recording" : "recordings"
            if kept == 0 {
                showSuccess("Upgraded \(upgraded) \(noun) with \(tier.displayName). Months and the Year Wrap update as you open them.")
            } else {
                showToast(Toast(style: .info, message: "Upgraded \(upgraded) of \(sessionIds.count) recordings. \(kept) kept their earlier summary because \(tier.displayName) didn't answer.", duration: 6))
            }
        }
    }

    /// Build or refresh the digest for the month containing `date`
    @discardableResult
    public func updateMonthDigest(date: Date, forceRegenerate: Bool = false) async -> MonthDigest? {
        await summaryCoordinator?.updateMonthDigest(date: date, forceRegenerate: forceRegenerate)
    }
    
    /// First day of every month that has recordings, newest first
    public func monthsWithRecordings() async -> [Date] {
        await summaryCoordinator?.monthsWithRecordings() ?? []
    }
    
    /// The stored digest for the month containing `date`
    public func fetchMonthDigest(date: Date) async -> MonthDigest? {
        await summaryCoordinator?.fetchMonthDigest(date: date)
    }
    
    /// The stored digest plus whether the month still has to be split into work and personal
    public func fetchMonthDigestStatus(date: Date) async -> (digest: MonthDigest, usesLegacy: Bool)? {
        await summaryCoordinator?.fetchMonthDigestStatus(date: date)
    }
    
    /// How many of the year's recordings in `journal` (nil: both) are new or changed since the wrap was built
    public func getNewSessionsSinceYearWrap(yearWrap: Summary, year: Int, journal: SessionCategory? = nil) async throws -> Int {
        guard let summaryCoordinator = summaryCoordinator else {
            throw AppCoordinatorError.notInitialized
        }
        return try await summaryCoordinator.getNewSessionsSinceYearWrap(yearWrap: yearWrap, year: year, journal: journal)
    }

    /// Update the Year Wrap staleness counts, per wrap filter
    public func updateYearWrapOutdatedCounts(_ counts: [ItemFilter: Int]) {
        yearWrapOutdatedCounts = counts
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
        
        // Its summary goes too, so it doesn't linger in rollups, digests and Year Wrap
        if let summary = try? await dbManager.fetchSummaryForSession(sessionId: sessionId) {
            try? await dbManager.deleteSummary(id: summary.id)
        }
        
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
    
    // =========================================================================
    // ⚠️ APP STORE GUIDELINE 4.2.3 COMPLIANCE ⚠️
    // =========================================================================
    //
    // Guideline 4.2.3 (Official Text from Apple):
    // (i)  Your app should work on its own without requiring installation
    //      of another app to function.
    // (ii) If your app needs to download additional resources in order to
    //      function on initial launch, disclose the size of the download
    //      and prompt users before doing so.
    //
    // ✅ PART (i) - App Works Without Downloads:
    //   • BasicEngine (uses Apple's NaturalLanguage framework) is ALWAYS available
    //   • Recording, transcription, playback, and basic summaries work immediately
    //   • Local AI model is an OPTIONAL enhancement for better quality summaries
    //   • The app is fully functional on first launch with zero downloads
    //
    // ✅ PART (ii) - Size Disclosure & User Prompt:
    //   • All download buttons display size, e.g. "Download model (~2.3 GB)" (LocalEngine.modelDownloadSize)
    //   • User must explicitly tap button to start download (never automatic)
    //   • Skip/Cancel options shown at every download prompt
    //   • "Wi-Fi recommended" note displayed before download
    //   • NO downloads triggered in .task, .onAppear, or init() lifecycle methods
    //
    // =========================================================================
    
    /// Download the local AI model in the background
    /// **App Store Compliance (4.2.3):** Requires explicit user action
    public func startLocalModelDownload() {
        localModelCoordinator?.startLocalModelDownload()
    }
    
    /// Download the local AI model with progress tracking (for setup flow)
    /// **App Store Compliance (4.2.3):** Requires explicit user action
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
    
    /// Get the current active AI engine tier
    public func getActiveEngineTier() async -> EngineTier {
        guard let summCoord = summarizationCoordinator else { return .basic }
        return await summCoord.getActiveEngine()
    }
    
    /// Check if should show Local AI download prompt
    /// Returns true only if user is on Basic tier and Local AI is not downloaded
    public func shouldShowLocalAIDownloadPrompt() async -> Bool {
        let activeEngine = await getActiveEngineTier()
        
        // Don't show if user has External AI, Apple Intelligence, or Local AI selected
        guard activeEngine == .basic else { return false }

        // Don't suggest a download this device can't run
        guard isLocalModelSupported else { return false }
        
        // Only show if local model is not downloaded
        let isDownloaded = await isLocalModelDownloaded()
        return !isDownloaded
    }
    
    /// Get formatted model size string
    public func localModelSizeFormatted() async -> String {
        guard let localModel = localModelCoordinator else { return "Not Downloaded" }
        return await localModel.localModelSizeFormatted()
    }
    
    /// Get the expected model size for display before download
    public var expectedLocalModelSizeMB: String {
        localModelCoordinator?.expectedLocalModelSizeMB ?? LocalEngine.modelDownloadSize
    }
    
    /// Whether this device has enough memory to run Smart (6 GB or more)
    public var isLocalModelSupported: Bool {
        LocalEngine.isSupportedOnThisDevice
    }

    /// Get the local model display name
    public var localModelDisplayName: String {
        localModelCoordinator?.localModelDisplayName ?? LocalEngine.modelDisplayName
    }
    
    /// True when the old Smart model was removed and the new one isn't downloaded yet
    public var showsLocalModelReplacedNotice: Bool {
        localModelCoordinator?.showsModelReplacedNotice ?? false
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let periodSummariesUpdated = Notification.Name("PeriodSummariesUpdated")
    static let recordingTitlesUpdated = Notification.Name("RecordingTitlesUpdated")
    /// A recording's title, notes, star or journal changed; the object is its session ID
    static let sessionMetadataChanged = Notification.Name("SessionMetadataChanged")
    /// A recording's summary was saved. `object` is the session's UUID.
    static let sessionSummaryUpdated = Notification.Name("SessionSummaryUpdated")
    /// Writing a recording's summary in the background failed. `object` is the session's UUID;
    /// `userInfo["message"]` says why.
    static let sessionSummaryFailed = Notification.Name("SessionSummaryFailed")
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
