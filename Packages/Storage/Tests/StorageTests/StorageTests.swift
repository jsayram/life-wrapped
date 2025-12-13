// =============================================================================
// Storage — Tests
// =============================================================================

import Foundation
import Testing
@testable import Storage
@testable import SharedModels

@Suite("Database Manager Tests")
struct DatabaseManagerTests {
    
    @Test("Database initializes successfully")
    func testDatabaseInit() async throws {
        let manager = try await createTestDatabase()
        
        // Verify we can perform basic operations
        let chunks = try await manager.fetchAllAudioChunks()
        #expect(chunks.isEmpty)
        
        await manager.close()
    }
    
    @Test("AudioChunk CRUD operations")
    func testAudioChunkCRUD() async throws {
        let manager = try await createTestDatabase()
        
        // Create
        let chunk = AudioChunk(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            startTime: Date(),
            endTime: Date().addingTimeInterval(60),
            format: .m4a,
            sampleRate: 44100
        )
        
        try await manager.insertAudioChunk(chunk)
        
        // Read
        let fetched = try await manager.fetchAudioChunk(id: chunk.id)
        #expect(fetched != nil)
        #expect(fetched?.id == chunk.id)
        #expect(fetched?.fileURL == chunk.fileURL)
        #expect(fetched?.format == .m4a)
        #expect(fetched?.sampleRate == 44100)
        
        // Read all
        let all = try await manager.fetchAllAudioChunks()
        #expect(all.count == 1)
        #expect(all[0].id == chunk.id)
        
        // Delete
        try await manager.deleteAudioChunk(id: chunk.id)
        let afterDelete = try await manager.fetchAudioChunk(id: chunk.id)
        #expect(afterDelete == nil)
        
        await manager.close()
    }
    
    @Test("TranscriptSegment CRUD operations")
    func testTranscriptSegmentCRUD() async throws {
        let manager = try await createTestDatabase()
        
        // Create parent audio chunk first
        let chunk = AudioChunk(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            startTime: Date(),
            endTime: Date().addingTimeInterval(60),
            format: .m4a,
            sampleRate: 44100
        )
        try await manager.insertAudioChunk(chunk)
        
        // Create
        let segment = TranscriptSegment(
            audioChunkID: chunk.id,
            startTime: 0.0,
            endTime: 5.0,
            text: "Hello world",
            confidence: 0.95,
            languageCode: "en-US"
        )
        
        try await manager.insertTranscriptSegment(segment)
        
        // Read
        let fetched = try await manager.fetchTranscriptSegment(id: segment.id)
        #expect(fetched != nil)
        #expect(fetched?.text == "Hello world")
        #expect(fetched?.confidence == 0.95)
        
        // Read by audio chunk
        let segments = try await manager.fetchTranscriptSegments(audioChunkID: chunk.id)
        #expect(segments.count == 1)
        #expect(segments[0].id == segment.id)
        
        // Delete
        try await manager.deleteTranscriptSegment(id: segment.id)
        let afterDelete = try await manager.fetchTranscriptSegment(id: segment.id)
        #expect(afterDelete == nil)
        
        await manager.close()
    }
    
    @Test("Summary CRUD operations")
    func testSummaryCRUD() async throws {
        let manager = try await createTestDatabase()
        
        // Create
        let now = Date()
        let summary = Summary(
            periodType: .day,
            periodStart: now,
            periodEnd: now.addingTimeInterval(86400),
            text: "Today was productive"
        )
        
        try await manager.insertSummary(summary)
        
        // Read
        let fetched = try await manager.fetchSummary(id: summary.id)
        #expect(fetched != nil)
        #expect(fetched?.text == "Today was productive")
        #expect(fetched?.periodType == .day)
        
        // Read all
        let all = try await manager.fetchSummaries()
        #expect(all.count == 1)
        
        // Read filtered by period type
        let dailySummaries = try await manager.fetchSummaries(periodType: .day)
        #expect(dailySummaries.count == 1)
        
        let weeklySummaries = try await manager.fetchSummaries(periodType: .week)
        #expect(weeklySummaries.isEmpty)
        
        // Delete
        try await manager.deleteSummary(id: summary.id)
        let afterDelete = try await manager.fetchSummary(id: summary.id)
        #expect(afterDelete == nil)
        
        await manager.close()
    }
    
