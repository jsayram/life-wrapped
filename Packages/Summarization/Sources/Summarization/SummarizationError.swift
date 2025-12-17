// =============================================================================
// Summarization — Error Types
// =============================================================================

import Foundation

/// Errors that can occur during summarization operations
public enum SummarizationError: LocalizedError, Sendable {
    case noTranscriptData
    case insufficientContent(minimumWords: Int, actualWords: Int)
    case summarizationFailed(String)
    case invalidDateRange(start: Date, end: Date)
    case storageError(String)
    case templateNotFound(String)
    case configurationError(String)
    case encodingFailed(String)
    case decodingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .noTranscriptData:
            return "No transcript data available for summarization."
            
        case .insufficientContent(let minimum, let actual):
            return "Insufficient content for summarization. Minimum \(minimum) words required, got \(actual)."
            
        case .summarizationFailed(let reason):
            return "Summarization failed: \(reason)"
            
        case .invalidDateRange(let start, let end):
            return "Invalid date range: start (\(start)) must be before end (\(end))."
            
        case .storageError(let reason):
            return "Storage error during summarization: \(reason)"
            
        case .templateNotFound(let templateName):
            return "Summary template '\(templateName)' not found."
            
        case .configurationError(let reason):
            return "Configuration error: \(reason)"
            
        case .encodingFailed(let reason):
            return "JSON encoding failed: \(reason)"
            
        case .decodingFailed(let reason):
            return "JSON decoding failed: \(reason)"
        }
    }
}
