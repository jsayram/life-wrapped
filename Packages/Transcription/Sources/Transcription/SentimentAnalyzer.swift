// =============================================================================
// Transcription — Sentiment Analyzer
// =============================================================================
// On-device sentiment analysis using Apple's Natural Language framework.
// Analyzes emotional tone of transcribed text without any network calls.
// =============================================================================

import NaturalLanguage
import SharedModels
import Foundation

/// On-device sentiment analyzer using Apple's Natural Language framework
/// Analyzes emotional tone of transcribed text with scores from -1.0 (negative) to +1.0 (positive)
/// Privacy: 100% on-device processing, no network calls, no model downloads required
public actor SentimentAnalyzer {
    
    // MARK: - Properties
    
    private let tagger: NLTagger
    
    // MARK: - Statistics
    
    private(set) var segmentsAnalyzed: Int = 0
    private(set) var totalProcessingTime: TimeInterval = 0
    
    // MARK: - Initialization
    
    public init() {
        self.tagger = NLTagger(tagSchemes: [.sentimentScore])
    }
    
    // MARK: - Public Methods
    
    /// Analyze sentiment of a single transcript segment
    /// - Parameter segment: The transcript segment to analyze
    /// - Returns: Sentiment score from -1.0 (most negative) to +1.0 (most positive), or nil if text is too short
    public func analyze(segment: TranscriptSegment) -> Double? {
        analyze(text: segment.text)
    }
    
    /// Analyze sentiment of raw text
    /// - Parameter text: The text to analyze
    /// - Returns: Sentiment score from -1.0 (most negative) to +1.0 (most positive), or nil if text is too short
    public func analyze(text: String) -> Double? {
        let startTime = Date()
        
        // Require at least 2 words for reliable sentiment analysis
        guard !text.isEmpty, text.split(separator: " ").count > 1 else {
            return nil
        }
        
        tagger.string = text
        
        let (tag, _) = tagger.tag(
            at: text.startIndex,
            unit: .paragraph,
            scheme: .sentimentScore
        )
        
        // Update statistics
        segmentsAnalyzed += 1
        totalProcessingTime += Date().timeIntervalSince(startTime)
        
        guard let tag = tag,
              let score = Double(tag.rawValue) else {
            return 0.0 // Return neutral if no sentiment detected
        }
        
        return score
    }
    
    /// Analyze sentiment of multiple segments in batch
    /// - Parameter segments: Array of transcript segments to analyze
    /// - Returns: Dictionary mapping segment IDs to sentiment scores
    public func analyzeBatch(_ segments: [TranscriptSegment]) -> [UUID: Double] {
        segments.reduce(into: [:]) { result, segment in
            if let score = analyze(segment: segment) {
                result[segment.id] = score
            }
        }
    }
    
    /// Calculate average sentiment for a collection of segments
    /// - Parameter segments: Array of transcript segments
    /// - Returns: Average sentiment score, or nil if no segments have sentiment
    public func sessionAverage(for segments: [TranscriptSegment]) -> Double? {
        let scores = segments.compactMap { analyze(segment: $0) }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }
    
    /// Categorize a sentiment score into a human-readable label
    /// - Parameter score: Sentiment score from -1.0 to +1.0
    /// - Returns: Category label
    public static func categorize(_ score: Double) -> String {
        switch score {
        case ..<(-0.5): return "Very Negative"
        case -0.5..<(-0.2): return "Negative"
        case -0.2..<0.2: return "Neutral"
        case 0.2..<0.5: return "Positive"
        default: return "Very Positive"
        }
    }
    
    /// Get sentiment category with shorter labels for UI
    /// - Parameter score: Sentiment score from -1.0 to +1.0
    /// - Returns: Short category label
    public static func categorizeShort(_ score: Double) -> String {
        switch score {
        case ..<(-0.3): return "Negative"
        case -0.3..<0.3: return "Neutral"
        default: return "Positive"
        }
    }
    
    /// Get emoji representation of sentiment
    /// - Parameter score: Sentiment score from -1.0 to +1.0
    /// - Returns: Emoji character
    public static func emoji(for score: Double) -> String {
        switch score {
        case ..<(-0.5): return "😢"
        case -0.5..<(-0.2): return "😔"
        case -0.2..<0.2: return "😐"
        case 0.2..<0.5: return "🙂"
        default: return "😊"
        }
    }
    
    /// Get color for sentiment visualization
    /// - Parameter score: Sentiment score from -1.0 to +1.0
    /// - Returns: Color name suitable for SwiftUI Color
    public static func colorName(for score: Double) -> String {
        switch score {
        case ..<(-0.3): return "red"
        case -0.3..<0.3: return "gray"
        default: return "green"
        }
    }
    
    /// Get statistics about analysis operations
    /// - Returns: Tuple with count of analyzed segments and average processing time
    public func getStatistics() -> (analyzed: Int, averageTime: TimeInterval) {
        let avgTime = segmentsAnalyzed > 0 ? 
            totalProcessingTime / Double(segmentsAnalyzed) : 0
        return (segmentsAnalyzed, avgTime)
    }
    
    /// Reset statistics counters
    public func resetStatistics() {
        segmentsAnalyzed = 0
        totalProcessingTime = 0
    }
}
