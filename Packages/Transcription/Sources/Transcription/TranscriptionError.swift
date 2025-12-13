// =============================================================================
// Transcription — Error Types
// =============================================================================

import Foundation

/// Errors that can occur during transcription operations
public enum TranscriptionError: Error, LocalizedError, Sendable {
    case notAuthorized
    case notAvailable
    case recognizerSetupFailed(String)
    case recognitionFailed(String)
    case audioFileNotFound(URL)
    case invalidAudioFormat(String)
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition is not authorized"
        case .notAvailable:
            return "Speech recognition is not available on this device"
        case .recognizerSetupFailed(let reason):
            return "Failed to setup speech recognizer: \(reason)"
        case .recognitionFailed(let reason):
            return "Recognition failed: \(reason)"
        case .audioFileNotFound(let url):
            return "Audio file not found: \(url.lastPathComponent)"
        case .invalidAudioFormat(let reason):
            return "Invalid audio format: \(reason)"
        case .cancelled:
            return "Transcription was cancelled"
        }
    }
}
