// =============================================================================
// WordAnalyzer.swift — Word frequency analysis utilities
// =============================================================================

import Foundation

// MARK: - Word Frequency Model

struct WordFrequency: Identifiable {
    let id = UUID()
    let word: String
    let count: Int
}

// MARK: - Word Analyzer

class WordAnalyzer {
    // Use comprehensive stopwords from constants file (single source of truth)
    static let stopwords = StopWords.all
    
    static func analyzeWords(from texts: [String], limit: Int = 20, customExcludedWords: Set<String> = []) -> [WordFrequency] {
        // Combine built-in and custom stopwords
        let allStopwords = stopwords.union(customExcludedWords)
        var wordCounts: [String: Int] = [:]
        
        // Process all texts
        for text in texts {
            // Normalize: lowercase and split into words
            let words = text.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { word in
                    // Remove punctuation from edges
                    word.trimmingCharacters(in: .punctuationCharacters)
                }
                .filter { word in
                    // Filter: non-empty, at least 2 chars, not a stopword, not a number
                    !word.isEmpty &&
                    word.count >= 2 &&
                    !allStopwords.contains(word) &&
                    !word.allSatisfy { $0.isNumber }
                }
            
            // Count occurrences
            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }
        
        // Sort by frequency and take top N
        return wordCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { WordFrequency(word: $0.key, count: $0.value) }
    }
}