    @Test("InsightsRollup CRUD operations")
    func testInsightsRollupCRUD() async throws {
        let manager = try await createTestDatabase()
        
        // Create
        let now = Date()
        let rollup = InsightsRollup(
            bucketType: .hour,
            bucketStart: now,
            bucketEnd: now.addingTimeInterval(3600),
            wordCount: 500,
            speakingSeconds: 180.5,
            segmentCount: 25
        )
        
        try await manager.insertRollup(rollup)
        
        // Read
        let fetched = try await manager.fetchRollup(id: rollup.id)
        #expect(fetched != nil)
        #expect(fetched?.wordCount == 500)
        #expect(fetched?.speakingSeconds == 180.5)
        #expect(fetched?.segmentCount == 25)
        
        // Read all
        let all = try await manager.fetchRollups()
        #expect(all.count == 1)
        
        // Read filtered by bucket type
        let hourlyRollups = try await manager.fetchRollups(bucketType: .hour)
        #expect(hourlyRollups.count == 1)
        
        // Delete
        try await manager.deleteRollup(id: rollup.id)
        let afterDelete = try await manager.fetchRollup(id: rollup.id)
        #expect(afterDelete == nil)
        
        await manager.close()
    }
    
    @Test("ControlEvent CRUD operations")
    func testControlEventCRUD() async throws {
        let manager = try await createTestDatabase()
        
        // Create
        let event = ControlEvent(
            timestamp: Date(),
            source: .phone,
            type: .startListening,
            payloadJSON: "{\"reason\":\"manual\"}"
        )
        
        try await manager.insertEvent(event)
        
        // Read
        let fetched = try await manager.fetchEvent(id: event.id)
        #expect(fetched != nil)
        #expect(fetched?.source == .phone)
        #expect(fetched?.type == .startListening)
        #expect(fetched?.payloadJSON == "{\"reason\":\"manual\"}")
        
        // Read all
        let all = try await manager.fetchEvents()
        #expect(all.count == 1)
        
        // Delete
        try await manager.deleteEvent(id: event.id)
        let afterDelete = try await manager.fetchEvent(id: event.id)
        #expect(afterDelete == nil)
        
        await manager.close()
    }
    
    @Test("Foreign key cascade delete")
    func testForeignKeyCascade() async throws {
        let manager = try await createTestDatabase()
        
        // Create audio chunk
        let chunk = AudioChunk(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            startTime: Date(),
            endTime: Date().addingTimeInterval(60),
            format: .m4a,
            sampleRate: 44100
        )
        try await manager.insertAudioChunk(chunk)
        
        // Create transcript segments
        let segment1 = TranscriptSegment(
            audioChunkID: chunk.id,
            startTime: 0.0,
            endTime: 2.0,
            text: "First segment",
            confidence: 0.9,
            languageCode: "en-US"
        )
        let segment2 = TranscriptSegment(
            audioChunkID: chunk.id,
            startTime: 2.0,
            endTime: 4.0,
            text: "Second segment",
            confidence: 0.85,
            languageCode: "en-US"
        )
        
        try await manager.insertTranscriptSegment(segment1)
        try await manager.insertTranscriptSegment(segment2)
        
        // Verify segments exist
        let segments = try await manager.fetchTranscriptSegments(audioChunkID: chunk.id)
        #expect(segments.count == 2)
        
        // Delete parent audio chunk
        try await manager.deleteAudioChunk(id: chunk.id)
        
        // Verify segments were cascade deleted
        let afterDelete1 = try await manager.fetchTranscriptSegment(id: segment1.id)
        let afterDelete2 = try await manager.fetchTranscriptSegment(id: segment2.id)
        #expect(afterDelete1 == nil)
        #expect(afterDelete2 == nil)
        
        await manager.close()
    }
    
