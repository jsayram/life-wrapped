// =============================================================================
// AppCoordinator — Central orchestrator for Life Wrapped
// =============================================================================

import Foundation
import SwiftUI
import UIKit
import AVFoundation
import Speech
import SharedModels
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
    
    // MARK: - Dependencies
    
    private var databaseManager: DatabaseManager?
    public let audioCapture: AudioCaptureManager
    public let audioPlayback: AudioPlaybackManager
    private var transcriptionManager: TranscriptionManager?
    private var summarizationManager: SummarizationManager?
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
            
            // Initialize managers that need storage
            print("🎤 [AppCoordinator] Initializing TranscriptionManager...")
            self.transcriptionManager = TranscriptionManager(storage: dbManager)
            print("📝 [AppCoordinator] Initializing SummarizationManager...")
            self.summarizationManager = SummarizationManager(storage: dbManager)
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
        needsPermissions = false
        await initialize()
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
        
        // Fetch chunks for each session and build RecordingSession objects
        var sessions: [RecordingSession] = []
        for (sessionId, _, _) in sessionMetadata {
            let chunks = try await dbManager.fetchChunksBySession(sessionId: sessionId)
            let session = RecordingSession(sessionId: sessionId, chunks: chunks)
            sessions.append(session)
        }
        
        return sessions
    }
    
    /// Fetch specific sessions by IDs
    public func fetchSessions(ids: [UUID]) async throws -> [RecordingSession] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        // Fetch chunks for each session and build RecordingSession objects
        var sessions: [RecordingSession] = []
        for sessionId in ids {
            let chunks = try await dbManager.fetchChunksBySession(sessionId: sessionId)
            if !chunks.isEmpty {
                let session = RecordingSession(sessionId: sessionId, chunks: chunks)
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
        
        guard let dbManager = databaseManager else {
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
        await MainActor.run {
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
        do {
            // Check if all chunks are transcribed
            let isComplete = try await isSessionTranscriptionComplete(sessionId: sessionId)
            guard isComplete else {
                print("⏳ [AppCoordinator] Session \(sessionId) not yet complete, skipping summary")
                return
            }
            
            // Check if summary already exists
            guard let dbManager = databaseManager else { return }
            if let existingSummary = try await dbManager.fetchSummaryForSession(sessionId: sessionId) {
                print("ℹ️ [AppCoordinator] Summary already exists for session \(sessionId)")
                return
            }
            
            // Generate session summary
            print("📝 [AppCoordinator] Generating summary for session \(sessionId)...")
            try await generateSessionSummary(sessionId: sessionId)
            print("✅ [AppCoordinator] Session summary generated")
            
        } catch {
            print("❌ [AppCoordinator] Failed to check/generate session summary: \(error)")
        }
    }
    
    /// Generate a summary for an entire session
    private func generateSessionSummary(sessionId: UUID) async throws {
        guard let dbManager = databaseManager,
              let summarizer = summarizationManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        // Get all transcript segments for the session
        let allSegments = try await fetchSessionTranscript(sessionId: sessionId)
        
        // Combine all text
        let fullText = allSegments.map { $0.text }.joined(separator: " ")
        let wordCount = fullText.split(separator: " ").count
        
        // Only summarize if there's enough content (at least 50 words)
        guard wordCount >= 50 else {
            print("ℹ️ [AppCoordinator] Session has only \(wordCount) words, skipping summary")
            return
        }
        
        // Get session time range
        let chunks = try await dbManager.fetchChunksBySession(sessionId: sessionId)
        guard let firstChunk = chunks.first, let lastChunk = chunks.last else { return }
        
        let periodStart = firstChunk.startTime
        let periodEnd = lastChunk.endTime
        
        // Generate summary using the date range method
        print("📝 [AppCoordinator] Summarizing \(wordCount) words from session...")
        let generatedSummary = try await summarizer.generateSummary(from: periodStart, to: periodEnd)
        let summaryText = generatedSummary.text
        
        // Save session summary
        let summary = Summary(
            periodType: .session,
            periodStart: periodStart,
            periodEnd: periodEnd,
            text: summaryText,
            sessionId: sessionId
        )
        
        try await dbManager.insertSummary(summary)
        print("✅ [AppCoordinator] Session summary saved")
    }
    
    private func transcribeAudio(chunk: AudioChunk) async throws -> [TranscriptSegment] {
        guard let transcriber = transcriptionManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        do {
            let segments = try await transcriber.transcribe(chunk: chunk)
            return segments
        } catch {
            throw AppCoordinatorError.transcriptionFailed(error)
        }
    }
    
    private func generateSummaryIfNeeded(segments: [TranscriptSegment]) async {
        guard let summarizer = summarizationManager else { return }
        
        // Combine all segment text
        let fullText = segments.map { $0.text }.joined(separator: " ")
        
        // Only summarize if there's enough content (at least 50 words)
        let wordCount = fullText.split(separator: " ").count
        guard wordCount >= 50 else { return }
        
        do {
            // Generate daily summary for today
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
            
            _ = try await summarizer.generateSummary(from: today, to: tomorrow)
            
        } catch {
            // Log but don't fail the recording flow for summarization errors
            print("Summarization failed: \(error)")
        }
    }
    
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
}

// MARK: - Preview Support

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
