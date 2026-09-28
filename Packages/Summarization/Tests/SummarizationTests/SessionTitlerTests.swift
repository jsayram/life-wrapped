// =============================================================================
// Summarization — recording titles
// =============================================================================

import Foundation
import Testing
@testable import Summarization

@Suite("Recording titles")
struct SessionTitlerTests {

    @Test("Model titles are tidied and bad ones rejected")
    func clean() {
        #expect(SessionTitler.clean("\"Test harness for Piccolo Xpress.\"") == "Test harness for Piccolo Xpress")
        #expect(SessionTitler.clean("  morning run by the river ") == "Morning run by the river")
        #expect(SessionTitler.clean("<title for 1>") == nil)
        #expect(SessionTitler.clean("Untitled recording") == nil)
        #expect(SessionTitler.clean("The user talks about work") == nil)
        #expect(SessionTitler.clean("") == nil)
        #expect(SessionTitler.clean("one two three four five six seven eight nine")?.split(separator: " ").count == 7)
    }

    @Test("Without a model, the title comes from the summary's first words")
    func fallback() {
        #expect(SessionTitler.fallback(summary: "I created a test harness for the Piccolo Xpress. Then lunch.") == "Created a test harness for the")
        #expect(SessionTitler.fallback(summary: "Long day.", keyPoints: ["Fix the login bug"]) == "Fix the login bug")
        #expect(SessionTitler.fallback(summary: "") == nil)
    }

    @Test("Batch titles map back to their notes, with unusable ones left for the fallback")
    func batch() async {
        let generator = ScriptedGenerator { _ in #"{"titles":["Launch planning","<title for 2>"]}"# }
        let titles = await SessionTitler.titles(for: ["Planned the launch.", "Ran by the river.", "Third note."], generator: generator)
        #expect(titles == ["Launch planning", nil, nil])
    }

    @Test("A failed request gives no titles rather than failing")
    func failedRequest() async {
        let generator = ScriptedGenerator { _ in "Sorry" }
        let titles = await SessionTitler.titles(for: ["A", "B"], generator: generator)
        #expect(titles == [nil, nil])
    }
}
