// =============================================================================
// SummaryVersion.swift — An earlier version of a summary, kept when it is replaced
// =============================================================================
//
// Every time a session summary, month digest or Year Wrap is rewritten, the text it
// replaces is kept here. That makes regenerating reversible: a summary written by
// Cloud AI can be brought back after Key Sentences rewrote it, and nothing a better
// engine wrote is ever lost for good.
//

import Foundation

public struct SummaryVersion: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    /// Which summary this was a version of; see `Summary.versionKey`
    public let summaryKey: String
    public let text: String
    /// When this version was written
    public let createdAt: Date
    /// When it was replaced by a newer one
    public let replacedAt: Date
    public let engineTier: String?
    public let topicsJSON: String?
    public let entitiesJSON: String?
    public let sourceIds: String?
    public let inputHash: String?

    public init(
        id: UUID = UUID(),
        summaryKey: String,
        text: String,
        createdAt: Date,
        replacedAt: Date = Date(),
        engineTier: String? = nil,
        topicsJSON: String? = nil,
        entitiesJSON: String? = nil,
        sourceIds: String? = nil,
        inputHash: String? = nil
    ) {
        self.id = id
        self.summaryKey = summaryKey
        self.text = text
        self.createdAt = createdAt
        self.replacedAt = replacedAt
        self.engineTier = engineTier
        self.topicsJSON = topicsJSON
        self.entitiesJSON = entitiesJSON
        self.sourceIds = sourceIds
        self.inputHash = inputHash
    }

    /// The version a summary becomes when something replaces it
    public init(archiving summary: Summary, replacedAt: Date = Date()) {
        self.init(
            summaryKey: summary.versionKey,
            text: summary.text,
            createdAt: summary.createdAt,
            replacedAt: replacedAt,
            engineTier: summary.engineTier,
            topicsJSON: summary.topicsJSON,
            entitiesJSON: summary.entitiesJSON,
            sourceIds: summary.sourceIds,
            inputHash: summary.inputHash
        )
    }
}

extension Summary {
    /// What identifies the slot a summary occupies, so its versions can be found after the
    /// row itself was deleted and recreated: the recording for a session summary, otherwise
    /// the period type, its start and the journal.
    public var versionKey: String {
        Summary.versionKey(periodType: periodType, periodStart: periodStart, sessionId: sessionId, category: category)
    }

    public static func versionKey(periodType: PeriodType, periodStart: Date, sessionId: UUID?, category: SessionCategory?) -> String {
        if periodType == .session, let sessionId {
            return "session:\(sessionId.uuidString)"
        }
        return "\(periodType.rawValue):\(Int(periodStart.timeIntervalSince1970)):\(category?.rawValue ?? "all")"
    }
}
