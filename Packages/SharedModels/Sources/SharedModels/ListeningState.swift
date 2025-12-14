// =============================================================================
// SharedModels — Listening State
// =============================================================================

import Foundation

// MARK: - Listening Mode

/// The listening mode determines how the app captures audio.
public enum ListeningMode: String, Codable, Sendable, CaseIterable {
    /// Continuously record and transcribe audio
    case active

    /// Only record/transcribe when speech is detected (battery-aware)
    case passive

    public var displayName: String {
        switch self {
        case .active: "Active"
        case .passive: "Passive"
        }
    }

    public var description: String {
        switch self {
        case .active: "Continuous recording and transcription"
        case .passive: "Record only when speech is detected"
        }
    }

    public var systemImage: String {
        switch self {
        case .active: "waveform.circle.fill"
        case .passive: "waveform.badge.mic"
        }
    }
}

// MARK: - Listening State

/// Represents the current state of the audio capture system.
public enum ListeningState: Sendable, Equatable {
    case idle
    case starting
    case listening(mode: ListeningMode)
    case paused(reason: PauseReason)
    case stopping
    case error(message: String)

    public var isListening: Bool {
        if case .listening = self { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    public var canStart: Bool {
        switch self {
        case .idle, .error: true
        default: false
        }
    }

    public var canStop: Bool {
        switch self {
        case .listening, .paused: true
        default: false
        }
    }

    public var displayName: String {
        switch self {
        case .idle: "Ready"
        case .starting: "Starting..."
        case .listening(let mode): "Listening (\(mode.displayName))"
        case .paused(let reason): "Paused: \(reason.displayName)"
        case .stopping: "Stopping..."
        case .error(let message): "Error: \(message)"
        }
    }

    public var systemImage: String {
        switch self {
        case .idle: "mic.slash"
        case .starting: "hourglass"
        case .listening: "mic.fill"
        case .paused: "pause.circle"
        case .stopping: "hourglass"
        case .error: "exclamationmark.triangle"
        }
    }
    
    public var mode: ListeningMode? {
        if case .listening(let mode) = self {
            return mode
        }
        return nil
    }
}

// MARK: - Pause Reason

public enum PauseReason: String, Codable, Sendable, CaseIterable {
    case userRequested
    case phoneCall
    case otherAudioSession
    case systemInterruption
    case lowBattery
    case backgroundSuspension

    public var displayName: String {
        switch self {
        case .userRequested: "User Paused"
        case .phoneCall: "Phone Call"
        case .otherAudioSession: "Other Audio"
        case .systemInterruption: "System"
        case .lowBattery: "Low Battery"
        case .backgroundSuspension: "Background"
        }
    }

    public var canAutoResume: Bool {
        switch self {
        case .userRequested, .lowBattery: false
        case .phoneCall, .otherAudioSession, .systemInterruption, .backgroundSuspension: true
        }
    }
}

// MARK: - Capture Configuration

/// Configuration for audio capture behavior.
public struct CaptureConfiguration: Codable, Sendable, Hashable {
    /// Duration of each audio chunk in seconds
    public var chunkDuration: TimeInterval

    /// Audio sample rate
    public var sampleRate: Int

    /// Output format
    public var format: AudioFormat

    /// Enable Voice Activity Detection for passive mode
    public var enableVAD: Bool

    /// Minimum speech duration to trigger recording in passive mode (seconds)
    public var vadMinSpeechDuration: TimeInterval

    /// Rolling buffer duration in passive mode (seconds before speech detection)
    public var rollingBufferDuration: TimeInterval

    public static let `default` = CaptureConfiguration(
        chunkDuration: 60,  // 1 minute chunks
        sampleRate: 16000,  // 16kHz for speech
        format: .m4a,
        enableVAD: true,
        vadMinSpeechDuration: 0.5,
        rollingBufferDuration: 3.0
    )

    public init(
        chunkDuration: TimeInterval = 60,
        sampleRate: Int = 16000,
        format: AudioFormat = .m4a,
        enableVAD: Bool = true,
        vadMinSpeechDuration: TimeInterval = 0.5,
        rollingBufferDuration: TimeInterval = 3.0
    ) {
        self.chunkDuration = chunkDuration
        self.sampleRate = sampleRate
        self.format = format
        self.enableVAD = enableVAD
        self.vadMinSpeechDuration = vadMinSpeechDuration
        self.rollingBufferDuration = rollingBufferDuration
    }
}
