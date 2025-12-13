// =============================================================================
// SharedModels — Watch Connectivity Messages
// =============================================================================

import Foundation

/// Messages sent between iPhone and Apple Watch
public enum WatchMessage: Codable, Sendable {
    // MARK: - Commands (Watch → Phone)

    case startListening(mode: ListeningMode)
    case stopListening
    case toggleMode
    case addMarker(note: String?)
    case requestState
    case requestTodayStats

    // MARK: - Responses (Phone → Watch)

    case stateUpdate(WatchStatePayload)
    case todayStats(WatchStatsPayload)
    case error(message: String)

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum MessageType: String, Codable {
        case startListening
        case stopListening
        case toggleMode
        case addMarker
        case requestState
        case requestTodayStats
        case stateUpdate
        case todayStats
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)

        switch type {
        case .startListening:
            let mode = try container.decode(ListeningMode.self, forKey: .payload)
            self = .startListening(mode: mode)
        case .stopListening:
            self = .stopListening
        case .toggleMode:
            self = .toggleMode
        case .addMarker:
            let note = try container.decodeIfPresent(String.self, forKey: .payload)
            self = .addMarker(note: note)
        case .requestState:
            self = .requestState
        case .requestTodayStats:
            self = .requestTodayStats
        case .stateUpdate:
            let payload = try container.decode(WatchStatePayload.self, forKey: .payload)
            self = .stateUpdate(payload)
        case .todayStats:
            let payload = try container.decode(WatchStatsPayload.self, forKey: .payload)
            self = .todayStats(payload)
        case .error:
            let message = try container.decode(String.self, forKey: .payload)
            self = .error(message: message)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .startListening(let mode):
            try container.encode(MessageType.startListening, forKey: .type)
            try container.encode(mode, forKey: .payload)
        case .stopListening:
            try container.encode(MessageType.stopListening, forKey: .type)
        case .toggleMode:
            try container.encode(MessageType.toggleMode, forKey: .type)
        case .addMarker(let note):
            try container.encode(MessageType.addMarker, forKey: .type)
            try container.encodeIfPresent(note, forKey: .payload)
        case .requestState:
            try container.encode(MessageType.requestState, forKey: .type)
        case .requestTodayStats:
            try container.encode(MessageType.requestTodayStats, forKey: .type)
        case .stateUpdate(let payload):
            try container.encode(MessageType.stateUpdate, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .todayStats(let payload):
            try container.encode(MessageType.todayStats, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .error(let message):
            try container.encode(MessageType.error, forKey: .type)
            try container.encode(message, forKey: .payload)
        }
    }

    /// Convert to dictionary for WatchConnectivity
    public func toDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dict = json as? [String: Any] else {
            throw WatchMessageError.invalidFormat
        }
        return dict
    }

    /// Create from WatchConnectivity dictionary
    public static func fromDictionary(_ dict: [String: Any]) throws -> WatchMessage {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(WatchMessage.self, from: data)
    }
}

public enum WatchMessageError: Error {
    case invalidFormat
    case decodingFailed
}

// MARK: - Payloads

public struct WatchStatePayload: Codable, Sendable {
    public let isListening: Bool
    public let mode: ListeningMode
    public let isPaused: Bool
    public let pauseReason: PauseReason?
    public let lastUpdated: Date

    public init(
        isListening: Bool,
        mode: ListeningMode,
        isPaused: Bool,
        pauseReason: PauseReason?,
        lastUpdated: Date = Date()
    ) {
        self.isListening = isListening
        self.mode = mode
        self.isPaused = isPaused
        self.pauseReason = pauseReason
        self.lastUpdated = lastUpdated
    }
}

public struct WatchStatsPayload: Codable, Sendable {
    public let wordCount: Int
    public let speakingMinutes: Double
    public let segmentCount: Int
    public let latestSnippet: String?
    public let date: Date

    public init(
        wordCount: Int,
        speakingMinutes: Double,
        segmentCount: Int,
        latestSnippet: String?,
        date: Date = Date()
    ) {
        self.wordCount = wordCount
        self.speakingMinutes = speakingMinutes
        self.segmentCount = segmentCount
        self.latestSnippet = latestSnippet
        self.date = date
    }
}
