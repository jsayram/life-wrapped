// =============================================================================
// PDFExportPreviewTests — Renders sample PDFs in the graphite design
// =============================================================================
// Writes preview files to TestResults/pdf-preview (gitignored) so the layout
// can be reviewed by eye. Also checks that both exports produce valid PDFs.
// =============================================================================

#if canImport(UIKit)
import Foundation
import PDFKit
import Testing
@testable import Storage
@testable import SharedModels

@Suite("PDF export preview")
struct PDFExportPreviewTests {

    @Test("Standard and Year Wrap PDFs render")
    func renderPreviews() async throws {
        let manager = try await DatabaseManager(containerIdentifier: "group.com.jsayram.lifewrapped.test.\(UUID().uuidString)")
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!

        // Recordings for the stats page
        for (index, words) in ["This morning I met Sarah downtown to plan the product launch.",
                               "Went for an evening run by the river, felt lighter after.",
                               "Planted tomatoes and basil with Dad, planning a greenhouse."].enumerated() {
            let start = Date().addingTimeInterval(TimeInterval(-3600 * (index + 1)))
            let chunk = AudioChunk(fileURL: URL(fileURLWithPath: "/tmp/preview\(index).m4a"), startTime: start, endTime: start.addingTimeInterval(240), format: .m4a, sampleRate: 44100)
            try await manager.insertAudioChunk(chunk)
            try await manager.insertTranscriptSegment(TranscriptSegment(audioChunkID: chunk.id, startTime: 0, endTime: 240, text: words, confidence: 0.95, languageCode: "en-US"))
        }

        // Summaries for the standard export
        let day = calendar.startOfDay(for: Date())
        try await manager.insertSummary(Summary(periodType: .day, periodStart: day, periodEnd: day.addingTimeInterval(86400), text: "Met Sarah downtown to plan the product launch. The beta ships on the fifteenth, and Sarah will send the press email. A little stressed about the deadline, but encouraged by early feedback on the new onboarding flow."))
        try await manager.insertSummary(Summary(periodType: .week, periodStart: day.addingTimeInterval(-86400 * 6), periodEnd: day.addingTimeInterval(86400), text: "A launch-focused week. Most entries were about getting the beta ready, balanced by runs and a slow afternoon in the garden. The mood lifted toward the weekend."))
        try await manager.insertSummary(Summary(periodType: .month, periodStart: day.addingTimeInterval(-86400 * 20), periodEnd: day.addingTimeInterval(86400), text: String(repeating: "A long month summary that should wrap across several lines and pages to test text flow in the export. ", count: 60)))

        // Year Wrap
        let wrapJSON = """
        {"year_title": "A year of building and slowing down",
         "year_summary": "You shipped a product, ran more than ever, and kept coming back to the garden. Work was intense in the spring and calmer by the fall.",
         "major_arcs": [{"text": "Launched the beta after four months of work.", "category": "work"}, {"text": "Built a steady running habit.", "category": "personal"}],
         "biggest_wins": [{"text": "Ran a first half marathon in October.", "category": "personal"}, {"text": "Beta launched on time.", "category": "work"}],
         "biggest_losses": [], "biggest_challenges": [{"text": "Balancing launch pressure with rest.", "category": "both"}],
         "finished_projects": [{"text": "Greenhouse with Dad.", "category": "personal"}], "unfinished_projects": [],
         "top_worked_on_topics": [{"text": "Onboarding", "category": "work"}, {"text": "Pricing", "category": "work"}],
         "top_talked_about_things": [{"text": "Running", "category": "personal"}],
         "valuable_actions_taken": [{"text": "Blocked focus time every morning.", "category": "work"}],
         "opportunities_missed": [{"text": "Travel plans that kept slipping.", "category": "personal"}],
         "people_mentioned": [{"name": "Sarah", "relationship": "Coworker"}, {"name": "Dad", "relationship": "Family"}],
         "places_visited": [{"name": "Downtown", "frequency": "Weekly"}, {"name": "The river trail", "frequency": "Most mornings"}]}
        """
        try await manager.insertSummary(Summary(periodType: .yearWrap, periodStart: startOfYear, periodEnd: calendar.date(byAdding: .year, value: 1, to: startOfYear)!, text: wrapJSON))

        let exporter = DataExporter(databaseManager: manager)
        let standard = try await exporter.exportToPDF(year: nil)
        let wrap = try await exporter.exportToPDF(year: year)

        #expect(PDFDocument(data: standard)?.pageCount ?? 0 >= 1)
        #expect(PDFDocument(data: wrap)?.pageCount ?? 0 >= 2)

        // Save previews next to the repo (ignored by git); skipped quietly if not writable
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let outDir = repoRoot.appendingPathComponent("TestResults/pdf-preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try? standard.write(to: outDir.appendingPathComponent("standard-export.pdf"))
        try? wrap.write(to: outDir.appendingPathComponent("year-wrap.pdf"))
        print("PDF previews: \(outDir.path)")

        await manager.close()
    }
}
#endif
