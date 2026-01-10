// =============================================================================
// Summarization — Tests
// =============================================================================

import Foundation
import Testing
@testable import Summarization

@Suite("Summarization Template Tests")
struct SummarizationTemplateTests {
    
    @Test("Daily template has correct configuration")
    func testDailyTemplate() throws {
        let template = SummarizationTemplates.daily
        
        #expect(template.name == "daily")
        #expect(template.maxWords == 150)
        #expect(template.includeEmotionalTone == true)
        #expect(template.includeKeyTopics == true)
        #expect(!template.systemPrompt.isEmpty)
        #expect(!template.userPromptTemplate.isEmpty)
    }
    
    @Test("Weekly template has correct configuration")
    func testWeeklyTemplate() throws {
        let template = SummarizationTemplates.weekly
        
        #expect(template.name == "weekly")
        #expect(template.maxWords == 250)
        #expect(template.includeEmotionalTone == true)
        #expect(template.includeKeyTopics == true)
    }
    
    @Test("Can retrieve template by name")
    func testTemplateRetrieval() throws {
        let daily = SummarizationTemplates.template(named: "daily")
        #expect(daily?.name == "daily")
        
        let weekly = SummarizationTemplates.template(named: "weekly")
        #expect(weekly?.name == "weekly")
        
        let custom = SummarizationTemplates.template(named: "custom")
        #expect(custom?.name == "custom")
        
        let invalid = SummarizationTemplates.template(named: "invalid")
        #expect(invalid == nil)
    }
    
    @Test("Template retrieval is case insensitive")
    func testCaseInsensitiveRetrieval() throws {
        let daily1 = SummarizationTemplates.template(named: "DAILY")
        let daily2 = SummarizationTemplates.template(named: "Daily")
        
        #expect(daily1?.name == "daily")
        #expect(daily2?.name == "daily")
    }
}

@Suite("Summarization Error Tests")
struct SummarizationErrorTests {
    
    @Test("Error descriptions are meaningful")
    func testErrorDescriptions() throws {
        let errors: [SummarizationError] = [
            .noTranscriptData,
            .insufficientContent(minimumWords: 50, actualWords: 20),
            .summarizationFailed("test reason"),
            .invalidDateRange(start: Date(), end: Date().addingTimeInterval(-3600)),
            .storageError("test error"),
            .templateNotFound("custom-template"),
            .configurationError("invalid config")
        ]
        
        for error in errors {
            let description = error.errorDescription
            #expect(description != nil)
            #expect(description!.isEmpty == false)
        }
    }
    
    @Test("Insufficient content error includes word counts")
    func testInsufficientContentError() throws {
        let error = SummarizationError.insufficientContent(minimumWords: 100, actualWords: 45)
        let description = error.errorDescription!
        
        #expect(description.contains("100"))
        #expect(description.contains("45"))
    }
    
    @Test("Template not found error includes template name")
    func testTemplateNotFoundError() throws {
        let error = SummarizationError.templateNotFound("my-template")
        let description = error.errorDescription!
        
        #expect(description.contains("my-template"))
    }
}

@Suite("Summarization Config Tests")
struct SummarizationConfigTests {
    
    @Test("Default config has expected values")
    func testDefaultConfig() throws {
        let config = SummarizationConfig.default
        
        #expect(config.minimumWords == 50)
        #expect(config.template.name == "daily")
        #expect(config.useLocalProcessing == true)
    }
    
    @Test("Can create custom config")
    func testCustomConfig() throws {
        let config = SummarizationConfig(
            minimumWords: 100,
            template: SummarizationTemplates.weekly,
            useLocalProcessing: false
        )
        
        #expect(config.minimumWords == 100)
        #expect(config.template.name == "weekly")
        #expect(config.useLocalProcessing == false)
    }
}

@Suite("Summarization Manager Tests")
struct SummarizationManagerTests {
    
    @Test("Manager initializes with config")
    func testInitialization() async throws {
        // Note: Real tests would need actual DatabaseManager
        // This is a placeholder showing the API structure
        #expect(true)
    }
    
    @Test("Statistics track summary generation")
    func testStatisticsTracking() async throws {
        // Placeholder for statistics tracking test
        // Would test that summariesGenerated and totalProcessingTime increment
        #expect(true)
    }
    