    @Test("Multiple inserts and query ordering")
    func testMultipleInsertsAndOrdering() async throws {
        let manager = try await createTestDatabase()
        
        // Create multiple audio chunks with different timestamps
        let baseDate = Date(timeIntervalSince1970: 1000000)
        
        let chunk1 = AudioChunk(
            fileURL: URL(fileURLWithPath: "/tmp/test1.m4a"),
            startTime: baseDate,
            endTime: baseDate.addingTimeInterval(60),
            format: .m4a,
            sampleRate: 44100
        )
        
        let chunk2 = AudioChunk(
            fileURL: URL(fileURLWithPath: "/tmp/test2.m4a"),
            startTime: baseDate.addingTimeInterval(120),
            endTime: baseDate.addingTimeInterval(180),
            format: .m4a,
            sampleRate: 44100
        )
        
        let chunk3 = AudioChunk(
            fileURL: URL(fileURLWithPath: "/tmp/test3.m4a"),
            startTime: baseDate.addingTimeInterval(240),
            endTime: baseDate.addingTimeInterval(300),
            format: .m4a,
            sampleRate: 44100
        )
        
        try await manager.insertAudioChunk(chunk1)
        try await manager.insertAudioChunk(chunk2)
        try await manager.insertAudioChunk(chunk3)
        
        // Fetch all - should be in descending order by start_time
        let all = try await manager.fetchAllAudioChunks()
        #expect(all.count == 3)
        #expect(all[0].id == chunk3.id) // Most recent first
        #expect(all[1].id == chunk2.id)
        #expect(all[2].id == chunk1.id)
        
        // Test limit
        let limited = try await manager.fetchAllAudioChunks(limit: 2)
        #expect(limited.count == 2)
        #expect(limited[0].id == chunk3.id)
        #expect(limited[1].id == chunk2.id)
        
        // Test offset
        let offset = try await manager.fetchAllAudioChunks(limit: 2, offset: 1)
        #expect(offset.count == 2)
        #expect(offset[0].id == chunk2.id)
        #expect(offset[1].id == chunk1.id)
        
        await manager.close()
    }
    
    @Test("Concurrent operations")
    func testConcurrentOperations() async throws {
        let manager = try await createTestDatabase()
        
        // Create 10 audio chunks concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let chunk = AudioChunk(
                        fileURL: URL(fileURLWithPath: "/tmp/test\(i).m4a"),
                        startTime: Date(),
                        endTime: Date().addingTimeInterval(60),
                        format: .m4a,
                        sampleRate: 44100
                    )
                    try? await manager.insertAudioChunk(chunk)
                }
            }
        }
        
        // Verify all were inserted
        let all = try await manager.fetchAllAudioChunks()
        #expect(all.count == 10)
        
        await manager.close()
    }
    
    @Test("Optional fields handling")
    func testOptionalFields() async throws {
        let manager = try await createTestDatabase()
        
        // Create audio chunk
        let chunk = AudioChunk(
            fileURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            startTime: Date(),
            endTime: Date().addingTimeInterval(60),
            format: .m4a,
            sampleRate: 44100
        )
        try await manager.insertAudioChunk(chunk)
        
        // Create segment with optional fields
        let segmentWithOptionals = TranscriptSegment(
            audioChunkID: chunk.id,
            startTime: 0.0,
            endTime: 5.0,
            text: "Test with optionals",
            confidence: 0.9,
            languageCode: "en-US",
            speakerLabel: "Speaker1",
            entitiesJSON: "{\"entities\":[\"test\"]}"
        )
        
        try await manager.insertTranscriptSegment(segmentWithOptionals)
        
        let fetched = try await manager.fetchTranscriptSegment(id: segmentWithOptionals.id)
        #expect(fetched?.speakerLabel == "Speaker1")
        #expect(fetched?.entitiesJSON == "{\"entities\":[\"test\"]}")
        
        // Create segment without optional fields
        let segmentWithoutOptionals = TranscriptSegment(
            audioChunkID: chunk.id,
            startTime: 5.0,
            endTime: 10.0,
            text: "Test without optionals",
            confidence: 0.85,
            languageCode: "en-US"
        )
        
        try await manager.insertTranscriptSegment(segmentWithoutOptionals)
        
        let fetchedNoOptionals = try await manager.fetchTranscriptSegment(id: segmentWithoutOptionals.id)
        #expect(fetchedNoOptionals?.speakerLabel == nil)
        #expect(fetchedNoOptionals?.entitiesJSON == nil)
        
        await manager.close()
    }
}

// MARK: - Test Helpers

/// Create a test database in a temporary location
/// Each test gets its own unique database to avoid interference
private func createTestDatabase() async throws -> DatabaseManager {
    // Use a unique container identifier for each test to avoid database sharing
    let uniqueID = UUID().uuidString
    let containerID = "group.com.jsayram.lifewrapped.test.\(uniqueID)"
    
    return try await DatabaseManager(containerIdentifier: containerID)
}
