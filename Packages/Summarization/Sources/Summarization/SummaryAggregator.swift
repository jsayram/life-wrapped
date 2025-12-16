// =============================================================================
// Summarization — Summary Aggregation
// =============================================================================

import Foundation

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
        
        // Step 1: Combine and deduplicate sentences
        var allSentences: [String] = []
        var seenSentences = Set<String>()
        
        for summary in summaries {
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
        
        // Step 3: Extract key themes using word frequency
        let themes = extractKeyThemes(from: summaries)
        
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
        
        // Count word frequencies across all summaries
        for summary in summaries {
            let words = summary
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { word in
                    word.count > 3 && !stopwords.contains(word)
                }
            
            for word in words {
                wordCounts[word, default: 0] += 1
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
