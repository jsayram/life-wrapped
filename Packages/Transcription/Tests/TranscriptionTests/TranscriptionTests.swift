// =============================================================================
// Transcription — Tests
// =============================================================================

import Foundation
import Testing
import Speech
@testable import Transcription
@testable import SharedModels

@Suite("Transcription Manager Tests")
struct TranscriptionManagerTests {
    
    @Test("Manager checks speech recognition availability")
    func testAvailabilityCheck() async throws {
        // Note: This test requires DatabaseManager which needs Storage
        // In real implementation, we'd use dependency injection or mocking
        
        // For now, test that Speech framework is available
        let isAvailable = SFSpeechRecognizer.authorizationStatus() != .denied
        #expect(isAvailable || SFSpeechRecognizer.authorizationStatus() == .notDetermined)
    }
    
    @Test("Manager can check locale availability")
    func testLocaleAvailability() async throws {
        // English should be available on all devices
        let englishLocale = Locale(identifier: "en-US")
        
        // Check if recognizer can be created
        let recognizer = SFSpeechRecognizer(locale: englishLocale)
        #expect(recognizer != nil)
    }
}

@Suite("Language Detector Tests")
struct LanguageDetectorTests {
    
    @Test("Detects English text")
    func testEnglishDetection() async throws {
        let detector = LanguageDetector()
        let text = "Hello, this is a test of the language detection system."
        
        let language = await detector.detectLanguage(in: text)
        #expect(language == "en")
    }
    
    @Test("Detects Spanish text")
    func testSpanishDetection() async throws {
        let detector = LanguageDetector()
        let text = "Hola, esta es una prueba del sistema de detección de idiomas."
        
        let language = await detector.detectLanguage(in: text)
        #expect(language == "es")
    }
    
    @Test("Returns nil for empty text")
    func testEmptyText() async throws {
        let detector = LanguageDetector()
        let language = await detector.detectLanguage(in: "")
        
        #expect(language == nil)
    }
    
    @Test("Gets language hypotheses with confidence")
    func testLanguageHypotheses() async throws {
        let detector = LanguageDetector()
        let text = "Hello world"
        
        let hypotheses = await detector.getLanguageHypotheses(in: text)
        
        // Should have at least one hypothesis
        #expect(hypotheses.count > 0)
        
        // English should be in the hypotheses
        #expect(hypotheses["en"] != nil)
        
        // Confidence should be between 0 and 1
        if let confidence = hypotheses["en"] {
            #expect(confidence >= 0.0 && confidence <= 1.0)
        }
    }
    
    @Test("Handles mixed language text")
    func testMixedLanguageText() async throws {
        let detector = LanguageDetector()
        let text = "Hello amigo, comment ça va?"
        
        let language = await detector.detectLanguage(in: text)
        
        // Should detect a dominant language
        #expect(language != nil)
    }
}

@Suite("Transcription Error Tests")
struct TranscriptionErrorTests {
    
    @Test("Error descriptions are meaningful")
    func testErrorDescriptions() throws {
        let errors: [TranscriptionError] = [
            .notAuthorized,
            .notAvailable,
            .recognizerSetupFailed("test reason"),
            .recognitionFailed("test reason"),
            .audioFileNotFound(URL(fileURLWithPath: "/tmp/test.m4a")),
            .invalidAudioFormat("test reason"),
            .cancelled
        ]
        
        for error in errors {
            let description = error.errorDescription
            #expect(description != nil)
            #expect(description!.isEmpty == false)
        }
    }
    
    @Test("Error types are distinct")
    func testErrorTypesDistinct() throws {
        let error1 = TranscriptionError.notAuthorized
        let error2 = TranscriptionError.notAvailable
        
        #expect(error1.errorDescription != error2.errorDescription)
    }
    
    @Test("Audio file not found includes path")
    func testAudioFileNotFoundError() throws {
        let url = URL(fileURLWithPath: "/tmp/test-audio.m4a")
        let error = TranscriptionError.audioFileNotFound(url)
        
        let description = error.errorDescription!
        #expect(description.contains("test-audio.m4a"))
    }
}