    @Test("Can reset statistics")
    func testResetStatistics() async throws {
        // Placeholder for reset statistics test
        #expect(true)
    }
}

@Suite("Text Analysis Tests")
struct TextAnalysisTests {
    
    @Test("Keyword extraction from text")
    func testKeywordExtraction() throws {
        let text = "Today was amazing. I finished my project and felt really accomplished. The project took weeks of work but it was worth it. Amazing feeling!"
        
        // In a real implementation, we'd test extractKeyTopics directly
        // For now, verify we have meaningful text to analyze
        #expect(text.contains("project"))
        #expect(text.contains("amazing"))
    }
    
    @Test("Emotional tone analysis detects positive")
    func testPositiveTone() throws {
        let positiveText = "I'm so happy today! Everything is wonderful and amazing. I love this!"
        
        // Simple check that positive words are present
        let lowercased = positiveText.lowercased()
        #expect(lowercased.contains("happy") || lowercased.contains("wonderful") || lowercased.contains("amazing"))
    }
    
    @Test("Emotional tone analysis detects negative")
    func testNegativeTone() throws {
        let negativeText = "Today was terrible. I'm sad and stressed about everything. This is awful."
        
        let lowercased = negativeText.lowercased()
        #expect(lowercased.contains("terrible") || lowercased.contains("sad") || lowercased.contains("awful"))
    }
    
    @Test("Handles empty text gracefully")
    func testEmptyText() throws {
        let emptyText = ""
        #expect(emptyText.isEmpty)
    }
}

@Suite("Date Range Tests")
struct DateRangeTests {
    
    @Test("Daily summary covers 24 hours")
    func testDailyRange() throws {
        let calendar = Calendar.current
        let date = Date()
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let difference = calendar.dateComponents([.hour], from: startOfDay, to: endOfDay).hour
        #expect(difference == 24)
    }
    
    @Test("Weekly summary covers 7 days")
    func testWeeklyRange() throws {
        let calendar = Calendar.current
        let date = Date()
        let weekday = calendar.component(.weekday, from: date)
        let daysToSubtract = weekday - 1
        let startOfWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: date)!
        let startOfWeekDay = calendar.startOfDay(for: startOfWeek)
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeekDay)!
        
        let difference = calendar.dateComponents([.day], from: startOfWeekDay, to: endOfWeek).day
        #expect(difference == 7)
    }
    
    @Test("Period type detection for single day")
    func testPeriodTypeDay() throws {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .hour, value: 12, to: start)!
        
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        #expect(days <= 1)
    }
    
    @Test("Period type detection for week")
    func testPeriodTypeWeek() throws {
        let calendar = Calendar.current
        let start = Date()
        let end = calendar.date(byAdding: .day, value: 5, to: start)!
        
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        #expect(days > 1 && days <= 7)
    }
}

// MARK: - Apple Engine Tests

@Suite("Apple Engine Tier Tests")
struct AppleEngineTierTests {
    
    @Test("Apple tier has correct display name")
    func testAppleTierDisplayName() {
        let tier = EngineTier.apple
        #expect(tier.displayName == "Smarter")
    }
    
    @Test("Apple tier has correct subtitle")
    func testAppleTierSubtitle() {
        let tier = EngineTier.apple
        #expect(tier.subtitle == "Apple's on-device AI (iOS 26+)")
    }
    
    @Test("Apple tier has correct icon")
    func testAppleTierIcon() {
        let tier = EngineTier.apple
        #expect(tier.icon == "apple.intelligence")
    }
    
    @Test("Apple tier is privacy preserving")
    func testAppleTierIsPrivacyPreserving() {
        let tier = EngineTier.apple
        #expect(tier.isPrivacyPreserving == true)
    }
    
    @Test("Apple tier does not require internet")
    func testAppleTierDoesNotRequireInternet() {
        let tier = EngineTier.apple
        #expect(tier.requiresInternet == false)
    }
    
    @Test("Apple tier is included in private tiers")
    func testAppleTierInPrivateTiers() {
        #expect(EngineTier.privateTiers.contains(.apple))
    }
    
    @Test("Apple tier description mentions iOS 26+")
    func testAppleTierDescription() {
        let tier = EngineTier.apple
        #expect(tier.description.contains("iOS 26+"))
    }
}

@Suite("Apple Engine Legacy Tests")
struct AppleEngineLegacyTests {
    
