// =============================================================================
// AppCoordinator — Central orchestrator for Life Wrapped
// =============================================================================

import Foundation
import SwiftUI
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
    
    // MARK: - Dependencies
    
    private var databaseManager: DatabaseManager?
    private let audioCapture: AudioCaptureManager
    private var transcriptionManager: TranscriptionManager?
    private var summarizationManager: SummarizationManager?
    private var insightsManager: InsightsManager?
    private let widgetDataManager: WidgetDataManager
    
    // MARK: - Recording State
    
    private var recordingStartTime: Date?
    private var lastCompletedChunk: AudioChunk?
    
    // MARK: - Initialization
    
    public init(
        widgetDataManager: WidgetDataManager = .shared
    ) {
        self.audioCapture = AudioCaptureManager()
        self.widgetDataManager = widgetDataManager
        
        // Setup chunk completion callback
        setupAudioCaptureCallback()
    }
    
    private func setupAudioCaptureCallback() {
        audioCapture.onChunkCompleted = { [weak self] chunk in
            await MainActor.run {
                self?.lastCompletedChunk = chunk
            }
        }
    }
    
    // MARK: - Async Initialization
    
    /// Initialize the app coordinator and load initial state
    public func initialize() async {
        guard !isInitialized else { return }
        
        do {
            // Initialize database
            let dbManager = try await DatabaseManager()
            self.databaseManager = dbManager
            
            // Initialize managers that need storage
            self.transcriptionManager = TranscriptionManager(storage: dbManager)
            self.summarizationManager = SummarizationManager(storage: dbManager)
            self.insightsManager = InsightsManager(storage: dbManager)
            
            // Load current streak
            await refreshStreak()
            
            // Load today's stats
            await refreshTodayStats()
            
            // Update widget
            await updateWidgetData()
            
            isInitialized = true
            initializationError = nil
            
        } catch {
            initializationError = error
            isInitialized = false
        }
    }
    
    // MARK: - Recording
    
    /// Start a new recording session
    public func startRecording() async throws {
        guard isInitialized else {
            throw AppCoordinatorError.notInitialized
        }
        
        guard !recordingState.isRecording else {
            throw AppCoordinatorError.recordingInProgress
        }
        
        // Clear any previous chunk
        lastCompletedChunk = nil
        
        // Start recording
        try await audioCapture.startRecording(mode: .active)
        
        recordingStartTime = Date()
        recordingState = .recording(startTime: Date())
    }
    
    /// Stop the current recording and process it through the pipeline
    /// Returns the UUID of the saved AudioChunk
    public func stopRecording() async throws -> UUID {
        guard case .recording = recordingState else {
            throw AppCoordinatorError.noActiveRecording
        }
        
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        recordingState = .processing
        
        do {
            // 1. Stop audio capture - this triggers onChunkCompleted callback
            try await audioCapture.stopRecording()
            
            // Wait a moment for callback to be called
            try? await Task.sleep(for: .milliseconds(100))
            
            // 2. Get the completed chunk
            guard let chunk = lastCompletedChunk else {
                throw AppCoordinatorError.storageFailed(
                    NSError(domain: "AppCoordinator", code: -1, 
                           userInfo: [NSLocalizedDescriptionKey: "No audio chunk received"])
                )
            }
            
            // 3. Save the audio chunk to storage
            try await dbManager.insertAudioChunk(chunk)
            
            // 4. Transcribe the audio
            let segments = try await transcribeAudio(chunk: chunk)
            
            // 5. Save transcript segments to storage
            for segment in segments {
                try await dbManager.insertTranscriptSegment(segment)
            }
            
            // 6. Generate summary if enough content
            await generateSummaryIfNeeded(segments: segments)
            
            // 7. Update rollups and stats
            await updateRollupsAndStats()
            
            // 8. Update widget data
            await updateWidgetData()
            
            // Reset recording state
            recordingStartTime = nil
            lastCompletedChunk = nil
            recordingState = .completed(chunkId: chunk.id)
            
            return chunk.id
            
        } catch {
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
    
    // MARK: - Private Recording Helpers
    
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
            
        } catch {
            print("Rollup generation failed: \(error)")
        }
        
        // Refresh local stats
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
        guard let dbManager = databaseManager else { return }
        
        let today = Calendar.current.startOfDay(for: Date())
        
        do {
            // Fetch today's rollup if it exists
            let rollups = try await dbManager.fetchRollups(bucketType: .day, limit: 1)
            
            if let todayRollup = rollups.first,
               Calendar.current.isDate(todayRollup.bucketStart, inSameDayAs: today) {
                todayStats = DayStats(
                    date: today,
                    segmentCount: todayRollup.segmentCount,
                    wordCount: todayRollup.wordCount,
                    totalDuration: todayRollup.speakingSeconds
                )
            } else {
                todayStats = DayStats.empty
            }
        } catch {
            print("Failed to refresh today stats: \(error)")
            todayStats = DayStats.empty
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
    
    /// Fetch recent audio chunks (recordings)
    public func fetchRecentRecordings(limit: Int = 20) async throws -> [AudioChunk] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchAllAudioChunks(limit: limit)
    }
    
    /// Fetch transcript segments for an audio chunk
    public func fetchTranscript(for chunkId: UUID) async throws -> [TranscriptSegment] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchTranscriptSegments(audioChunkID: chunkId)
    }
    
    /// Fetch recent summaries
    public func fetchRecentSummaries(limit: Int = 10) async throws -> [Summary] {
        guard let dbManager = databaseManager else {
            throw AppCoordinatorError.notInitialized
        }
        
        return try await dbManager.fetchSummaries(limit: limit)
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
