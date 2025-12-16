// =============================================================================
// Transcription — Language Detection
// =============================================================================

import Foundation
import NaturalLanguage

/// Utility for detecting language from text
public actor LanguageDetector {
    
    private let recognizer = NLLanguageRecognizer()
    
    public init() {}
    
    /// Get human-readable language name from ISO code
    /// - Parameter code: ISO language code (e.g., "en", "es")
    /// - Returns: Localized language name (e.g., "English", "Spanish")
    public static func displayName(for code: String) -> String {
        let locale = Locale.current
        return locale.localizedString(forLanguageCode: code) ?? code.uppercased()
    }
    
    /// Get list of all languages supported by Apple's NL framework
    /// - Returns: Array of ISO language codes
    public static func supportedLanguages() -> [String] {
        // Common languages supported by Apple's Natural Language framework
        // This list represents the most commonly used languages
        return [
            "ar", "zh", "hr", "cs", "da", "nl", "en", "fi", "fr", "de", "el",
            "he", "hi", "hu", "id", "it", "ja", "ko", "ms", "no", "pl", "pt",
            "ro", "ru", "sk", "es", "sv", "th", "tr", "uk", "vi"
        ].sorted()
    }
    
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
