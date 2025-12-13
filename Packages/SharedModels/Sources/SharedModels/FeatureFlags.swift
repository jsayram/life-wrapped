// =============================================================================
// SharedModels — Feature Flags
// =============================================================================

import Foundation

/// Feature flags for progressive rollout and development.
public enum FeatureFlag: String, CaseIterable, Sendable {
    case passiveListening = "passive_listening"
    case onDeviceSummarization = "on_device_summarization"
    case cloudKitSync = "cloudkit_sync"
    case watchApp = "watch_app"
    case speakerDiarization = "speaker_diarization"
    case entityExtraction = "entity_extraction"
    case encryptedBackup = "encrypted_backup"

    public var displayName: String {
        switch self {
        case .passiveListening: "Passive Listening"
        case .onDeviceSummarization: "On-Device Summarization"
        case .cloudKitSync: "CloudKit Sync"
        case .watchApp: "Apple Watch"
        case .speakerDiarization: "Speaker Detection"
        case .entityExtraction: "Entity Extraction"
        case .encryptedBackup: "Encrypted Backup"
        }
    }

    public var description: String {
        switch self {
        case .passiveListening:
            "Only record when speech is detected to save battery"
        case .onDeviceSummarization:
            "Generate summaries using on-device AI"
        case .cloudKitSync:
            "Sync data across devices via iCloud"
        case .watchApp:
            "Control and view stats from Apple Watch"
        case .speakerDiarization:
            "Identify different speakers in recordings"
        case .entityExtraction:
            "Extract people, places, and topics from transcripts"
        case .encryptedBackup:
            "Encrypt backup files with a password"
        }
    }

    /// Whether this feature is enabled by default
    public var defaultEnabled: Bool {
        switch self {
        case .passiveListening: true
        case .onDeviceSummarization: false  // Phase 2
        case .cloudKitSync: false  // Phase 2
        case .watchApp: true
        case .speakerDiarization: false  // Future
        case .entityExtraction: false  // Future
        case .encryptedBackup: true
        }
    }
}

/// Protocol for feature flag storage
public protocol FeatureFlagProvider: Sendable {
    func isEnabled(_ flag: FeatureFlag) -> Bool
    func setEnabled(_ flag: FeatureFlag, enabled: Bool)
}

/// Default implementation using UserDefaults
public final class UserDefaultsFeatureFlagProvider: FeatureFlagProvider, @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "feature_flag_") {
        self.defaults = defaults
        self.prefix = prefix
    }

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        let key = prefix + flag.rawValue
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return flag.defaultEnabled
    }

    public func setEnabled(_ flag: FeatureFlag, enabled: Bool) {
        let key = prefix + flag.rawValue
        defaults.set(enabled, forKey: key)
    }
}
