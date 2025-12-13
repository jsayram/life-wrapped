// =============================================================================
// Transcription — Language Detection
// =============================================================================

import Foundation
import NaturalLanguage

/// Utility for detecting language from text
public actor LanguageDetector {
    
    private let recognizer = NLLanguageRecognizer()
    
    public init() {}
    
    /// Detect the dominant language in text
    /// - Parameter text: Text to analyze
    /// - Returns: Language code (e.g., "en", "es", "fr") or nil if undetermined
    public func detectLanguage(in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        
        recognizer.reset()
        recognizer.processString(text)
        
        guard let language = recognizer.dominantLanguage else {
            return nil
        }
        
        return language.rawValue
    }
    
    /// Get language hypotheses with confidence scores
    /// - Parameter text: Text to analyze
    /// - Returns: Dictionary of language codes to confidence scores
    public func getLanguageHypotheses(in text: String) -> [String: Double] {
        guard !text.isEmpty else { return [:] }
        
        recognizer.reset()
        recognizer.processString(text)
        
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        
        return hypotheses.reduce(into: [:]) { result, pair in
            result[pair.key.rawValue] = pair.value
        }
    }
}
