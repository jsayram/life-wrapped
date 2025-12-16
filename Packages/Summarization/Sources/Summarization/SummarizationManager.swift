// =============================================================================
// Summarization — Manager
// =============================================================================

import Foundation
import NaturalLanguage
import SharedModels
import Storage

/// Configuration for summarization operations
public struct SummarizationConfig: Sendable {
    public let minimumWords: Int
    public let template: SummarizationTemplate
    public let useLocalProcessing: Bool
    
    public init(
        minimumWords: Int = 50,
        template: SummarizationTemplate = SummarizationTemplates.daily,
        useLocalProcessing: Bool = true
    ) {
        self.minimumWords = minimumWords
        self.template = template
        self.useLocalProcessing = useLocalProcessing
    }
    
    public static let `default` = SummarizationConfig()
}

/// Actor that manages summarization of transcribed content
/// Currently uses rule-based summarization; can be extended with LLM integration
public actor SummarizationManager {
    
    // MARK: - Properties
    
    private let storage: DatabaseManager
    private let config: SummarizationConfig
    
    // MARK: - Statistics
    
    private(set) var summariesGenerated: Int = 0
    private(set) var totalProcessingTime: TimeInterval = 0
    
    // MARK: - Initialization
    
    public init(storage: DatabaseManager, config: SummarizationConfig = .default) {
        self.storage = storage
        self.config = config
    }
    
    // MARK: - Summary Generation
    
    /// Generate a summary for a specific date range
    /// - Parameters:
    ///   - startDate: Start of the date range
    ///   - endDate: End of the date range
    ///   - template: Optional template (uses config default if nil)
    /// - Returns: Generated Summary object
    public func generateSummary(
        from startDate: Date,
        to endDate: Date,
        using template: SummarizationTemplate? = nil
    ) async throws -> Summary {
        let startTime = Date()
        
        // Validate date range
        guard startDate < endDate else {
            throw SummarizationError.invalidDateRange(start: startDate, end: endDate)
        }
        
        // Fetch transcript segments for the date range
        let segments = try await storage.getTranscriptSegments(from: startDate, to: endDate)
        
        guard !segments.isEmpty else {
            throw SummarizationError.noTranscriptData
        }
        
        // Combine all transcript text
        let fullText = segments.map { $0.text }.joined(separator: " ")
        let wordCount = fullText.split(separator: " ").count
        
        // Check minimum content requirement
        guard wordCount >= config.minimumWords else {
            throw SummarizationError.insufficientContent(
                minimumWords: config.minimumWords,
                actualWords: wordCount
            )
        }
        
        // Use provided template or default from config
        let activeTemplate = template ?? config.template
        
        // Generate summary content
        let summaryText = try await performSummarization(
            text: fullText,
            template: activeTemplate,
            startDate: startDate,
            endDate: endDate
        )
        
        // Extract key topics (simple keyword extraction for now)
        _ = extractKeyTopics(from: fullText)
        
        // Analyze emotional tone
        _ = analyzeEmotionalTone(from: fullText)
        
        // Determine period type based on date range
        let daysDifference = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        let periodType: PeriodType = daysDifference <= 1 ? .day : daysDifference <= 7 ? .week : .month
        
        // Create Summary object
        let summary = Summary(
            periodType: periodType,
            periodStart: startDate,
            periodEnd: endDate,
            text: summaryText
        )
        
        // Save to storage
        do {
            _ = try await storage.insertSummary(summary)
        } catch {
            throw SummarizationError.storageError(error.localizedDescription)
        }
        
        // Update statistics
        let processingTime = Date().timeIntervalSince(startTime)
        summariesGenerated += 1
        totalProcessingTime += processingTime
        
        return summary
    }
    
    /// Generate a daily summary for a specific date
    /// - Parameter date: The date to summarize
    /// - Returns: Generated Summary object
    public func generateDailySummary(for date: Date) async throws -> Summary {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date.addingTimeInterval(86400)
        
        return try await generateSummary(
            from: startOfDay,
            to: endOfDay,
            using: SummarizationTemplates.daily
        )
    }
    
    /// Generate a weekly summary for the week containing the given date
    /// - Parameter date: A date within the week to summarize
    /// - Returns: Generated Summary object
    public func generateWeeklySummary(for date: Date) async throws -> Summary {
        let calendar = Calendar.current
        
        // Get the start of the week (Sunday)
        let weekday = calendar.component(.weekday, from: date)
        let daysToSubtract = weekday - 1 // Sunday is 1
        let startOfWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: date) ?? date
        let startOfWeekDay = calendar.startOfDay(for: startOfWeek)
        
        // Get end of week (Saturday)
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeekDay) ?? date
        
        return try await generateSummary(
            from: startOfWeekDay,
            to: endOfWeek,
            using: SummarizationTemplates.weekly
        )
    }
    
    /// Get statistics about summarization operations
    public func getStatistics() -> (summariesGenerated: Int, averageProcessingTime: TimeInterval) {
        let avgTime = summariesGenerated > 0 ? totalProcessingTime / Double(summariesGenerated) : 0
        return (summariesGenerated, avgTime)
    }
    
    /// Reset statistics
    public func resetStatistics() {
        summariesGenerated = 0
        totalProcessingTime = 0
    }
    
    // MARK: - Private Methods
    
    /// Perform the actual summarization using improved extractive approach
    /// Currently uses sentence scoring and selection
    /// TODO: Integrate with LLM (Apple Intelligence, OpenAI, etc.)
    private func performSummarization(
        text: String,
        template: SummarizationTemplate,
        startDate: Date,
        endDate: Date
    ) async throws -> String {
        // Split into sentences
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.split(separator: " ").count > 3 }
        
        guard !sentences.isEmpty else {
            return "Summary for \(DateFormatter.localizedString(from: startDate, dateStyle: .medium, timeStyle: .none))"
        }
        
        // Calculate target number of sentences based on word limit
        let avgWordsPerSentence = 15
        let maxSentences = max(1, template.maxWords / avgWordsPerSentence)
        
        // Score sentences based on multiple factors
        let scoredSentences = sentences.enumerated().map { index, sentence in
            var score = 0.0
            
            // Position score (earlier sentences often more important)
            let positionScore = 1.0 - (Double(index) / Double(sentences.count))
            score += positionScore * 0.3
            
            // Length score (prefer medium-length sentences)
            let wordCount = sentence.split(separator: " ").count
            let lengthScore = wordCount >= 8 && wordCount <= 25 ? 1.0 : 0.5
            score += lengthScore * 0.2
            
            // Keyword presence (important words increase score)
            let keywords = extractKeyTopics(from: text, limit: 10)
            let sentenceLower = sentence.lowercased()
            let keywordCount = keywords.filter { sentenceLower.contains($0) }.count
            score += Double(keywordCount) * 0.5
            
            return (sentence: sentence, score: score)
        }
        
        // Select top sentences
        let selectedSentences = scoredSentences
            .sorted { $0.score > $1.score }
            .prefix(min(maxSentences, sentences.count))
            .sorted { sentences.firstIndex(of: $0.sentence) ?? 0 < sentences.firstIndex(of: $1.sentence) ?? 0 }
            .map { $0.sentence }
        
        // Combine into summary
        var summary = selectedSentences.joined(separator: ". ")
        if !summary.isEmpty && !summary.hasSuffix(".") && !summary.hasSuffix("!") && !summary.hasSuffix("?") {
            summary += "."
        }
        
        return summary
    }
    
    /// Extract key topics from text using improved frequency analysis
    private func extractKeyTopics(from text: String, limit: Int = 5) -> [String] {
        // Common stop words to filter out
        let stopWords = Set([
            "the", "and", "that", "this", "with", "from", "have", "was", "were",
            "been", "which", "their", "what", "about", "would", "there", "could",
            "should", "when", "where", "they", "them", "than", "then", "these",
            "those", "will", "just", "your", "into", "more", "some", "very"
        ])
        
        // Extract words and filter
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 4 && !stopWords.contains($0) }
        
        // Count frequencies
        var frequencies: [String: Int] = [:]
        for word in words {
            frequencies[word, default: 0] += 1
        }
        
        // Get top words by frequency
        let topWords = frequencies.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
        
        return Array(topWords)
    }
    
    /// Analyze emotional tone from text using Apple's Natural Language framework
    /// Returns a human-readable categorization based on sentiment score
    private func analyzeEmotionalTone(from text: String) -> String {
        // Use Apple's Natural Language framework for accurate sentiment analysis
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        let (tag, _) = tagger.tag(
            at: text.startIndex,
            unit: .paragraph,
            scheme: .sentimentScore
        )
        
        // Convert sentiment score to descriptive label
        guard let tag = tag,
              let score = Double(tag.rawValue) else {
            return "balanced"  // Default if no sentiment detected
        }
        
        // Map sentiment score (-1.0 to +1.0) to descriptive terms
        switch score {
        case ..<(-0.5):
            return "very challenging"
        case -0.5..<(-0.2):
            return "challenging"
        case -0.2..<0.2:
            return "balanced"
        case 0.2..<0.5:
            return "mostly positive"
        default:
            return "positive"
        }
    }
}
