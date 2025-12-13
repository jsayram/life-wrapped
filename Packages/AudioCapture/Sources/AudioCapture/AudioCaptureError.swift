// =============================================================================
// AudioCapture — Error Types
// =============================================================================

import Foundation

/// Errors that can occur during audio capture operations
public enum AudioCaptureError: Error, LocalizedError, Sendable {
    case notAuthorized
    case audioSessionSetupFailed(String)
    case engineStartFailed(String)
    case fileCreationFailed(String)
    case invalidState(String)
    case recordingFailed(String)
    case appGroupContainerNotFound
    
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Microphone access is not authorized"
        case .audioSessionSetupFailed(let reason):
            return "Failed to setup audio session: \(reason)"
        case .engineStartFailed(let reason):
            return "Failed to start audio engine: \(reason)"
        case .fileCreationFailed(let reason):
            return "Failed to create audio file: \(reason)"
        case .invalidState(let reason):
            return "Invalid state: \(reason)"
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        case .appGroupContainerNotFound:
            return "App Group container not found"
        }
    }
}
