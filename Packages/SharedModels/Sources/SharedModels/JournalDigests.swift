// =============================================================================
// JournalDigests.swift — Choosing and refreshing a month's two journal digests
// =============================================================================
//
// Work and Personal each have their own digest per month. This file holds the
// decisions about them as plain functions so they can be tested: what to rebuild,
// what to delete, and what the app shows. SummaryCoordinator does the reading and
// writing.
//
// A month may also have an older digest that mixed both journals (stored without
// a category). It only bridges the gap until the month is rebuilt, and is deleted
// as soon as every journal with recordings has its own current digest.

import Foundation

public enum JournalDigests {

    /// What is stored for one journal's digest
    public struct Stored: Equatable, Sendable {
        public let inputHash: String?
        public let isFinal: Bool

        public init(inputHash: String?, isFinal: Bool) {
            self.inputHash = inputHash
            self.isFinal = isFinal
        }
    }

    /// What to do to bring a month up to date
    public struct Plan: Equatable, Sendable {
        /// Stored digest is current: use it as is
        public var reuse: [SessionCategory] = []
        /// Stored digest is current but the month has ended since: mark it final, no model needed
        public var markFinal: [SessionCategory] = []
        /// Missing or out of date: build with the model
        public var rebuild: [SessionCategory] = []
        /// Stored for a journal that no longer has recordings this month (moved or deleted)
        public var remove: [SessionCategory] = []
        /// Delete the month's older mixed digest once the steps above have succeeded
        public var removeLegacy = false

        public init() {}

        /// True when anything has to be written or deleted
        public var needsWork: Bool {
            !rebuild.isEmpty || !markFinal.isEmpty || !remove.isEmpty || removeLegacy
        }
    }

    /// Decide what to do for a month.
    /// - Parameters:
    ///   - currentHashes: input hash per journal that has recordings this month
    ///   - stored: what is saved per journal
    ///   - hasLegacy: whether an older mixed digest is still saved for the month
    ///   - monthEnded: whether the month is over, so digests should be final
    ///   - force: rebuild every journal with recordings, even if current
    public static func plan(
        currentHashes: [SessionCategory: String],
        stored: [SessionCategory: Stored],
        hasLegacy: Bool,
        monthEnded: Bool,
        force: Bool = false
    ) -> Plan {
        var plan = Plan()
        for journal in SessionCategory.allCases {
            guard let hash = currentHashes[journal] else {
                if stored[journal] != nil { plan.remove.append(journal) }
                continue
            }
            if !force, let existing = stored[journal], existing.inputHash == hash {
                if existing.isFinal == monthEnded {
                    plan.reuse.append(journal)
                } else {
                    plan.markFinal.append(journal)
                }
            } else {
                plan.rebuild.append(journal)
            }
        }
        // Once the plan is carried out, every journal with recordings has its own digest,
        // so the mixed one has nothing left to cover
        plan.removeLegacy = hasLegacy
        return plan
    }

    /// The month as the app shows it: both journals combined. A journal without a digest of its
    /// own uses its part of the older mixed digest, which only exists until the month is rebuilt.
    /// `usesLegacy` is true when any part came from that older digest.
    public static func combined(
        stored: [SessionCategory: MonthDigest],
        legacy: MonthDigest?
    ) -> (digest: MonthDigest, usesLegacy: Bool)? {
        var parts: [MonthDigest] = []
        var usesLegacy = false
        for journal in SessionCategory.allCases {
            if let digest = stored[journal] {
                parts.append(digest)
            } else if let slice = legacy?.slice(for: journal.itemFilter) {
                parts.append(slice)
                usesLegacy = true
            }
        }
        if let digest = MonthDigest.combining(parts) {
            return (digest, usesLegacy)
        }
        // A very old digest from before work and personal were tracked at all
        return legacy.map { ($0, true) }
    }
}
