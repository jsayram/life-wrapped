import Foundation
import SharedModels
import Storage
import InsightsRollup

/// Manages data access, statistics, and session queries
@MainActor
public final class DataCoordinator {
    
    // MARK: - Dependencies
    
    private let databaseManager: DatabaseManager
    private let insightsManager: InsightsManager
    
    // MARK: - Initialization
    
    public init(databaseManager: DatabaseManager, insightsManager: InsightsManager) {
        self.databaseManager = databaseManager
        self.insightsManager = insightsManager
    }
    
    // MARK: - Stats & Rollups
    
    /// Calculate current streak from recording sessions (not transcript segments)
    /// This ensures streak updates immediately when a recording is made,
    /// without waiting for transcription to complete.
    public func calculateStreak() async throws -> Int {
        // Get all sessions (up to 365 for a year of data)
        let sessions = try await databaseManager.fetchSessions(limit: 365)
        
        // Extract unique dates from session start times
        let activityDates = sessions.map { $0.firstChunkTime }
        
        let streakInfo = StreakCalculator.calculateStreak(from: activityDates)
        return streakInfo.currentStreak
    }
    
    /// Fetch today's stats from rollup
    public func fetchTodayStats() async throws -> DayStats {
        let today = Calendar.current.startOfDay(for: Date())
        
        if let rollup = try await databaseManager.fetchRollup(bucketType: .day, bucketStart: today) {
            return DayStats(
                date: today,
                segmentCount: rollup.segmentCount,
                wordCount: rollup.wordCount,
                totalDuration: rollup.speakingSeconds
            )
        } else {
            return DayStats.empty
        }
    }
    
    /// Generate rollups for today
    public func generateRollupsForToday() async throws {
        _ = try await insightsManager.generateRollup(bucketType: .day, for: Date())
        print("✅ [DataCoordinator] Daily rollup generated")
    }
    
    // MARK: - Session Queries
    
    /// Fetch multiple sessions by IDs
    public func fetchSessions(ids: [UUID]) async throws -> [RecordingSession] {
        guard !ids.isEmpty else { return [] }
        
        var sessions: [RecordingSession] = []
        for id in ids {
            let chunks = try await databaseManager.fetchChunksBySession(sessionId: id)
            if !chunks.isEmpty {
                sessions.append(RecordingSession(sessionId: id, chunks: chunks))
            }
        }
        return sessions
    }
    
    /// Fetch transcript segments for an audio chunk
    public func fetchTranscript(for chunkId: UUID) async throws -> [TranscriptSegment] {
        return try await databaseManager.fetchTranscriptSegments(audioChunkID: chunkId)
    }
    
    /// Fetch transcript segments for an entire session (all chunks combined)
    public func fetchSessionTranscript(sessionId: UUID) async throws -> [TranscriptSegment] {
        let chunks = try await databaseManager.fetchChunksBySession(sessionId: sessionId)
        
        var allSegments: [TranscriptSegment] = []
        for chunk in chunks {
            let segments = try await databaseManager.fetchTranscriptSegments(audioChunkID: chunk.id)
            allSegments.append(contentsOf: segments)
        }
        
        return allSegments.sorted { $0.createdAt < $1.createdAt }
    }
    
