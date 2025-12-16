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
    
    /// Get flag emoji for language ISO code
    /// - Parameter code: ISO language code (e.g., "en", "es", "fr")
    /// - Returns: Flag emoji (e.g., 🇺🇸, 🇪🇸, 🇫🇷)
    public static func flagEmoji(for code: String) -> String {
        // Map language codes to country codes for flags
        let languageToCountry: [String: String] = [
            "en": "us", "es": "mx", "fr": "fr", "de": "de", "it": "it",
            "pt": "pt", "zh": "cn", "ja": "jp", "ko": "kr", "ar": "sa",
            "ru": "ru", "nl": "nl", "sv": "se", "no": "no", "da": "dk",
            "fi": "fi", "pl": "pl", "tr": "tr", "el": "gr", "he": "il",
            "hi": "in", "bn": "bd", "th": "th", "vi": "vn", "id": "id", "ms": "my",
            "uk": "ua", "cs": "cz", "sk": "sk", "ro": "ro", "hr": "hr", "hu": "hu"
        ]
        
        let countryCode = languageToCountry[code.lowercased()] ?? code.lowercased()
        let base: UInt32 = 127397
        var emoji = ""
        
        for scalar in countryCode.uppercased().unicodeScalars {
            if let scalarValue = UnicodeScalar(base + scalar.value) {
                emoji.append(String(scalarValue))
            }
        }
        
        return emoji.isEmpty ? "🌐" : emoji
    }
    
    /// Get list of supported languages
    /// - Returns: Array of ISO language codes (English and Spanish first)
    public static func supportedLanguages() -> [String] {
        // Only support these 9 languages
        return ["en", "es", "hi", "bn", "fr", "vi", "zh", "ko", "tr"]
    }
    
    /// Detect the dominant language in text
    /// - Parameter text: Text to analyze
    /// - Returns: Language code (e.g., "en", "es", "fr") or nil if undetermined
    public func detectLanguage(in text: String) -> String? {
        // Need minimum text length for accurate detection
        guard text.count >= 10 else { return nil }
        
        recognizer.reset()
        
        // Constrain detection to enabled languages from Settings
        if let enabledLanguages = UserDefaults.standard.array(forKey: "enabledLanguages") as? [String],
           !enabledLanguages.isEmpty {
            let nlLanguages = enabledLanguages.compactMap { NLLanguage(rawValue: $0) }
            if !nlLanguages.isEmpty {
                recognizer.languageHints = nlLanguages.reduce(into: [:]) { $0[$1] = 1.0 }
            }
        }
        
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
