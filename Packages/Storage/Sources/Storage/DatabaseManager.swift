// =============================================================================
// Storage — Database Manager (Facade)
// =============================================================================
// Thin facade that delegates to specialized repositories.
// Maintains backward-compatible public API while repositories handle operations.
// =============================================================================

import Foundation
import SharedModels
import CryptoKit

/// Thread-safe SQLite database manager (facade)
public actor DatabaseManager {
    
    // MARK: - Type Aliases (for backward compatibility)
    
    /// Session metadata type alias for backward compatibility
    public typealias SessionMetadata = SessionRepository.SessionMetadata
    
    // MARK: - Connection & Repositories
    
    private let connection: DatabaseConnection
    private let schemaManager: SchemaManager
    private let audioChunkRepository: AudioChunkRepository
    private let sessionRepository: SessionRepository
    private let transcriptRepository: TranscriptRepository
    private let summaryRepository: SummaryRepository
    private let insightsRepository: InsightsRepository
    private let controlEventRepository: ControlEventRepository
    
    // MARK: - Initialization
    
    public init(containerIdentifier: String = AppConstants.appGroupIdentifier) async throws {
        print("💾 [DatabaseManager] Looking for App Group: \(containerIdentifier)")
        
        // Initialize connection
        self.connection = try await DatabaseConnection(containerIdentifier: containerIdentifier)
        print("✅ [DatabaseManager] Connection established")
        
        // Initialize schema manager and run migrations
        self.schemaManager = SchemaManager(connection: connection)
        try await schemaManager.migrate()
        print("✅ [DatabaseManager] Migrations complete")
        
        // Initialize repositories
        self.audioChunkRepository = AudioChunkRepository(connection: connection)
        self.sessionRepository = SessionRepository(connection: connection)
        self.transcriptRepository = TranscriptRepository(connection: connection)
        self.summaryRepository = SummaryRepository(connection: connection)
        self.insightsRepository = InsightsRepository(connection: connection)
        self.controlEventRepository = ControlEventRepository(connection: connection)
        
        print("✅ [DatabaseManager] All repositories initialized")
    }
    
    /// Close the database connection
    public func close() async {
        await connection.close()
    }
    
    /// Public accessor for database path
    public func getDatabasePath() async -> String {
        await connection.getDatabasePath()
    }
    
    // MARK: - Utility Functions
    
    /// Compute input hash for summary caching
    public func computeInputHash(_ texts: [String]) -> String {
        let combined = texts.joined(separator: "\n")
        let data = Data(combined.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    
    /// Convert source IDs to JSON string
    public func sourceIdsToJSON(_ ids: [UUID]) -> String {
        let strings = ids.map { $0.uuidString }
        let data = try? JSONEncoder().encode(strings)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
    
    // MARK: - AudioChunk CRUD
    
    public func insertAudioChunk(_ chunk: AudioChunk) async throws {
        try await audioChunkRepository.insert(chunk)
    }
    
    public func fetchAudioChunk(id: UUID) async throws -> AudioChunk? {
        try await audioChunkRepository.fetch(id: id)
    }
    
    public func fetchAllAudioChunks(limit: Int? = nil, offset: Int = 0) async throws -> [AudioChunk] {
        try await audioChunkRepository.fetchAll(limit: limit, offset: offset)
    }
    
    public func fetchRecentAudioChunks(limit: Int = 50) async throws -> [AudioChunk] {
        try await audioChunkRepository.fetchRecent(limit: limit)
    }
    
    public func deleteAudioChunk(id: UUID) async throws {
        try await audioChunkRepository.delete(id: id)
    }
    
    // MARK: - Session Queries
    
    public func fetchChunksBySession(sessionId: UUID) async throws -> [AudioChunk] {
        try await sessionRepository.fetchChunksBySession(sessionId: sessionId)
    }
    
    public func fetchSessions(limit: Int = 100) async throws -> [(sessionId: UUID, firstChunkTime: Date, chunkCount: Int)] {
        try await sessionRepository.fetchSessions(limit: limit)
    }
    
    public func fetchSessionsByHour() async throws -> [(hour: Int, count: Int, sessionIds: [UUID])] {
        try await sessionRepository.fetchSessionsByHour()
    }
    
    public func fetchLongestSession() async throws -> (sessionId: UUID, duration: TimeInterval, date: Date)? {
        try await sessionRepository.fetchLongestSession()
    }
    
    public func fetchMostActiveMonth() async throws -> (year: Int, month: Int, count: Int, sessionIds: [UUID])? {
        try await sessionRepository.fetchMostActiveMonth()
    }
    
    public func fetchSessionsByDayOfWeek() async throws -> [(dayOfWeek: Int, count: Int, sessionIds: [UUID])] {
        try await sessionRepository.fetchSessionsByDayOfWeek()
    }
    
    public func fetchSessionsByYear() async throws -> [(year: Int, count: Int, sessionIds: [UUID])] {
        try await sessionRepository.fetchSessionsByYear()
    }
    
    public func deleteSession(sessionId: UUID) async throws {
        try await sessionRepository.deleteSession(sessionId: sessionId)
    }
    
    public func fetchSessionsByDate(date: Date) async throws -> [RecordingSession] {
        try await sessionRepository.fetchByDate(date: date)
    }
    
    // MARK: - Session Metadata
    
    public func upsertSessionMetadata(_ metadata: SessionMetadata) async throws {
        try await sessionRepository.upsertSessionMetadata(metadata)
    }
    
    public func fetchSessionMetadata(sessionId: UUID) async throws -> SessionMetadata? {
        try await sessionRepository.fetchSessionMetadata(sessionId: sessionId)
    }
    
    public func updateSessionTitle(sessionId: UUID, title: String?) async throws {
        try await sessionRepository.updateSessionTitle(sessionId: sessionId, title: title)
    }
    
    public func updateSessionNotes(sessionId: UUID, notes: String?) async throws {
        try await sessionRepository.updateSessionNotes(sessionId: sessionId, notes: notes)
    }
    
    public func toggleSessionFavorite(sessionId: UUID) async throws -> Bool {
        try await sessionRepository.toggleSessionFavorite(sessionId: sessionId)
    }
    
    public func updateSessionCategory(sessionId: UUID, category: SessionCategory?) async throws {
        try await sessionRepository.updateSessionCategory(sessionId: sessionId, category: category)
    }
    
    public func fetchSessionsByCategory(category: SessionCategory, limit: Int? = nil) async throws -> [RecordingSession] {
        try await sessionRepository.fetchSessionsByCategory(category: category, limit: limit)
    }
    
    public func fetchSessionMetadataBatch(sessionIds: [UUID]) async throws -> [UUID: SessionMetadata] {
        try await sessionRepository.fetchSessionMetadataBatch(sessionIds: sessionIds)
    }
    
    public func deleteSessionMetadata(sessionId: UUID) async throws {
        try await sessionRepository.deleteSessionMetadata(sessionId: sessionId)
    }
    
    public func deleteAllSessionMetadata() async throws {
        try await sessionRepository.deleteAllMetadata()
    }
    
    // MARK: - Transcript CRUD
    
    public func insertTranscriptSegment(_ segment: TranscriptSegment) async throws {
        try await transcriptRepository.insert(segment)
    }
    
    public func fetchTranscriptSegment(id: UUID) async throws -> TranscriptSegment? {
        try await transcriptRepository.fetch(id: id)
    }
    
    public func fetchTranscriptSegments(audioChunkID: UUID) async throws -> [TranscriptSegment] {
        try await transcriptRepository.fetchSegmentsByChunk(audioChunkID: audioChunkID)
    }
    
    public func deleteTranscriptSegment(id: UUID) async throws {
        try await transcriptRepository.delete(id: id)
    }
    
    public func updateTranscriptSegmentText(id: UUID, newText: String) async throws {
        try await transcriptRepository.updateText(id: id, newText: newText)
    }
    
    public func searchSessionsByTranscript(query: String) async throws -> Set<UUID> {
        try await transcriptRepository.searchSessionsByTranscript(query: query)
    }
    
    public func isSessionTranscriptionComplete(sessionId: UUID) async throws -> Bool {
        try await transcriptRepository.isSessionTranscriptionComplete(sessionId: sessionId)
    }
    
    public func getTranscriptSegments(from startDate: Date, to endDate: Date) async throws -> [TranscriptSegment] {
        try await transcriptRepository.getSegments(from: startDate, to: endDate)
    }
    
    public func fetchSessionWordCount(sessionId: UUID) async throws -> Int {
        try await transcriptRepository.fetchSessionWordCount(sessionId: sessionId)
    }
    
    public func fetchTranscriptText(startDate: Date, endDate: Date) async throws -> [String] {
        try await sessionRepository.fetchTranscriptText(startDate: startDate, endDate: endDate)
    }
    
    public func fetchSessionSentiment(sessionId: UUID) async throws -> Double? {
        try await transcriptRepository.fetchSessionSentiment(sessionId: sessionId)
    }
    
    public func fetchDailySentiment(from startDate: Date, to endDate: Date) async throws -> [(date: Date, sentiment: Double)] {
        try await transcriptRepository.fetchDailySentiment(from: startDate, to: endDate)
    }
    
    public func fetchLanguageDistribution() async throws -> [(language: String, wordCount: Int)] {
        try await transcriptRepository.fetchLanguageDistribution()
    }
    
    public func fetchSessionLanguage(sessionId: UUID) async throws -> String? {
        try await transcriptRepository.fetchSessionLanguage(sessionId: sessionId)
    }
    
    // MARK: - Summary CRUD
    
    public func insertSummary(_ summary: Summary) async throws {
        try await summaryRepository.insert(summary)
    }
    
    public func fetchSummary(id: UUID) async throws -> Summary? {
        try await summaryRepository.fetch(id: id)
    }
    
    public func fetchSummaries(periodType: PeriodType? = nil, limit: Int = 100) async throws -> [Summary] {
        try await summaryRepository.fetchSummaries(periodType: periodType, limit: limit)
    }
    
    public func fetchAllSummaries() async throws -> [Summary] {
        try await summaryRepository.fetchAll()
    }
    
    public func fetchSummaryForSession(sessionId: UUID) async throws -> Summary? {
        try await summaryRepository.fetchForSession(sessionId: sessionId)
    }
    
    public func fetchSessionSummariesInDateRange(from startDate: Date, to endDate: Date) async throws -> [Summary] {
        try await summaryRepository.fetchSessionSummariesInDateRange(from: startDate, to: endDate)
    }
    
    public func fetchPeriodSummary(type: PeriodType, date: Date) async throws -> Summary? {
        try await summaryRepository.fetchPeriodSummary(type: type, date: date)
    }
    
    public func upsertPeriodSummary(
        type: PeriodType,
        text: String,
        start: Date,
        end: Date,
        topicsJSON: String? = nil,
        entitiesJSON: String? = nil,
        engineTier: String? = nil,
        sourceIds: String? = nil,
        inputHash: String? = nil
    ) async throws {
        try await summaryRepository.upsertPeriodSummary(
            type: type,
            text: text,
            start: start,
            end: end,
            topicsJSON: topicsJSON,
            entitiesJSON: entitiesJSON,
            engineTier: engineTier,
            sourceIds: sourceIds,
            inputHash: inputHash
        )
    }
    
    public func fetchDailySummaries(from startDate: Date, to endDate: Date) async throws -> [Summary] {
        try await summaryRepository.fetchDailySummaries(from: startDate, to: endDate)
    }
    
    public func fetchWeeklySummaries(from startDate: Date, to endDate: Date) async throws -> [Summary] {
        try await summaryRepository.fetchWeeklySummaries(from: startDate, to: endDate)
    }
    
    public func fetchMonthlySummaries(from startDate: Date, to endDate: Date) async throws -> [Summary] {
        try await summaryRepository.fetchMonthlySummaries(from: startDate, to: endDate)
    }
    
    public func deleteSummary(id: UUID) async throws {
        try await summaryRepository.delete(id: id)
    }
    
    // MARK: - InsightsRollup CRUD
    
    public func insertRollup(_ rollup: InsightsRollup) async throws {
        try await insightsRepository.insert(rollup)
    }
    
    public func fetchRollup(id: UUID) async throws -> InsightsRollup? {
        try await insightsRepository.fetch(id: id)
    }
    
    public func fetchRollups(bucketType: PeriodType? = nil, limit: Int = 100) async throws -> [InsightsRollup] {
        try await insightsRepository.fetchRollups(bucketType: bucketType, limit: limit)
    }
    
    public func fetchRollup(bucketType: PeriodType, bucketStart: Date) async throws -> InsightsRollup? {
        try await insightsRepository.fetchRollup(bucketType: bucketType, bucketStart: bucketStart)
    }
    
    public func deleteRollup(id: UUID) async throws {
        try await insightsRepository.delete(id: id)
    }
    
    public func deleteAllInsightRollups() async throws {
        try await insightsRepository.deleteAll()
    }
    
    // MARK: - ControlEvent CRUD
    
    public func insertEvent(_ event: ControlEvent) async throws {
        try await controlEventRepository.insert(event)
    }
    
    public func fetchEvent(id: UUID) async throws -> ControlEvent? {
        try await controlEventRepository.fetch(id: id)
    }
    
    public func fetchEvents(limit: Int = 100) async throws -> [ControlEvent] {
        try await controlEventRepository.fetchEvents(limit: limit)
    }
    
    public func deleteEvent(id: UUID) async throws {
        try await controlEventRepository.delete(id: id)
    }
    
    public func deleteAllControlEvents() async throws {
        try await controlEventRepository.deleteAll()
    }
}