    /// Get total word count for a session
    public func getSessionWordCount(sessionId: UUID) async throws -> Int {
        let transcript = try await fetchSessionTranscript(sessionId: sessionId)
        return transcript.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
    
    /// Check if all chunks in a session have been transcribed
    public func isSessionTranscriptionComplete(sessionId: UUID) async throws -> Bool {
        return try await databaseManager.isSessionTranscriptionComplete(sessionId: sessionId)
    }
    
    // MARK: - Summaries
    
    /// Fetch summary for a session
    public func fetchSessionSummary(sessionId: UUID) async throws -> Summary? {
        return try await databaseManager.fetchSummaryForSession(sessionId: sessionId)
    }
    
    /// Append user notes to existing session summary without AI regeneration
    public func appendNotesToSessionSummary(sessionId: UUID, notes: String) async throws {
        guard let existingSummary = try await databaseManager.fetchSummaryForSession(sessionId: sessionId) else {
            throw NSError(domain: "DataCoordinator", code: -1, userInfo: [NSLocalizedDescriptionKey: "No summary found for session"])
        }
        
        let updatedText = existingSummary.text + "\n\nAdditional Notes:\n" + notes
        
        let updatedSummary = Summary(
            id: existingSummary.id,
            periodType: existingSummary.periodType,
            periodStart: existingSummary.periodStart,
            periodEnd: existingSummary.periodEnd,
            text: updatedText,
            createdAt: existingSummary.createdAt,
            sessionId: existingSummary.sessionId,
            topicsJSON: existingSummary.topicsJSON,
            entitiesJSON: existingSummary.entitiesJSON,
            engineTier: existingSummary.engineTier,
            sourceIds: existingSummary.sourceIds,
            inputHash: existingSummary.inputHash
        )
        
        try await databaseManager.deleteSummary(id: existingSummary.id)
        try await databaseManager.insertSummary(updatedSummary)
        
        print("✅ [DataCoordinator] Appended notes to session summary")
    }
    
    /// Fetch recent summaries
    public func fetchRecentSummaries(limit: Int = 10) async throws -> [Summary] {
        return try await databaseManager.fetchSummaries(limit: limit)
    }
    
    /// Fetch period summary for a specific date and type
    public func fetchPeriodSummary(type: PeriodType, date: Date) async throws -> Summary? {
        return try await databaseManager.fetchPeriodSummary(type: type, date: date)
    }
    
    // MARK: - Session Analytics
    
    /// Fetch sessions grouped by year with aggregated statistics
    public func fetchYearlyData() async throws -> [(year: Int, sessionCount: Int, wordCount: Int, duration: TimeInterval)] {
        let yearData = try await databaseManager.fetchSessionsByYear()
        
        return try await withThrowingTaskGroup(of: (year: Int, sessionCount: Int, wordCount: Int, duration: TimeInterval).self) { group in
            for yearInfo in yearData {
                group.addTask {
                    // Calculate word count for all sessions in this year
                    var totalWords = 0
                    var totalDuration: TimeInterval = 0
                    
                    for sessionId in yearInfo.sessionIds {
                        // Fetch word count from database (uses cached word_count column)
                        let wordCount = try await self.databaseManager.fetchSessionWordCount(sessionId: sessionId)
                        totalWords += wordCount
                        
                        // Fetch all chunks for this session to calculate duration
                        let chunks = try await self.databaseManager.fetchChunksBySession(sessionId: sessionId)
                        totalDuration += chunks.reduce(0.0) { $0 + $1.duration }
                    }
                    
                    return (
                        year: yearInfo.year,
                        sessionCount: yearInfo.count,
                        wordCount: totalWords,
                        duration: totalDuration
                    )
                }
            }
            
            var results: [(year: Int, sessionCount: Int, wordCount: Int, duration: TimeInterval)] = []
            for try await result in group {
                results.append(result)
            }
            
            return results.sorted { $0.year > $1.year } // Most recent year first
        }
    }
    
    /// Delete all data for a specific year
    public func deleteDataForYear(year: Int) async throws {
        // Get all sessions for this year
        let yearData = try await databaseManager.fetchSessionsByYear()
        guard let yearInfo = yearData.first(where: { $0.year == year }) else {
            print("⚠️ [DataCoordinator] No data found for year \(year)")
            return
        }
        
        // Delete each session's data
        for sessionId in yearInfo.sessionIds {
            // Fetch chunks for this session
            let chunks = try await databaseManager.fetchChunksBySession(sessionId: sessionId)
            
            // Delete audio files
            for chunk in chunks {
                try? FileManager.default.removeItem(at: chunk.fileURL)
            }
            
            // Delete transcript segments
            for chunk in chunks {
                let segments = try await databaseManager.fetchTranscriptSegments(audioChunkID: chunk.id)
                for segment in segments {
                    try await databaseManager.deleteTranscriptSegment(id: segment.id)
                }
            }
            
            // Delete audio chunks from database
            for chunk in chunks {
                try await databaseManager.deleteAudioChunk(id: chunk.id)
            }
            
            // Delete session metadata
            try? await databaseManager.deleteSessionMetadata(sessionId: sessionId)
            
            // Delete session summary
            if let summary = try await databaseManager.fetchSummaryForSession(sessionId: sessionId) {
                try await databaseManager.deleteSummary(id: summary.id)
            }
        }
        
        print("✅ [DataCoordinator] Deleted all data for year \(year)")
    }
    
    /// Fetch sessions grouped by hour of day
    public func fetchSessionsByHour() async throws -> [(hour: Int, count: Int, sessionIds: [UUID])] {
        return try await databaseManager.fetchSessionsByHour()
    }
    
    /// Fetch the longest recording session
    public func fetchLongestSession() async throws -> (sessionId: UUID, duration: TimeInterval, date: Date)? {
        return try await databaseManager.fetchLongestSession()
    }
    
    /// Fetch the most active month
    public func fetchMostActiveMonth() async throws -> (year: Int, month: Int, count: Int, sessionIds: [UUID])? {
        return try await databaseManager.fetchMostActiveMonth()
    }
    
    /// Fetch sessions grouped by day of week
    public func fetchSessionsByDayOfWeek() async throws -> [(dayOfWeek: Int, count: Int, sessionIds: [UUID])] {
        return try await databaseManager.fetchSessionsByDayOfWeek()
    }
    
    /// Fetch all transcript text within a date range
    public func fetchTranscriptText(startDate: Date, endDate: Date) async throws -> [String] {
        return try await databaseManager.fetchTranscriptText(startDate: startDate, endDate: endDate)
    }
    
    // MARK: - Sentiment Analysis
    
    /// Fetch daily sentiment averages for a date range
    public func fetchDailySentiment(from startDate: Date, to endDate: Date) async throws -> [(date: Date, sentiment: Double)] {
        return try await databaseManager.fetchDailySentiment(from: startDate, to: endDate)
    }
    
    /// Fetch sentiment for a specific session
    public func fetchSessionSentiment(sessionId: UUID) async throws -> Double? {
        return try await databaseManager.fetchSessionSentiment(sessionId: sessionId)
    }
    
    // MARK: - Language Detection
    
    /// Fetch language distribution (language code and word count)
    public func fetchLanguageDistribution() async throws -> [(language: String, wordCount: Int)] {
        return try await databaseManager.fetchLanguageDistribution()
    }
    
    /// Fetch dominant language for a specific session
    public func fetchSessionLanguage(sessionId: UUID) async throws -> String? {
        return try await databaseManager.fetchSessionLanguage(sessionId: sessionId)
    }
    
    // MARK: - Session Metadata
    
    /// Update session title
    public func updateSessionTitle(sessionId: UUID, title: String?) async throws {
        try await databaseManager.updateSessionTitle(sessionId: sessionId, title: title)
        print("📝 [DataCoordinator] Updated session title: \(title ?? "nil")")
    }
    
    /// Update session notes
    public func updateSessionNotes(sessionId: UUID, notes: String?) async throws {
        try await databaseManager.updateSessionNotes(sessionId: sessionId, notes: notes)
        print("📝 [DataCoordinator] Updated session notes")
    }
    
    /// Toggle session favorite status
    public func toggleSessionFavorite(sessionId: UUID) async throws -> Bool {
        let isFavorite = try await databaseManager.toggleSessionFavorite(sessionId: sessionId)
        print("⭐ [DataCoordinator] Session favorite: \(isFavorite)")
        return isFavorite
    }
    
    /// Update session category
    public func updateSessionCategory(sessionId: UUID, category: SessionCategory?) async throws {
        try await databaseManager.updateSessionCategory(sessionId: sessionId, category: category)
        print("🏷️ [DataCoordinator] Session category updated: \(category?.displayName ?? "None")")
    }
    
    /// Fetch session metadata
    public func fetchSessionMetadata(sessionId: UUID) async throws -> DatabaseManager.SessionMetadata? {
        return try await databaseManager.fetchSessionMetadata(sessionId: sessionId)
    }
    
    // MARK: - Transcript Editing
    
    /// Update transcript segment text (for user edits)
    public func updateTranscriptText(segmentId: UUID, newText: String) async throws {
        try await databaseManager.updateTranscriptSegmentText(id: segmentId, newText: newText)
        print("✏️ [DataCoordinator] Updated transcript segment: \(segmentId)")
    }
    
    /// Search for sessions by transcript text
    public func searchSessionsByTranscript(query: String) async throws -> Set<UUID> {
        return try await databaseManager.searchSessionsByTranscript(query: query)
    }
    
    // MARK: - Delete Statistics
    
    /// Get statistics about data to be deleted (for confirmation dialog)
    public func getDeleteStats() async -> (chunks: Int, transcripts: Int, summaries: Int, modelSize: String) {
        do {
            let chunks = try await databaseManager.fetchAllAudioChunks()
            let summaries = try await databaseManager.fetchAllSummaries()
            
            // Calculate total transcript segments across all chunks
            var transcriptCount = 0
            for chunk in chunks {
                let segments = try await databaseManager.fetchTranscriptSegments(audioChunkID: chunk.id)
                transcriptCount += segments.count
            }
            
            return (
                chunks: chunks.count,
                transcripts: transcriptCount,
                summaries: summaries.count,
                modelSize: "Not available"
            )
        } catch {
            print("❌ [DataCoordinator] Failed to get delete stats: \(error)")
            return (chunks: 0, transcripts: 0, summaries: 0, modelSize: "Unknown")
        }
    }
}
