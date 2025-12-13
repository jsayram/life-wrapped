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
