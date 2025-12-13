// =============================================================================
// SharedModels — Constants
// =============================================================================

import Foundation

/// App-wide constants
public enum AppConstants {
    /// App Group identifier for sharing data between app and extensions
    public static let appGroupIdentifier = "group.com.jsayram.lifewrapped"

    /// CloudKit container identifier
    public static let cloudKitContainerIdentifier = "iCloud.com.jsayram.lifewrapped"

    /// Keychain service identifier
    public static let keychainService = "com.jsayram.lifewrapped"

    /// Database filename
    public static let databaseFilename = "lifewrapped.sqlite"

    /// Audio chunks directory name
    public static let audioChunksDirectory = "AudioChunks"

    /// Backups directory name
    public static let backupsDirectory = "Backups"

    /// Maximum audio file age before cleanup (30 days)
    public static let maxAudioFileAge: TimeInterval = 30 * 24 * 60 * 60

    /// Default chunk duration in seconds
    public static let defaultChunkDuration: TimeInterval = 60

    /// Minimum iOS version for on-device speech recognition
    public static let minIOSVersionForOnDeviceSpeech = 17.0
}

/// Notification names for inter-component communication
public extension Notification.Name {
    static let listeningStateDidChange = Notification.Name("listeningStateDidChange")
    static let newTranscriptAvailable = Notification.Name("newTranscriptAvailable")
    static let audioChunkCompleted = Notification.Name("audioChunkCompleted")
    static let insightsDidUpdate = Notification.Name("insightsDidUpdate")
    static let syncDidComplete = Notification.Name("syncDidComplete")
    static let backgroundTaskWillExpire = Notification.Name("backgroundTaskWillExpire")
}

/// UserInfo keys for notifications
public enum NotificationUserInfoKey: String {
    case listeningState
    case transcriptSegment
    case audioChunk
    case error
}