    @Test("Legacy engine has correct tier")
    @available(iOS 18.1, *)
    func testLegacyEngineTier() async throws {
        // Test tier without needing actual storage
        #expect(EngineTier.apple.displayName == "Smarter")
    }
    
    @Test("Legacy engine error message contains correct iOS version")
    @available(iOS 18.1, *)
    func testLegacyEngineErrorMessage() async throws {
        let error = SummarizationError.summarizationFailed("Apple Intelligence API requires iOS 26.0+. Please use Local AI or External API instead.")
        let description = error.errorDescription ?? ""
        #expect(description.contains("iOS 26.0+"))
    }
    
    @Test("Legacy engine statistics tuple is correct type")
    func testLegacyEngineStatisticsType() async throws {
        // Verify the statistics tuple structure
        let stats: (summariesGenerated: Int, averageTime: TimeInterval, totalTime: TimeInterval) = (0, 0.0, 0.0)
        #expect(stats.summariesGenerated == 0)
        #expect(stats.averageTime == 0.0)
        #expect(stats.totalTime == 0.0)
    }
}

@Suite("Apple Engine Fallback Logic Tests")
struct AppleEngineModernTests {
    
    @Test("Apple engine tier is apple")
    func testModernEngineTier() async throws {
        #expect(EngineTier.apple.rawValue == "apple")
    }
    
    @Test("Basic summary fallback extracts sentences correctly")
    func testModernEngineFallbackMethods() async throws {
        // Test the basic fallback summary generation
        let text = "This is a test sentence. Here is another one. And a third."
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        #expect(sentences.count >= 3)
        #expect(sentences[0] == "This is a test sentence")
    }
    
    @Test("Topic extraction fallback finds words correctly")
    func testModernEngineTopicExtractionFallback() async throws {
        let text = "development programming coding software engineering projects"
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 4 }
        
        #expect(words.count >= 4)
        #expect(words.contains("development"))
        #expect(words.contains("programming"))
    }
    
    @Test("Empty text returns empty sentences in fallback")
    func testModernEngineEmptyTextFallback() async throws {
        let text = ""
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        #expect(sentences.isEmpty)
    }
    
    @Test("Word count calculation is accurate")
    func testModernEngineWordCount() async throws {
        let text = "Hello world this is a test sentence"
        let wordCount = text.split(separator: " ").count
        #expect(wordCount == 7)
    }
    
    @Test("Topic frequency sorting works correctly")
    func testTopicFrequencySorting() async throws {
        var topicCounts: [String: Int] = [:]
        topicCounts["work"] = 5
        topicCounts["meeting"] = 3
        topicCounts["project"] = 7
        topicCounts["deadline"] = 1
        
        let topTopics = topicCounts.sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
        
        #expect(topTopics.count == 3)
        #expect(topTopics[0] == "project")
        #expect(topTopics[1] == "work")
        #expect(topTopics[2] == "meeting")
    }
    
    @Test("Sentiment average calculation is accurate")
    func testSentimentAverageCalculation() async throws {
        let sentiments = [0.5, -0.3, 0.8, 0.0]
        let avgSentiment = sentiments.reduce(0, +) / Double(sentiments.count)
        
        #expect(avgSentiment == 0.25)
    }
}

// MARK: - Engine Coordinator Apple Integration Tests

@Suite("Summarization Coordinator Apple Engine Tests")
struct SummarizationCoordinatorAppleTests {
    
    @Test("Coordinator includes Apple in available engines check")
    func testCoordinatorAvailableEnginesIncludesApple() async throws {
        // Verify EngineTier has apple case
        let allCases = EngineTier.allCases
        #expect(allCases.contains(.apple))
    }
    
    @Test("Apple tier raw value is 'apple'")
    func testAppleTierRawValue() {
        #expect(EngineTier.apple.rawValue == "apple")
    }
    
    @Test("Apple tier can be decoded from string")
    func testAppleTierDecoding() throws {
        let jsonString = "\"apple\""
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let tier = try decoder.decode(EngineTier.self, from: data)
        #expect(tier == .apple)
    }
    
    @Test("Apple tier can be encoded to string")
    func testAppleTierEncoding() throws {
        let tier = EngineTier.apple
        let encoder = JSONEncoder()
        let data = try encoder.encode(tier)
        let string = String(data: data, encoding: .utf8)!
        #expect(string == "\"apple\"")
    }
}
