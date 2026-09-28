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
    
    @Test("Each journal keeps its own period summary, apart from the unscoped one")
    func testJournalSummaries() async throws {
        let manager = try await createTestDatabase()
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start)!
        let middle = start.addingTimeInterval(86_400 * 10)

        try await manager.upsertPeriodSummary(type: .monthDigest, text: "old combined", start: start, end: end)
        try await manager.upsertPeriodSummary(type: .monthDigest, text: "work", start: start, end: end, category: .work)
        try await manager.upsertPeriodSummary(type: .monthDigest, text: "personal", start: start, end: end, category: .personal)
        // Upserting again updates the journal's row instead of adding one
        try await manager.upsertPeriodSummary(type: .monthDigest, text: "work v2", start: start, end: end, category: .work)

        #expect(try await manager.fetchPeriodSummary(type: .monthDigest, date: middle)?.text == "old combined")
        #expect(try await manager.fetchPeriodSummary(type: .monthDigest, date: middle, category: .work)?.text == "work v2")
        #expect(try await manager.fetchPeriodSummary(type: .monthDigest, date: middle, category: .personal)?.text == "personal")
        #expect(try await manager.fetchSummaries(periodType: .monthDigest, from: start, to: end).count == 3)

        await manager.close()
    }
    
    @Test("Recording days: one per local day, all time, however many recordings a day has")
    func testRecordingDays() async throws {
        let manager = try await createTestDatabase()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // 400 recordings on one busy day, plus one recording on each of the 3 days before it
        for dayOffset in 0...3 {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today)!.addingTimeInterval(9 * 3600)
            for index in 0..<(dayOffset == 0 ? 400 : 1) {
                let start = day.addingTimeInterval(Double(index))
                try await manager.insertAudioChunk(AudioChunk(
                    fileURL: URL(fileURLWithPath: "/tmp/\(UUID()).m4a"), startTime: start, endTime: start + 1,
                    format: .m4a, sampleRate: 44100, sessionId: UUID(), chunkIndex: 0))
            }
        }

        let days = try await manager.fetchRecordingDays()
        #expect(days.count == 4)
        #expect(Set(days.map { calendar.startOfDay(for: $0) }).count == 4)

        await manager.close()
    }

    @Test("Change times: content changes and transcript edits are recorded separately")
    func testSessionChangeTimes() async throws {
        let manager = try await createTestDatabase()
        let edited = UUID()
        let untouched = UUID()
        try await manager.upsertSessionMetadata(.init(sessionId: untouched, title: "Old", category: .work))
        let before = Date().addingTimeInterval(-1)

        #expect(try await manager.fetchTranscriptEditedAt(sessionId: edited) == nil)

        // Creates the row when there is none, and keeps the journal and notes of one that exists
        try await manager.markSessionChanged(sessionId: edited, transcript: true)
        #expect(try await manager.fetchTranscriptEditedAt(sessionId: edited) != nil)
        #expect(try await manager.fetchSessionIdsContentChanged(since: before).isEmpty)

        try await manager.updateSessionNotes(sessionId: untouched, notes: "More")
        try await manager.markSessionChanged(sessionId: untouched, content: true)
        #expect(try await manager.fetchSessionIdsContentChanged(since: before) == [untouched])
        #expect(try await manager.fetchSessionIdsContentChanged(since: Date().addingTimeInterval(1)).isEmpty)
        let metadata = try await manager.fetchSessionMetadata(sessionId: untouched)
        #expect(metadata?.category == .work)
        #expect(metadata?.notes == "More")

        await manager.close()
    }

    @Test("A summary's journal survives saving, export and import")
    func testJournalRoundTrip() async throws {
        let manager = try await createTestDatabase()
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let summary = Summary(periodType: .monthDigest, periodStart: start, periodEnd: start.addingTimeInterval(86_400 * 31),
                              text: "{}", category: .work)
        try await manager.insertSummary(summary)
        #expect(try await manager.fetchSummary(id: summary.id)?.category == .work)

        // Export writes it; an older export without the field still decodes
        let encoder = JSONEncoder()
        let exported = try encoder.encode(JSONSummary(from: summary))
        #expect(String(decoding: exported, as: UTF8.self).contains("\"category\":\"work\""))
        let old = #"{"id":"\#(UUID().uuidString)","periodType":"monthDigest","periodStart":0,"periodEnd":10,"text":"{}","createdAt":0}"#
        let decoded = try JSONDecoder().decode(JSONSummary.self, from: Data(old.utf8))
        #expect(decoded.category == nil)

        await manager.close()
    }
    
    @Test("Markdown export lists months with their digest and recordings, not deleted ones")
    func testMarkdownExport() async throws {
        let manager = try await createTestDatabase()
        let calendar = Calendar.current
        let march = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let recordedAt = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 9))!
        let kept = UUID(), deleted = UUID()

        // Only the kept recording still has audio
        try await manager.insertAudioChunk(AudioChunk(fileURL: URL(fileURLWithPath: "/tmp/a.m4a"), startTime: recordedAt,
                                                      endTime: recordedAt.addingTimeInterval(60), format: .m4a, sampleRate: 44100, sessionId: kept))
        try await manager.upsertSessionMetadata(.init(sessionId: kept, title: "Launch plan", category: .work))
        try await manager.insertSummary(Summary(periodType: .session, periodStart: recordedAt, periodEnd: recordedAt.addingTimeInterval(60),
                                                text: "Planned the launch.", sessionId: kept))
        try await manager.insertSummary(Summary(periodType: .session, periodStart: recordedAt, periodEnd: recordedAt.addingTimeInterval(60),
                                                text: "A recording that was deleted.", sessionId: deleted))
        let digest = MonthDigest(monthStart: march, isFinal: true,
                                 stats: DigestStats(sessionCount: 1, totalMinutes: 1, wordCount: 10, activeDays: 1, workCount: 1, personalCount: 0),
                                 headline: "Launch month", narrative: nil, items: [], engineTier: "apple", journal: .work)
        try await manager.upsertPeriodSummary(type: .monthDigest, text: try digest.jsonString(), start: march,
                                              end: calendar.date(byAdding: .month, value: 1, to: march)!, category: .work)

        let markdown = try await DataExporter(databaseManager: manager).exportToMarkdown(year: 2026)
        #expect(markdown.contains("## March 2026"))
        #expect(markdown.contains("Launch month"))
        #expect(markdown.contains("· Work · Launch plan**"))
        #expect(markdown.contains("Planned the launch."))
        #expect(!markdown.contains("deleted"))

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
    
    @Test("Ranged summary fetch is not cut off by the default row limit")
    func testRangedSummaryFetchPastDefaultLimit() async throws {
        let manager = try await createTestDatabase()

        // 150 session summaries, one per day, going back from today
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for dayOffset in 0..<150 {
            let start = calendar.date(byAdding: .day, value: -dayOffset, to: today)!.addingTimeInterval(3600)
            try await manager.insertSummary(Summary(
                periodType: .session,
                periodStart: start,
                periodEnd: start.addingTimeInterval(600),
                text: "Session \(dayOffset)",
                sessionId: UUID()
            ))
        }

        // The unranged fetch only sees the newest 100, so the oldest day is missing
        let limited = try await manager.fetchSummaries(periodType: .session)
        #expect(limited.count == 100)

        let oldestDay = calendar.date(byAdding: .day, value: -149, to: today)!
        let oldestDayEnd = calendar.date(byAdding: .day, value: 1, to: oldestDay)!
        let oldest = try await manager.fetchSummaries(periodType: .session, from: oldestDay, to: oldestDayEnd)
        #expect(oldest.count == 1)
        #expect(oldest.first?.text == "Session 149")

        // A range covering everything returns all rows, oldest first
        let all = try await manager.fetchSummaries(periodType: .session, from: oldestDay, to: today.addingTimeInterval(86400))
        #expect(all.count == 150)
        #expect(all.first?.text == "Session 149")

        // Other period types are excluded
        let days = try await manager.fetchSummaries(periodType: .day, from: oldestDay, to: today.addingTimeInterval(86400))
        #expect(days.isEmpty)

        await manager.close()
    }

    #if canImport(UIKit)
    @Test("PDF export reads Year Wraps whose items link to recordings")
    func exporterReadsLinkedWrap() async throws {
        let manager = try await createTestDatabase()
        let exporter = DataExporter(databaseManager: manager)
        let id = UUID()
        let json = """
        {"year_title":"T","year_summary":"S",
         "biggest_wins":[{"text":"Ran a 10k","category":"personal","session_ids":["\(id.uuidString)"]}],
         "major_arcs":[{"text":"Old style item","category":"work"}],
         "people_mentioned":[{"name":"Sarah","impact":"Mentioned in 2 recordings","session_ids":["\(id.uuidString)"]}],
         "places_visited":[{"name":"Lisbon","frequency":"once"}],
         "stats":{"session_count":3}}
        """
        let wrap = await exporter.parseYearWrapJSON(from: json)
        #expect(wrap?.biggestWins.first?.text == "Ran a 10k")
        #expect(wrap?.biggestWins.first?.sessionIds == [id])
        #expect(wrap?.majorArcs.first?.text == "Old style item")
        #expect(wrap?.peopleMentioned.first?.sessionIds == [id])
        #expect(wrap?.placesVisited.first?.name == "Lisbon")
        await manager.close()
    }
    #endif
    
    @Test("Deleted recordings are told apart from ones that still have audio")
    func existingSessionIds() async throws {
        let manager = try await createTestDatabase()
        let kept = UUID(), deleted = UUID()
        for sessionId in [kept, deleted] {
            try await manager.insertAudioChunk(AudioChunk(fileURL: URL(fileURLWithPath: "/tmp/\(sessionId).m4a"), startTime: Date(), endTime: Date().addingTimeInterval(30), format: .m4a, sampleRate: 44100, sessionId: sessionId))
        }
        try await manager.deleteSession(sessionId: deleted)
        let existing = try await manager.existingSessionIds(among: [kept, deleted, UUID()])
        #expect(existing == [kept])
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

// MARK: - Summary versions

@Suite("Summary versions")
struct SummaryVersionTests {

    private let start = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!
    private var end: Date { start.addingTimeInterval(86_400 * 31) }

    @Test("Replacing a recording's summary keeps the old text, and restoring brings it back")
    func sessionSummaryVersions() async throws {
        let manager = try await createTestDatabase()
        let sessionId = UUID()
        let cloud = Summary(periodType: .session, periodStart: start, periodEnd: start.addingTimeInterval(60),
                            text: "A careful Cloud AI summary.", sessionId: sessionId, engineTier: "external", inputHash: "h1")
        try await manager.replaceSessionSummary(cloud)
        #expect(try await manager.fetchSummaryVersions(for: cloud).isEmpty)

        let basic = Summary(periodType: .session, periodStart: start, periodEnd: start.addingTimeInterval(60),
                            text: "Key sentences.", sessionId: sessionId, engineTier: "basic", inputHash: "h1")
        try await manager.replaceSessionSummary(basic)
        let current = try #require(try await manager.fetchSummaryForSession(sessionId: sessionId))
        #expect(current.text == "Key sentences.")
        let versions = try await manager.fetchSummaryVersions(for: current)
        #expect(versions.count == 1)
        #expect(versions.first?.engineTier == "external")
        #expect(versions.first?.text == "A careful Cloud AI summary.")

        // The same text again is not a new version
        try await manager.replaceSessionSummary(basic)
        #expect(try await manager.fetchSummaryVersions(for: current).count == 1)

        // Restore: Cloud AI is current again and the Key Sentences text is kept in turn
        let restored = try await manager.restoreSummaryVersion(versions[0], replacing: current)
        #expect(restored.engineTier == "external")
        #expect(try await manager.fetchSummaryForSession(sessionId: sessionId)?.text == "A careful Cloud AI summary.")
        let after = try await manager.fetchSummaryVersions(for: restored)
        #expect(after.count == 1)
        #expect(after.first?.engineTier == "basic")

        // Deleting the recording removes its versions
        try await manager.deleteSession(sessionId: sessionId)
        #expect(try await manager.fetchSummaryVersions(for: restored).isEmpty)
        await manager.close()
    }

    @Test("A rewritten month digest keeps its earlier text, at most ten versions")
    func periodSummaryVersions() async throws {
        let manager = try await createTestDatabase()
        for i in 0..<12 {
            try await manager.upsertPeriodSummary(type: .monthDigest, text: "v\(i)", start: start, end: end,
                                                  engineTier: i == 0 ? "external" : "basic", category: .work)
        }
        let current = try #require(try await manager.fetchPeriodSummary(type: .monthDigest, date: start, category: .work))
        #expect(current.text == "v11")
        let versions = try await manager.fetchSummaryVersions(for: current)
        #expect(versions.count == SummaryVersionRepository.keptPerSummary)
        #expect(versions.first?.text == "v10")
        #expect(versions.last?.text == "v1")

        // Deleting the digest row removes its versions too
        try await manager.deleteSummary(id: current.id)
        #expect(try await manager.fetchSummaryVersions(for: current).isEmpty)
        await manager.close()
    }

    @Test("Backups carry engines and versions, and older backups still import")
    func backupRoundTrip() async throws {
        let manager = try await createTestDatabase()
        let sessionId = UUID()
        let first = Summary(periodType: .session, periodStart: start, periodEnd: start.addingTimeInterval(60),
                            text: "First.", sessionId: sessionId, topicsJSON: "[\"launch\"]", engineTier: "external", inputHash: "h1")
        try await manager.replaceSessionSummary(first)
        let second = Summary(periodType: .session, periodStart: start, periodEnd: start.addingTimeInterval(60),
                             text: "Second.", sessionId: sessionId, engineTier: "basic", inputHash: "h1")
        try await manager.replaceSessionSummary(second)

        let data = try await DataExporter(databaseManager: manager).exportToJSON()
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"summaryVersions\""))
        #expect(json.contains("\"engineTier\" : \"basic\""))

        let fresh = try await createTestDatabase()
        let result = try await DataImporter(databaseManager: fresh).importFromJSON(data: data)
        #expect(result.importedSummaries == 1)
        let imported = try #require(try await fresh.fetchSummaryForSession(sessionId: sessionId))
        #expect(imported.engineTier == "basic")
        #expect(imported.inputHash == "h1")
        let versions = try await fresh.fetchSummaryVersions(for: imported)
        #expect(versions.count == 1)
        #expect(versions.first?.topicsJSON == "[\"launch\"]")

        // Importing the same backup again adds nothing
        _ = try await DataImporter(databaseManager: fresh).importFromJSON(data: data)
        #expect(try await fresh.fetchSummaryVersions(for: imported).count == 1)

        // A backup from before 1.3 has no versions and no engine
        let old = """
        {"exportDate":"2026-01-01T00:00:00Z","version":"1.0","audioChunks":[],"summaries":[
        {"id":"\(UUID().uuidString)","periodType":"session","periodStart":"2026-01-01T00:00:00Z","periodEnd":"2026-01-01T00:01:00Z","text":"Old.","createdAt":"2026-01-01T00:00:00Z","sessionId":"\(UUID().uuidString)"}]}
        """
        let older = try await createTestDatabase()
        let oldResult = try await DataImporter(databaseManager: older).importFromJSON(data: Data(old.utf8))
        #expect(oldResult.importedSummaries == 1)
        #expect(oldResult.errors.isEmpty)

        await manager.close(); await fresh.close(); await older.close()
    }
}
