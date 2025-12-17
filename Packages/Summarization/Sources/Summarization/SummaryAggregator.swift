// =============================================================================
// Summarization — Summary Aggregation
// =============================================================================

import Foundation
import NaturalLanguage

/// Protocol for aggregating multiple summaries into one
public protocol SummaryAggregator {
    func aggregate(summaries: [String]) -> String
}

/// Basic aggregator using string manipulation and word frequency
public class BasicAggregator: SummaryAggregator {
    
    private let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
        "be", "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "can", "this", "that", "these", "those", "i",
        "you", "he", "she", "it", "we", "they", "my", "your", "his", "her",
        "its", "our", "their", "me", "him", "us", "them", "what", "which",
        "who", "when", "where", "why", "how", "all", "each", "every", "both",
        "few", "more", "most", "some", "such", "no", "not", "only", "own",
        "same", "so", "than", "too", "very", "just", "about"
    ]
    
    public init() {}
    
    public func aggregate(summaries: [String]) -> String {
        guard !summaries.isEmpty else { return "" }
        
        // Single summary - return as is
        if summaries.count == 1 {
            return summaries[0]
        }
        
        // Step 0: Strip existing "Key themes:" sections to avoid duplication
        let cleanedSummaries = summaries.map { summary in
            // Remove everything from "Key themes:" onward
            if let range = summary.range(of: "Key themes:", options: .caseInsensitive) {
                return String(summary[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            return summary
        }
        
        // Step 1: Combine and deduplicate sentences
        var allSentences: [String] = []
        var seenSentences = Set<String>()
        
        for summary in cleanedSummaries {
            let sentences = splitIntoSentences(summary)
            for sentence in sentences {
                let normalized = sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !seenSentences.contains(normalized) && !normalized.isEmpty {
                    allSentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    seenSentences.insert(normalized)
                }
            }
        }
        
        // Step 2: Join sentences
        let combinedText = allSentences.joined(separator: ". ")
        
        // Step 3: Extract key themes using word frequency from cleaned summaries
        let themes = extractKeyThemes(from: cleanedSummaries)
        
        // Step 4: Format final summary
        var result = combinedText
        if !result.hasSuffix(".") && !result.hasSuffix("!") && !result.hasSuffix("?") {
            result += "."
        }
        
        if !themes.isEmpty {
            let themeString = themes.map { "\($0.word) (\($0.count))" }.joined(separator: ", ")
            result += " Key themes: \(themeString)."
        }
        
        return result
    }
    
    private func splitIntoSentences(_ text: String) -> [String] {
        // Simple sentence splitting by period followed by space or end
        var sentences: [String] = []
        var currentSentence = ""
        
        let characters = Array(text)
        for i in 0..<characters.count {
            currentSentence.append(characters[i])
            
            // Check for sentence ending
            if characters[i] == "." || characters[i] == "!" || characters[i] == "?" {
                // Check if followed by space or end of string
                if i == characters.count - 1 || characters[i + 1].isWhitespace {
                    sentences.append(currentSentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentSentence = ""
                }
            }
        }
        
        // Add remaining text if any
        if !currentSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(currentSentence.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        return sentences
    }
    
    private func extractKeyThemes(from summaries: [String]) -> [(word: String, count: Int)] {
        var wordCounts: [String: Int] = [:]
        
        // Use NaturalLanguage to extract only meaningful nouns
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        
        for summary in summaries {
            tagger.string = summary
            let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
            
            tagger.enumerateTags(in: summary.startIndex..<summary.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
                // Only count nouns (actual topics/things)
                guard let tag = tag, tag == .noun else { return true }
                
                let word = String(summary[tokenRange]).lowercased()
                
                // Filter: must be 4+ characters and not a stopword
                guard word.count >= 4, !stopwords.contains(word) else { return true }
                
                wordCounts[word, default: 0] += 1
                return true
            }
        }
        
        // Filter and sort by frequency (must appear at least twice)
        let themes = wordCounts
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (word: $0.key, count: $0.value) }
        
        return Array(themes)
    }
}
