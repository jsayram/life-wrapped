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
    
    // MARK: - Local AI Model Download State
    
    @Published public private(set) var isDownloadingLocalModel: Bool = false
    private var localModelDownloadTask: Task<Void, Never>?
    
    // MARK: - Dependencies
    
    private var databaseManager: DatabaseManager?
    public let audioCapture: AudioCaptureManager
    public let audioPlayback: AudioPlaybackManager
    private var transcriptionManager: TranscriptionManager?
    public private(set) var summarizationCoordinator: SummarizationCoordinator?
    private var insightsManager: InsightsManager?
    private let widgetDataManager: WidgetDataManager
    
    // MARK: - Recording State
    
    private var recordingStartTime: Date?
    private var lastCompletedChunk: AudioChunk?
    
    // MARK: - Transcription Queue
    
    private var pendingTranscriptionIds: [UUID] = []  // Chunk IDs awaiting transcription
    private var activeTranscriptionCount: Int = 0
    private let maxConcurrentTranscriptions: Int = 3
    
    // MARK: - Transcription Status Tracking
    
    @Published public private(set) var transcribingChunkIds: Set<UUID> = []  // Currently transcribing
    @Published public private(set) var transcribedChunkIds: Set<UUID> = []   // Successfully completed
    @Published public private(set) var failedChunkIds: Set<UUID> = []         // Failed transcription
    
    // MARK: - Period Summary Generation Guards
    
    /// Tracks which period summaries are currently being generated to prevent duplicate concurrent calls
    private var generatingPeriodSummaries: Set<String> = []
    
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
            
            // Add to transcription queue for parallel processing (using ID only)
            print("📝 [AppCoordinator] Adding chunk \(chunk.chunkIndex) to transcription queue")
            await MainActor.run {
                pendingTranscriptionIds.append(chunk.id)
            }
            
            // Start batch transcription if not already running
            Task {
                await processTranscriptionQueue()
            }
        } catch {
            print("❌ [AppCoordinator] Failed to process chunk: \(error)")
        }
    }
    
    // MARK: - Async Initialization
    
    /// Initialize the app coordinator and load initial state
    public func initialize() async {
        print("🚀 [AppCoordinator] Starting initialization...")
        guard !isInitialized else {
            print("⚠️ [AppCoordinator] Already initialized, skipping")
            return
        }
        
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
        let micPermission = await checkMicrophonePermission()
        let speechPermission = await checkSpeechRecognitionPermission()
        
        let hasAll = micPermission && speechPermission
        print("🔐 [AppCoordinator] Permissions - Mic: \(micPermission), Speech: \(speechPermission)")
        
        await MainActor.run {
            needsPermissions = !hasAll
        }
        
        return hasAll
    }
    
    private func checkMicrophonePermission() async -> Bool {
        #if os(iOS)
        let status = AVAudioApplication.shared.recordPermission
        return status == .granted
        #else
        return true
        #endif
    }
    
    private func checkSpeechRecognitionPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        return status == .authorized
    }
    
    /// Called when user completes permission flow
    public func permissionsGranted() async {
        print("✅ [AppCoordinator] Permissions granted, initializing...")
        
        do {
            // Initialize first (with error handling)
            await initialize()
            
            // Only close permissions sheet after successful initialization
            if isInitialized {
                needsPermissions = false
                print("✅ [AppCoordinator] Successfully initialized, closing permissions sheet")
            } else {
                print("⚠️ [AppCoordinator] Initialization did not complete, keeping permissions sheet open")
            }
        } catch {
            print("❌ [AppCoordinator] Failed during permissionsGranted: \(error)")
            // Keep permissions sheet open if initialization fails
            initializationError = error
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
                isFavorite: metadata?.isFavorite ?? false
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
                    isFavorite: metadata?.isFavorite ?? false
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
        print("🎙️ [AppCoordinator] Starting recording...")
        guard isInitialized else {
            print("❌ [AppCoordinator] Cannot start recording: not initialized")
            throw AppCoordinatorError.notInitialized
        }
        
        guard !recordingState.isRecording else {
            print("❌ [AppCoordinator] Cannot start recording: already in progress")
            throw AppCoordinatorError.recordingInProgress
        }
        
        // Clear any previous chunk
        lastCompletedChunk = nil
        
        // Start recording
        print("🎤 [AppCoordinator] Starting AudioCaptureManager...")
        try await audioCapture.startRecording(mode: .active)
        print("✅ [AppCoordinator] Audio capture started")
        
        recordingStartTime = Date()
        recordingState = .recording(startTime: Date())
        print("🎙️ [AppCoordinator] Recording state updated to .recording")
    }
    
    /// Stop the current recording and process it through the pipeline
    /// Returns the UUID of the saved AudioChunk
    @MainActor
    public func stopRecording() async throws {
        print("⏹️ [AppCoordinator] Stopping recording...")
        guard case .recording = recordingState else {
            print("❌ [AppCoordinator] Cannot stop: no active recording")
            throw AppCoordinatorError.noActiveRecording
        }
        
        guard databaseManager != nil else {
            print("❌ [AppCoordinator] Cannot stop: not initialized")
            throw AppCoordinatorError.notInitialized
        }
        
        recordingState = .processing
        print("🔄 [AppCoordinator] State changed to .processing")
        
        do {
            // 1. Stop audio capture - this triggers onChunkCompleted callback for final chunk
            print("🎤 [AppCoordinator] Stopping audio capture...")
            try await audioCapture.stopRecording()
            print("✅ [AppCoordinator] Audio capture stopped")
            
            // Wait for final chunk to be processed
            try? await Task.sleep(for: .milliseconds(500))
            
            // 2. Generate summary if enough content
            print("📝 [AppCoordinator] Generating summary...")
            // Note: segments are processed per-chunk now, so we'd need to fetch all segments for summary
            
            // 3. Update widget data
            print("🧩 [AppCoordinator] Updating widget...")
            await updateWidgetData()
            
            // Reset recording state
            recordingStartTime = nil
            lastCompletedChunk = nil
            recordingState = .completed(chunkId: UUID()) // Just show completed state
            print("🎉 [AppCoordinator] Recording session completed successfully")
            
            // Auto-reset to idle after brief success display
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await MainActor.run {
                    if case .completed = self.recordingState {
                        self.recordingState = .idle
                        print("🔄 [AppCoordinator] Auto-reset to idle state")
                    }
                }
            }
            
        } catch {
            print("❌ [AppCoordinator] Recording failed: \(error.localizedDescription)")
            print("❌ [AppCoordinator] Error details: \(error)")
            recordingState = .failed(error.localizedDescription)
            throw error
        }
    }
    
    /// Cancel the current recording without saving
    public func cancelRecording() async {
        guard recordingState.isRecording else { return }
        
        do {
            try await audioCapture.stopRecording()
        } catch {
            // Ignore errors when canceling
        }
        
        recordingStartTime = nil
        lastCompletedChunk = nil
        recordingState = .idle
    }
    
    /// Reset to idle state after viewing completed/failed state
    public func resetRecordingState() {
        if case .idle = recordingState { return }
        if case .recording = recordingState { return }
        if case .processing = recordingState { return }
        recordingState = .idle
    }
    
    /// Retry transcription for a failed chunk
    public func retryTranscription(chunkId: UUID) async {
        print("🔄 [AppCoordinator] Retrying transcription for chunk: \(chunkId)")
        
        // Remove from failed set
        _ = await MainActor.run {
            failedChunkIds.remove(chunkId)
        }
        
        // Add back to pending queue
        await MainActor.run {
            if !pendingTranscriptionIds.contains(chunkId) {
                pendingTranscriptionIds.append(chunkId)
            }
        }
        
        // Trigger queue processing
        await processTranscriptionQueue()
        
        print("✅ [AppCoordinator] Chunk \(chunkId) added to transcription queue for retry")
    }
    
    // MARK: - Private Recording Helpers
    
    /// Process transcription queue with concurrency limit
    private func processTranscriptionQueue() async {
        guard let dbManager = databaseManager else { return }
        
        // Process chunks while we have pending transcriptions and capacity
        while !pendingTranscriptionIds.isEmpty && activeTranscriptionCount < maxConcurrentTranscriptions {
            guard let chunkId = pendingTranscriptionIds.first else { break }
            await MainActor.run {
                _ = pendingTranscriptionIds.removeFirst()
            }
            
            // Fetch chunk from database
            guard let chunk = try? await dbManager.fetchAudioChunk(id: chunkId) else {
                print("❌ [AppCoordinator] Could not fetch chunk \(chunkId) from database")
                continue
            }
            
            activeTranscriptionCount += 1
            await MainActor.run {
                _ = transcribingChunkIds.insert(chunkId)
            }
            print("🔄 [AppCoordinator] Starting transcription \(activeTranscriptionCount)/\(maxConcurrentTranscriptions) for chunk \(chunk.chunkIndex)")
            
            // Start transcription in parallel
            Task {
                do {
                    print("🎯 [AppCoordinator] Transcribing chunk \(chunk.chunkIndex)...")
                    let segments = try await self.transcribeAudio(chunk: chunk)
                    print("✅ [AppCoordinator] Chunk \(chunk.chunkIndex) transcription complete: \(segments.count) segments")
                    
                    // Save transcript segments
                    print("💾 [AppCoordinator] Saving \(segments.count) segments for chunk \(chunk.chunkIndex)...")
                    for segment in segments {
                        try await dbManager.insertTranscriptSegment(segment)
                    }
                    print("✅ [AppCoordinator] Chunk \(chunk.chunkIndex) segments saved")
                    
                    // If using Local AI tier, run chunk through LLM for processing
                    if let coordinator = self.summarizationCoordinator,
                       await coordinator.supportsChunkProcessing() {
                        let chunkText = segments.map { $0.text }.joined(separator: " ")
                        if !chunkText.isEmpty {
                            do {
                                let chunkSummary = try await coordinator.summarizeChunk(
                                    chunkId: chunkId,
                                    transcriptText: chunkText
                                )
                                print("🤖 [AppCoordinator] Chunk \(chunk.chunkIndex) AI summary: \(chunkSummary.prefix(50))...")
                            } catch {
                                print("⚠️ [AppCoordinator] Chunk AI processing failed: \(error)")
                            }
                        }
                    }
                    
                    // Update status tracking
                    await MainActor.run {
                        self.transcribingChunkIds.remove(chunkId)
                        self.transcribedChunkIds.insert(chunkId)
                    }
                    
                    // Update rollups incrementally
                    print("📊 [AppCoordinator] Updating rollups after chunk \(chunk.chunkIndex)...")
                    await self.updateRollupsAndStats()
                    
                } catch {
                    print("❌ [AppCoordinator] Failed to transcribe chunk \(chunk.chunkIndex): \(error)")
                    await MainActor.run {
                        self.transcribingChunkIds.remove(chunkId)
                        self.failedChunkIds.insert(chunkId)
                    }
                }
                
                // Decrement counter and process next in queue
                await MainActor.run {
                    self.activeTranscriptionCount -= 1
                    print("⬇️ [AppCoordinator] Transcription completed, active count now: \(self.activeTranscriptionCount)")
                }
                
                // Check if session is complete and generate summary
                Task {
                    await self.checkAndGenerateSessionSummary(for: chunk.sessionId)
                }
                
                // Continue processing queue
                await self.processTranscriptionQueue()
            }
        }
        
        if pendingTranscriptionIds.isEmpty && activeTranscriptionCount == 0 {
            print("✅ [AppCoordinator] All transcriptions complete")
        } else if !pendingTranscriptionIds.isEmpty {
            print("⏳ [AppCoordinator] \(pendingTranscriptionIds.count) chunks queued, \(activeTranscriptionCount) active transcriptions")
        }
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
            
            // Check if summary already exists
            guard let dbManager = databaseManager else {
                print("❌ [AppCoordinator] DatabaseManager not available")
                return
            }
            
            print("2️⃣ [AppCoordinator] Checking if summary already exists...")
            if let existingSummary = try await dbManager.fetchSummaryForSession(sessionId: sessionId) {
                print("ℹ️ [AppCoordinator] ✋ Summary already exists for session \(sessionId)")
                print("📝 [AppCoordinator] Existing summary: \(existingSummary.text.prefix(50))...")
                print("🚫 [AppCoordinator] Skipping regeneration (summary already exists)")
                return
            }
            
            print("✅ [AppCoordinator] No existing summary found - will generate new one")
            
            // Generate session summary
            print("3️⃣ [AppCoordinator] 🚀 Triggering session summary generation...")
            try await generateSessionSummary(sessionId: sessionId)
            print("✅ [AppCoordinator] ✨ Session summary generated and period summaries updated")
            
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
    public func generateSessionSummary(sessionId: UUID, forceRegenerate: Bool = false) async throws {
        print("🚀 [AppCoordinator] === GENERATING SESSION SUMMARY ===")
        print("📌 [AppCoordinator] Session ID: \(sessionId)")
        print("🔄 [AppCoordinator] Force regenerate: \(forceRegenerate)")
        
        guard let dbManager = databaseManager,
              let coordinator = summarizationCoordinator else {
            print("❌ [AppCoordinator] Missing dependencies - dbManager: \(databaseManager != nil), coordinator: \(summarizationCoordinator != nil)")
            throw AppCoordinatorError.notInitialized
        }
        
        print("✅ [AppCoordinator] Dependencies initialized")
        
        // Get all transcript segments for the session
        print("🔍 [AppCoordinator] Fetching transcript segments...")
        let allSegments = try await fetchSessionTranscript(sessionId: sessionId)
        
        // Combine all text
        let fullText = allSegments.map { $0.text }.joined(separator: " ")
        let wordCount = fullText.split(separator: " ").count
        
        print("📊 [AppCoordinator] Session transcript: \(allSegments.count) segments, \(wordCount) words")
        print("📝 [AppCoordinator] First 100 chars: \(fullText.prefix(100))...")
        
        guard wordCount > 0 else {
            print("❌ [AppCoordinator] No transcript text found - cannot generate summary")
            throw AppCoordinatorError.transcriptionFailed(NSError(domain: "AppCoordinator", code: -1, userInfo: [NSLocalizedDescriptionKey: "No transcript text"]))
        }
        
        // Calculate hash of transcript content for cache checking
        let inputHash = calculateHash(for: fullText)
        
        // Check if we can skip regeneration (cache hit)
        if !forceRegenerate {
            if let existingSummary = try? await dbManager.fetchSummaryForSession(sessionId: sessionId) {
                if let existingHash = existingSummary.inputHash, existingHash == inputHash {
                    print("✅ [AppCoordinator] Summary cache HIT - transcript unchanged, skipping regeneration")
                    print("🔑 [AppCoordinator] Hash match: \(inputHash.prefix(8))...")
                    return
                } else {
                    print("🔄 [AppCoordinator] Summary cache MISS - transcript changed, regenerating")
                    if let existingHash = existingSummary.inputHash {
                        print("🔑 [AppCoordinator] Old hash: \(existingHash.prefix(8))..., New hash: \(inputHash.prefix(8))...")
                    }
                }
            }
        } else {
            print("🔄 [AppCoordinator] Forced regeneration - skipping cache check")
        }
        
        // Get session time range
        let chunks = try await dbManager.fetchChunksBySession(sessionId: sessionId)
        guard let firstChunk = chunks.first, let lastChunk = chunks.last else {
            print("❌ [AppCoordinator] No chunks found for session")
            return
        }
        
        let periodStart = firstChunk.startTime
        let periodEnd = lastChunk.endTime
        
        // If force regenerating, use smart clearing for Local AI (only clears changed chunks)
        if forceRegenerate {
            let localEngine = await coordinator.getLocalEngine()
            
            // Build array of (chunkId, transcriptText) for smart cache clearing
            var chunkTexts: [(id: UUID, text: String)] = []
            for chunk in chunks {
                let segments = try await dbManager.fetchTranscriptSegments(audioChunkID: chunk.id)
                let transcriptText = segments.map { $0.text }.joined(separator: " ")
                chunkTexts.append((id: chunk.id, text: transcriptText))
            }
            
            // Smart cache clearing: only invalidates chunks whose text hash changed
            let chunksNeedingReprocessing = await localEngine.clearChangedChunkSummaries(for: chunkTexts)
            print("🗑️ [AppCoordinator] Smart clear: \(chunksNeedingReprocessing.count) of \(chunks.count) chunks need reprocessing")
        }
        
        // Use the user's active engine (respects their settings choice)
        let activeEngine = await coordinator.getActiveEngine()
        print("🧠 [AppCoordinator] Using active summarization engine: \(activeEngine.displayName)")
        
        // Generate summary using coordinator (returns Summary with structured data)
        print("🌐 [AppCoordinator] 🚀 CALLING LLM API - Summarizing \(wordCount) words from session...")
        var generatedSummary = try await coordinator.generateSessionSummary(sessionId: sessionId, segments: allSegments)
        
        print("✅ [AppCoordinator] LLM API returned summary (engine: \(generatedSummary.engineTier ?? "unknown"), text length: \(generatedSummary.text.count))")
        print("📝 [AppCoordinator] Summary preview: \(generatedSummary.text.prefix(100))...")
        
        // Update time range and include inputHash for caching
        generatedSummary = Summary(
            id: generatedSummary.id,
            periodType: .session,
            periodStart: periodStart,
            periodEnd: periodEnd,
            text: generatedSummary.text,
            createdAt: generatedSummary.createdAt,
            sessionId: sessionId,
            topicsJSON: generatedSummary.topicsJSON,
            entitiesJSON: generatedSummary.entitiesJSON,
            engineTier: generatedSummary.engineTier,
            sourceIds: generatedSummary.sourceIds,
            inputHash: inputHash  // Store hash for future cache checks
        )
        
        // Delete old session summary if it exists (to prevent duplicates in rollups)
        if let existingSummary = try? await dbManager.fetchSummaryForSession(sessionId: sessionId) {
            print("🗑️ [AppCoordinator] Deleting old session summary (ID: \(existingSummary.id))...")
            try await dbManager.deleteSummary(id: existingSummary.id)
            print("✅ [AppCoordinator] Old session summary deleted")
        }
        
        // Save session summary
        print("💾 [AppCoordinator] Saving summary to database...")
        try await dbManager.insertSummary(generatedSummary)
        print("✅ [AppCoordinator] Session summary saved successfully!")
        print("📊 [AppCoordinator] Summary details - topics: \(generatedSummary.topicsJSON?.prefix(50) ?? "none")")
        
        // Update period summaries (daily, weekly, monthly)
        print("📅 [AppCoordinator] Updating period summaries...")
        await updatePeriodSummaries(sessionId: sessionId, sessionDate: periodStart)
        await MainActor.run {
            NotificationCenter.default.post(name: .periodSummariesUpdated, object: nil)
        }
        print("🎉 [AppCoordinator] === SESSION SUMMARY COMPLETE ===")
        
        // Unload Local AI model from memory to free resources
        if let coordinator = self.summarizationCoordinator {
            let localEngine = await coordinator.getLocalEngine()
            print("🧹 [AppCoordinator] Unloading Local AI model to free memory...")
            await localEngine.unloadModel()
            print("✅ [AppCoordinator] Model unloaded, memory released")
        }
    }
    
    private func transcribeAudio(chunk: AudioChunk) async throws -> [TranscriptSegment] {
        guard let transcriber = transcriptionManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        do {
            // Step 1: Transcribe audio
            let segments = try await transcriber.transcribe(chunk: chunk)
            
            // Step 2: Analyze sentiment and detect language for each segment (real-time)
            let sentimentAnalyzer = SentimentAnalyzer()
            let languageDetector = LanguageDetector()
            var enrichedSegments: [TranscriptSegment] = []
            
            for segment in segments {
                let sentimentScore = await sentimentAnalyzer.analyze(segment: segment)
                let detectedLanguage = await languageDetector.detectLanguage(in: segment.text)
                
                // Create enriched segment with sentiment and language data
                let enrichedSegment = TranscriptSegment(
                    id: segment.id,
                    audioChunkID: segment.audioChunkID,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    text: segment.text,
                    confidence: segment.confidence,
                    languageCode: detectedLanguage ?? segment.languageCode,
                    createdAt: segment.createdAt,
                    speakerLabel: segment.speakerLabel,
                    entitiesJSON: segment.entitiesJSON,
                    wordCount: segment.wordCount,
                    sentimentScore: sentimentScore
                )
                enrichedSegments.append(enrichedSegment)
                
                // Log analysis results for monitoring
                if let score = sentimentScore {
                    let category = SentimentAnalyzer.categorizeShort(score)
                    print("📊 [AppCoordinator] Segment sentiment: \(category) (\(String(format: "%.2f", score)))")
                }
                if let language = detectedLanguage {
                    print("🌐 [AppCoordinator] Detected language: \(language)")
                }
            }
            
            return enrichedSegments
        } catch {
            throw AppCoordinatorError.transcriptionFailed(error)
        }
    }
    
    // Note: Summary generation is now handled per-session in checkAndGenerateSessionSummary()
    // This old per-chunk method is no longer needed
    
    private func updateRollupsAndStats() async {
        guard let insights = insightsManager else { return }
        
        do {
            // Generate daily rollup for today
            _ = try await insights.generateRollup(bucketType: .day, for: Date())
            print("✅ [AppCoordinator] Daily rollup generated")
            
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
        guard let dbManager = databaseManager else { return }
        
        do {
            // Fetch daily rollups for streak calculation
            let rollups = try await dbManager.fetchRollups(bucketType: .day, limit: 365)
            
            // Extract dates with activity
            let activityDates = rollups
                .filter { $0.segmentCount > 0 }
                .map { $0.bucketStart }
            
            let streakInfo = StreakCalculator.calculateStreak(from: activityDates)
            currentStreak = streakInfo.currentStreak
        } catch {
            print("Failed to refresh streak: \(error)")
            currentStreak = 0
        }
    }
    
    /// Refresh today's stats
    public func refreshTodayStats() async {
        guard let dbManager = databaseManager else {
            print("⚠️ [AppCoordinator] refreshTodayStats: No database manager")
            return
        }
        
        let today = Calendar.current.startOfDay(for: Date())
        print("📊 [AppCoordinator] refreshTodayStats called for date: \(today)")
        
        do {
            // Fetch today's rollup specifically by date (not just most recent)
            let todayRollup = try await dbManager.fetchRollup(bucketType: .day, bucketStart: today)
            
            if let rollup = todayRollup {
                todayStats = DayStats(
                    date: today,
                    segmentCount: rollup.segmentCount,
                    wordCount: rollup.wordCount,
                    totalDuration: rollup.speakingSeconds
                )
                print("✅ [AppCoordinator] Today stats loaded: \(rollup.segmentCount) entries, \(rollup.wordCount) words, \(Int(rollup.speakingSeconds))s")
            } else {
                // No rollup for today yet - show zeros
                todayStats = DayStats.empty
                print("ℹ️ [AppCoordinator] No rollup found for today - showing zeros")
            }
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
        guard let dbManager = databaseManager else { return }
        
        do {
            // Get latest daily rollups
            let dailyRollups = try await dbManager.fetchRollups(bucketType: .day, limit: 365)
            
            // Extract dates with activity
            let activityDates = dailyRollups
                .filter { $0.segmentCount > 0 }
                .map { $0.bucketStart }
            
            let streakInfo = StreakCalculator.calculateStreak(from: activityDates)
            
            // Get today's stats
            let today = Calendar.current.startOfDay(for: Date())
            var todayWordCount = 0
            var todayMinutes = 0.0
            var todayEntries = 0
            
            if let todayRollup = dailyRollups.first,
               Calendar.current.isDate(todayRollup.bucketStart, inSameDayAs: today) {
                todayWordCount = todayRollup.wordCount
                todayMinutes = todayRollup.speakingSeconds / 60.0
                todayEntries = todayRollup.segmentCount
            }
            
            // Get weekly stats
            let calendar = Calendar.current
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
            let weeklyRollups = dailyRollups.filter { $0.bucketStart >= weekAgo }
            let weeklyWordCount = weeklyRollups.reduce(0) { $0 + $1.wordCount }
            let weeklyMinutes = weeklyRollups.reduce(0.0) { $0 + $1.speakingSeconds } / 60.0
            
            // Create widget data
            let widgetData = WidgetData(
                streakDays: streakInfo.currentStreak,
                todayWords: todayWordCount,
                todayMinutes: Int(todayMinutes),
                todayEntries: todayEntries,
                goalProgress: 0.0, // Can be enhanced with user goals
                lastEntryTime: activityDates.first,
                isStreakAtRisk: StreakCalculator.streakAtRisk(streakInfo),
                weeklyWords: weeklyWordCount,
                weeklyMinutes: Int(weeklyMinutes),
                lastUpdated: Date()
            )
            
            widgetDataManager.writeWidgetData(widgetData)
            
            // Tell WidgetKit to refresh widgets
            WidgetCenter.shared.reloadAllTimelines()
            
        } catch {
            print("Failed to update widget data: \(error)")
        }
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
    
    /// Fetch recent summaries
    public func fetchRecentSummaries(limit: Int = 10) async throws -> [Summary] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchSummaries(limit: limit)
    }
    
    /// Fetch sessions grouped by hour of day
    public func fetchSessionsByHour() async throws -> [(hour: Int, count: Int, sessionIds: [UUID])] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchSessionsByHour()
    }
    
    /// Fetch the longest recording session
    public func fetchLongestSession() async throws -> (sessionId: UUID, duration: TimeInterval, date: Date)? {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchLongestSession()
    }
    
    /// Fetch the most active month
    public func fetchMostActiveMonth() async throws -> (year: Int, month: Int, count: Int, sessionIds: [UUID])? {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchMostActiveMonth()
    }
    
    /// Fetch sessions grouped by day of week
    public func fetchSessionsByDayOfWeek() async throws -> [(dayOfWeek: Int, count: Int, sessionIds: [UUID])] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchSessionsByDayOfWeek()
    }
    
    /// Fetch all transcript text within a date range
    public func fetchTranscriptText(startDate: Date, endDate: Date) async throws -> [String] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchTranscriptText(startDate: startDate, endDate: endDate)
    }
    
    /// Fetch daily sentiment averages for a date range
    public func fetchDailySentiment(from startDate: Date, to endDate: Date) async throws -> [(date: Date, sentiment: Double)] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchDailySentiment(from: startDate, to: endDate)
    }
    
    /// Fetch sentiment for a specific session
    public func fetchSessionSentiment(sessionId: UUID) async throws -> Double? {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchSessionSentiment(sessionId: sessionId)
    }
    
    /// Fetch language distribution (language code and word count)
    public func fetchLanguageDistribution() async throws -> [(language: String, wordCount: Int)] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchLanguageDistribution()
    }
    
    /// Fetch dominant language for a specific session
    public func fetchSessionLanguage(sessionId: UUID) async throws -> String? {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchSessionLanguage(sessionId: sessionId)
    }
    
    // MARK: - Session Metadata
    
    /// Update session title
    public func updateSessionTitle(sessionId: UUID, title: String?) async throws {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        try await dbManager.updateSessionTitle(sessionId: sessionId, title: title)
        print("📝 [AppCoordinator] Updated session title: \(title ?? "nil")")
    }
    
    /// Update session notes
    public func updateSessionNotes(sessionId: UUID, notes: String?) async throws {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        try await dbManager.updateSessionNotes(sessionId: sessionId, notes: notes)
        print("📝 [AppCoordinator] Updated session notes")
    }
    
    /// Toggle session favorite status
    public func toggleSessionFavorite(sessionId: UUID) async throws -> Bool {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        let isFavorite = try await dbManager.toggleSessionFavorite(sessionId: sessionId)
        print("⭐ [AppCoordinator] Session favorite: \(isFavorite)")
        return isFavorite
    }
    
    /// Fetch session metadata
    public func fetchSessionMetadata(sessionId: UUID) async throws -> DatabaseManager.SessionMetadata? {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchSessionMetadata(sessionId: sessionId)
    }
    
    // MARK: - Transcript Editing
    
    /// Update transcript segment text (for user edits)
    public func updateTranscriptText(segmentId: UUID, newText: String) async throws {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        try await dbManager.updateTranscriptSegmentText(id: segmentId, newText: newText)
        print("✏️ [AppCoordinator] Updated transcript segment: \(segmentId)")
    }
    
    /// Search for sessions by transcript text
    public func searchSessionsByTranscript(query: String) async throws -> Set<UUID> {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.searchSessionsByTranscript(query: query)
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
        print("🔄 [AppCoordinator] Updating period summaries for session...")
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: sessionDate)
        
        // Update daily summary
        await updateDailySummary(date: startOfDay)
        
        // Update weekly summary
        await updateWeeklySummary(date: sessionDate)
        
        // Update monthly summary
        await updateMonthlySummary(date: sessionDate)
        
        // Update yearly summary
        await updateYearlySummary(date: sessionDate)
    }
    
    /// Update or create daily summary by aggregating all session summaries for that day using deterministic rollup
    public func updateDailySummary(date: Date, forceRegenerate: Bool = false) async {
        guard let dbManager = databaseManager else { return }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let periodKey = "day-\(startOfDay.timeIntervalSince1970)"

        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [AppCoordinator] Daily summary already being generated, skipping duplicate call...")
            return
        }

        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            let sessions = try await dbManager.fetchSessionsByDate(date: date)
            print("📊 [AppCoordinator] Found \(sessions.count) sessions for \(date.formatted(date: .abbreviated, time: .omitted))")

            guard !sessions.isEmpty else {
                print("ℹ️ [AppCoordinator] No sessions found for this day")
                return
            }

            var sessionsWithSummaries = 0
            var sessionsNeedingSummaries = 0

            for session in sessions {
                if let _ = try? await dbManager.fetchSummaryForSession(sessionId: session.sessionId) {
                    sessionsWithSummaries += 1
                } else {
                    let isComplete = try await isSessionTranscriptionComplete(sessionId: session.sessionId)
                    if isComplete {
                        print("⚠️ [AppCoordinator] Session \(session.sessionId) missing summary, generating...")
                        try await generateSessionSummary(sessionId: session.sessionId)
                        sessionsWithSummaries += 1
                    } else {
                        print("⏳ [AppCoordinator] Session \(session.sessionId) transcription incomplete, skipping")
                        sessionsNeedingSummaries += 1
                    }
                }
            }

            guard sessionsWithSummaries > 0 else {
                print("ℹ️ [AppCoordinator] No sessions with summaries for this day (\(sessions.count) total, \(sessionsNeedingSummaries) pending transcription)")
                return
            }

            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date

            let sessionSummaries = try await dbManager.fetchSummaries(periodType: .session)
                .filter { $0.sessionId != nil && $0.periodStart >= startOfDay && $0.periodStart < endOfDay }
                .sorted { $0.periodStart < $1.periodStart }

            let sessionIds = sessionSummaries.compactMap { $0.sessionId }
            let sessionTexts = sessionSummaries.map { $0.text }

            let sourceIds = await dbManager.sourceIdsToJSON(sessionIds)
            let inputHash = await dbManager.computeInputHash(sessionTexts)

            print("🔐 [AppCoordinator] Computed input hash: \(inputHash.prefix(16))... from \(sessionTexts.count) session summaries")

            if let existing = try? await dbManager.fetchPeriodSummary(type: .day, date: startOfDay) {
                print("📂 [AppCoordinator] Found existing daily summary (hash: \(existing.inputHash?.prefix(16) ?? "nil")...), engine: \(existing.engineTier ?? "unknown")")
                if existing.inputHash == inputHash, !forceRegenerate {
                    print("💾 [AppCoordinator] ✅ CACHE HIT - Daily rollup unchanged, skipping regeneration")
                    return
                }
                print(forceRegenerate ? "🔄 [AppCoordinator] Force regenerate enabled" : "🔄 [AppCoordinator] Hash mismatch - regenerating daily rollup")
            } else {
                print("📝 [AppCoordinator] No existing daily summary found, will generate new rollup")
            }

            // Generate rollup summary from session summaries (oldest to newest)
            // Store clean text without timestamps - metadata is in periodStart/periodEnd
            print("📝 [AppCoordinator] Generating rollup from \(sessionSummaries.count) session summaries (oldest to newest)")
            let lines = sessionSummaries.map { summary in
                // Clean text only - no timestamps to prevent accumulation in nested rollups
                return "• \(summary.text)"
            }
            let summaryText = lines.joined(separator: "\n")
            let topicsJSON: String? = nil
            let entitiesJSON: String? = nil
            let engineTier = "rollup"

            try await dbManager.upsertPeriodSummary(
                type: .day,
                text: summaryText,
                start: startOfDay,
                end: endOfDay,
                topicsJSON: topicsJSON,
                entitiesJSON: entitiesJSON,
                engineTier: engineTier,
                sourceIds: sourceIds,
                inputHash: inputHash
            )

            print("✅ [AppCoordinator] Daily summary saved (engine: \(engineTier), \(summaryText.count) chars)")
        } catch {
            print("❌ [AppCoordinator] Failed to update daily summary: \(error)")
        }
    }
    
    /// Update or create weekly summary by concatenating daily rollups
    public func updateWeeklySummary(date: Date, forceRegenerate: Bool = false) async {
        guard let dbManager = databaseManager else { return }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = 2 // Monday
        guard let startOfWeek = calendar.date(from: components) else { return }
        guard let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) else { return }

        let periodKey = "week-\(startOfWeek.timeIntervalSince1970)"

        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [AppCoordinator] Weekly summary already being generated, skipping duplicate call...")
            return
        }

        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            print("📊 [AppCoordinator] Updating weekly rollup for \(startOfWeek.formatted(date: .abbreviated, time: .omitted)) - \(endOfWeek.formatted(date: .abbreviated, time: .omitted))")

            let dailySummaries = try await dbManager.fetchDailySummaries(from: startOfWeek, to: endOfWeek)
                .sorted { $0.periodStart < $1.periodStart }
            print("📊 [AppCoordinator] Found \(dailySummaries.count) daily summaries for this week")

            guard !dailySummaries.isEmpty else {
                print("ℹ️ [AppCoordinator] No daily summaries found for this week")
                return
            }

            let dailyIds = dailySummaries.map { $0.id }
            let dailyTexts = dailySummaries.map { $0.text }
            let sourceIds = await dbManager.sourceIdsToJSON(dailyIds)
            let inputHash = await dbManager.computeInputHash(dailyTexts)

            print("🔐 [AppCoordinator] Computed input hash: \(inputHash.prefix(16))... from \(dailyTexts.count) daily summaries")

            if let existing = try? await dbManager.fetchPeriodSummary(type: .week, date: startOfWeek) {
                print("📂 [AppCoordinator] Found existing weekly summary (hash: \(existing.inputHash?.prefix(16) ?? "nil")...), engine: \(existing.engineTier ?? "unknown")")
                if existing.inputHash == inputHash, !forceRegenerate {
                    print("💾 [AppCoordinator] ✅ CACHE HIT - Weekly rollup unchanged, skipping regeneration")
                    return
                }
                print(forceRegenerate ? "🔄 [AppCoordinator] Force regenerate enabled" : "🔄 [AppCoordinator] Hash mismatch - regenerating weekly rollup")
            } else {
                print("📝 [AppCoordinator] No existing weekly summary found, will generate new rollup")
            }

            // Generate rollup summary from daily summaries (oldest to newest)
            // Store clean text without timestamps - metadata is in periodStart/periodEnd
            print("📝 [AppCoordinator] Generating rollup from \(dailySummaries.count) daily summaries (oldest to newest)")
            let lines = dailySummaries.map { summary in
                // Clean text only - no timestamps to prevent accumulation in nested rollups
                return "• \(summary.text)"
            }
            let summaryText = lines.joined(separator: "\n")
            let topicsJSON: String? = nil
            let entitiesJSON: String? = nil
            let engineTier = "rollup"

            try await dbManager.upsertPeriodSummary(
                type: .week,
                text: summaryText,
                start: startOfWeek,
                end: endOfWeek,
                topicsJSON: topicsJSON,
                entitiesJSON: entitiesJSON,
                engineTier: engineTier,
                sourceIds: sourceIds,
                inputHash: inputHash
            )

            print("✅ [AppCoordinator] Weekly summary saved (engine: \(engineTier))")
        } catch {
            print("❌ [AppCoordinator] Failed to update weekly summary: \(error)")
        }
    }
    
    /// Update or create monthly summary by concatenating weekly rollups (or daily when needed)
    public func updateMonthlySummary(date: Date, forceRegenerate: Bool = false) async {
        guard let dbManager = databaseManager else { return }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let startOfMonth = calendar.date(from: components) else { return }
        guard let endOfMonth = calendar.date(byAdding: DateComponents(month: 1), to: startOfMonth) else { return }

        let periodKey = "month-\(startOfMonth.timeIntervalSince1970)"

        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [AppCoordinator] Monthly summary already being generated, skipping duplicate call...")
            return
        }

        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            print("📊 [AppCoordinator] Updating monthly rollup for \(startOfMonth.formatted(date: .abbreviated, time: .omitted))")

            var weeklySummaries = try await dbManager.fetchWeeklySummaries(from: startOfMonth, to: endOfMonth)
                .sorted { $0.periodStart < $1.periodStart }
            print("📊 [AppCoordinator] Found \(weeklySummaries.count) weekly summaries for this month")

            if weeklySummaries.isEmpty {
                print("ℹ️ [AppCoordinator] No weekly summaries found, checking daily summaries...")
                weeklySummaries = try await dbManager.fetchDailySummaries(from: startOfMonth, to: endOfMonth)
                    .sorted { $0.periodStart < $1.periodStart }
            }

            guard !weeklySummaries.isEmpty else {
                print("ℹ️ [AppCoordinator] No rollups found for this month")
                return
            }

            let weeklyIds = weeklySummaries.map { $0.id }
            let weeklyTexts = weeklySummaries.map { $0.text }
            let sourceIds = await dbManager.sourceIdsToJSON(weeklyIds)
            let inputHash = await dbManager.computeInputHash(weeklyTexts)

            print("🔐 [AppCoordinator] Computed input hash: \(inputHash.prefix(16))... from \(weeklyTexts.count) rollups")

            if let existing = try? await dbManager.fetchPeriodSummary(type: .month, date: startOfMonth) {
                print("📂 [AppCoordinator] Found existing monthly summary (hash: \(existing.inputHash?.prefix(16) ?? "nil")...), engine: \(existing.engineTier ?? "unknown")")
                if existing.inputHash == inputHash, !forceRegenerate {
                    print("💾 [AppCoordinator] ✅ CACHE HIT - Monthly rollup unchanged, skipping regeneration")
                    return
                }
                print(forceRegenerate ? "🔄 [AppCoordinator] Force regenerate enabled" : "🔄 [AppCoordinator] Hash mismatch - regenerating monthly rollup")
            } else {
                print("📝 [AppCoordinator] No existing monthly summary found, will generate new rollup")
            }

            // Generate rollup summary from weekly summaries (oldest to newest)
            // Store clean text without timestamps - metadata is in periodStart/periodEnd
            print("📝 [AppCoordinator] Generating rollup from \(weeklySummaries.count) weekly summaries (oldest to newest)")
            let lines = weeklySummaries.map { summary in
                // Clean text only - no timestamps to prevent accumulation in nested rollups
                return "• \(summary.text)"
            }
            let summaryText = lines.joined(separator: "\n")
            let topicsJSON: String? = nil
            let entitiesJSON: String? = nil
            let engineTier = "rollup"

            try await dbManager.upsertPeriodSummary(
                type: .month,
                text: summaryText,
                start: startOfMonth,
                end: endOfMonth,
                topicsJSON: topicsJSON,
                entitiesJSON: entitiesJSON,
                engineTier: engineTier,
                sourceIds: sourceIds,
                inputHash: inputHash
            )

            print("✅ [AppCoordinator] Monthly summary saved (engine: \(engineTier))")
        } catch {
            print("❌ [AppCoordinator] Failed to update monthly summary: \(error)")
        }
    }
    
    /// Update or create yearly summary by concatenating monthly rollups (no external calls)
    public func updateYearlySummary(date: Date, forceRegenerate: Bool = false) async {
        guard let dbManager = databaseManager else { return }

        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1
        guard let startOfYear = calendar.date(from: startComponents) else { return }
        guard let endOfYear = calendar.date(byAdding: DateComponents(year: 1), to: startOfYear) else { return }

        let periodKey = "year-\(startOfYear.timeIntervalSince1970)"

        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [AppCoordinator] Yearly summary already being generated, skipping duplicate call...")
            return
        }

        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            print("📊 [AppCoordinator] Updating yearly rollup for \(year)")

            var monthlySummaries = try await dbManager.fetchMonthlySummaries(from: startOfYear, to: endOfYear)
                .sorted { $0.periodStart < $1.periodStart }
            print("📊 [AppCoordinator] Found \(monthlySummaries.count) monthly summaries for this year")

            if monthlySummaries.isEmpty {
                print("ℹ️ [AppCoordinator] No monthly summaries found, checking weekly summaries...")
                monthlySummaries = try await dbManager.fetchWeeklySummaries(from: startOfYear, to: endOfYear)
                    .sorted { $0.periodStart < $1.periodStart }
            }

            guard !monthlySummaries.isEmpty else {
                print("ℹ️ [AppCoordinator] No rollups found for this year")
                return
            }

            let monthlyIds = monthlySummaries.map { $0.id }
            let monthlyTexts = monthlySummaries.map { $0.text }
            let sourceIds = await dbManager.sourceIdsToJSON(monthlyIds)
            let inputHash = await dbManager.computeInputHash(monthlyTexts)

            print("🔐 [AppCoordinator] Computed input hash: \(inputHash.prefix(16))... from \(monthlyTexts.count) rollups")

            if let existing = try? await dbManager.fetchPeriodSummary(type: .year, date: startOfYear) {
                print("📂 [AppCoordinator] Found existing yearly summary (hash: \(existing.inputHash?.prefix(16) ?? "nil")...)")
                if existing.inputHash == inputHash, !forceRegenerate {
                    print("💾 [AppCoordinator] ✅ CACHE HIT - Yearly rollup unchanged, skipping regeneration")
                    return
                }
                print(forceRegenerate ? "🔄 [AppCoordinator] Force regenerate enabled" : "🔄 [AppCoordinator] Hash mismatch - regenerating yearly rollup")
            } else {
                print("📝 [AppCoordinator] No existing yearly summary found, will generate new rollup")
            }

            // Store clean text without timestamps - metadata is in periodStart/periodEnd
            let lines = monthlySummaries.map { summary in
                // Clean text only - no timestamps to prevent accumulation in nested rollups
                return "• \(summary.text)"
            }
            let rollupText = lines.joined(separator: "\n")

            try await dbManager.upsertPeriodSummary(
                type: .year,
                text: rollupText,
                start: startOfYear,
                end: endOfYear,
                topicsJSON: nil,
                entitiesJSON: nil,
                engineTier: "rollup",
                sourceIds: sourceIds,
                inputHash: inputHash
            )

            print("✅ [AppCoordinator] Yearly rollup updated (engine: rollup)")
        } catch {
            print("❌ [AppCoordinator] Failed to update yearly summary: \(error)")
        }
    }

    /// Manual Year Wrap using external intelligence (keeps deterministic rollup as default)
    public func wrapUpYear(date: Date, forceRegenerate: Bool = false) async {
        guard let dbManager = databaseManager,
              let coordinator = summarizationCoordinator else { return }

        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1
        guard let startOfYear = calendar.date(from: startComponents) else { return }
        guard let endOfYear = calendar.date(byAdding: DateComponents(year: 1), to: startOfYear) else { return }

        let periodKey = "yearwrap-\(startOfYear.timeIntervalSince1970)"

        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [AppCoordinator] Year Wrap already in progress, skipping duplicate call...")
            return
        }

        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            print("📊 [AppCoordinator] Starting Year Wrap for \(year)")

            var sourceSummaries = try await dbManager.fetchMonthlySummaries(from: startOfYear, to: endOfYear)
                .sorted { $0.periodStart < $1.periodStart }

            if sourceSummaries.isEmpty {
                sourceSummaries = try await dbManager.fetchWeeklySummaries(from: startOfYear, to: endOfYear)
                    .sorted { $0.periodStart < $1.periodStart }
            }

            guard !sourceSummaries.isEmpty else {
                print("ℹ️ [AppCoordinator] No rollups available to build a Year Wrap")
                return
            }

            let sourceIds = await dbManager.sourceIdsToJSON(sourceSummaries.map { $0.id })
            let inputHash = await dbManager.computeInputHash(sourceSummaries.map { $0.text })

            if let existing = try? await dbManager.fetchPeriodSummary(type: .yearWrap, date: startOfYear) {
                print("📂 [AppCoordinator] Found existing Year Wrap (hash: \(existing.inputHash?.prefix(16) ?? "nil")...)")
                if existing.inputHash == inputHash, !forceRegenerate {
                    print("💾 [AppCoordinator] ✅ CACHE HIT - Year Wrap unchanged, skipping external call")
                    return
                }
                print(forceRegenerate ? "🔄 [AppCoordinator] Force regenerate enabled" : "🔄 [AppCoordinator] Hash mismatch - regenerating Year Wrap")
            } else {
                print("📝 [AppCoordinator] No Year Wrap found, generating new one")
            }

            let wrapSummary = try await coordinator.generateYearWrapSummary(
                startOfYear: startOfYear,
                endOfYear: endOfYear,
                sourceSummaries: sourceSummaries
            )

            try await dbManager.upsertPeriodSummary(
                type: .yearWrap,
                text: wrapSummary.text,
                start: startOfYear,
                end: endOfYear,
                topicsJSON: wrapSummary.topicsJSON,
                entitiesJSON: wrapSummary.entitiesJSON,
                engineTier: wrapSummary.engineTier ?? EngineTier.external.rawValue,
                sourceIds: sourceIds,
                inputHash: inputHash
            )

            print("✅ [AppCoordinator] Year Wrap saved (engine: \(wrapSummary.engineTier ?? "external"))")
        } catch {
            print("❌ [AppCoordinator] Failed to generate Year Wrap: \(error)")
            showError("Year Wrap failed. Check your external key and try again.")
        }
    }

    // MARK: - Rollup Helpers

    private func buildRollupText(header: String, lines: [String]) -> String {
        guard !lines.isEmpty else { return header }
        return ([header] + lines).joined(separator: "\n")
    }

    private var rollupTimeFormatter: DateFormatter { Self.rollupTimeFormatter }
    private var rollupDateFormatter: DateFormatter { Self.rollupDateFormatter }
    private var rollupMonthRangeFormatter: DateFormatter { Self.rollupMonthRangeFormatter }
    private var rollupYearMonthFormatter: DateFormatter { Self.rollupYearMonthFormatter }

    private static let rollupTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let rollupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let rollupMonthRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let rollupYearMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter
    }()
    
    /// Format date and time for rollup bulletins using user-configured formats
    private func formatRollupDateTime(_ date: Date) -> String {
        let dateFormat = UserDefaults.standard.rollupDateFormat
        let timeFormat = UserDefaults.standard.rollupTimeFormat
        
        let formatter = DateFormatter()
        formatter.dateFormat = "\(dateFormat) \(timeFormat)"
        return formatter.string(from: date)
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
    
    // MARK: - Hash Utilities
    
    /// Calculate SHA256 hash of input text for cache validation
    private func calculateHash(for text: String) -> String {
        guard let data = text.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Local AI Model Management
    
    /// Check if the local AI model is downloaded
    public func isLocalModelDownloaded() async -> Bool {
        guard let coordinator = summarizationCoordinator else { return false }
        return await coordinator.getLocalEngine().isModelDownloaded()
    }
    
    /// Download the local AI model in the background
    /// Download continues even if user navigates away from Settings
    public func startLocalModelDownload() {
        guard !isDownloadingLocalModel else { return }
        guard let coordinator = summarizationCoordinator else { return }
        
        isDownloadingLocalModel = true
        
        localModelDownloadTask = Task {
            do {
                try await coordinator.getLocalEngine().downloadModel(progress: nil)
                
                // After successful download, switch to Local AI
                await coordinator.setPreferredEngine(.local)
                
                await MainActor.run {
                    self.isDownloadingLocalModel = false
                    self.showSuccess("Local AI model downloaded and activated")
                }
                
                // Notify that engine changed
                NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            } catch {
                await MainActor.run {
                    self.isDownloadingLocalModel = false
                    self.showError("Download failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Download the local AI model with progress tracking (for setup flow)
    /// - Parameter progress: Closure called with download progress (0.0-1.0)
    public func downloadLocalModel(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard let coordinator = summarizationCoordinator else {
            throw AppCoordinatorError.notInitialized
        }
        isDownloadingLocalModel = true
        defer { isDownloadingLocalModel = false }
        try await coordinator.getLocalEngine().downloadModel(progress: progress)
        showSuccess("Local AI model downloaded")
    }
    
    /// Delete the local AI model and switch to Basic tier if needed
    public func deleteLocalModel() async throws {
        guard let coordinator = summarizationCoordinator else {
            throw AppCoordinatorError.notInitialized
        }
        
        // Cancel any ongoing download
        localModelDownloadTask?.cancel()
        localModelDownloadTask = nil
        isDownloadingLocalModel = false
        
        // Delete the model
        try await coordinator.getLocalEngine().deleteModel()
        
        // If current tier is .local, switch to .basic
        let currentTier = await coordinator.getActiveEngine()
        if currentTier == .local {
            await coordinator.setPreferredEngine(.basic)
        }
        
        showSuccess("Local AI model deleted")
    }
    
    /// Get formatted model size string: "Downloaded (2282 MB)" or "Not Downloaded"
    public func localModelSizeFormatted() async -> String {
        guard let coordinator = summarizationCoordinator else { return "Not Downloaded" }
        return await coordinator.getLocalEngine().modelSizeFormatted()
    }
    
    /// Get the expected model size for display before download
    public var expectedLocalModelSizeMB: String {
        return "~2.3 GB"
    }
    
    /// Get the local model display name
    public var localModelDisplayName: String {
        return "Phi-3.5 Mini"
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
