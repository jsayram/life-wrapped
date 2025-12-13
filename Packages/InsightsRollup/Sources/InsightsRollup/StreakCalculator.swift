// =============================================================================
// InsightsRollup — Streak Calculator
// =============================================================================

import Foundation
import SharedModels

/// Calculates and tracks user streaks (consecutive days with activity)
public struct StreakCalculator: Sendable {
    
    // MARK: - Streak Types
    
    public struct StreakInfo: Sendable, Equatable {
        public let currentStreak: Int
        public let longestStreak: Int
        public let lastActivityDate: Date?
        public let streakStartDate: Date?
        public let isActiveToday: Bool
        
        public init(
            currentStreak: Int,
            longestStreak: Int,
            lastActivityDate: Date?,
            streakStartDate: Date?,
            isActiveToday: Bool
        ) {
            self.currentStreak = currentStreak
            self.longestStreak = longestStreak
            self.lastActivityDate = lastActivityDate
            self.streakStartDate = streakStartDate
            self.isActiveToday = isActiveToday
        }
        
        /// Status message for the streak
        public var statusMessage: String {
            if currentStreak == 0 {
                return "Start journaling to begin your streak!"
            } else if isActiveToday {
                return "🔥 \(currentStreak) day streak! Keep it going!"
            } else {
                return "⚠️ Journal today to keep your \(currentStreak) day streak!"
            }
        }
    }
    
    // MARK: - Calculation
    
    /// Calculate streak information from a list of activity dates
    /// - Parameter activityDates: Sorted array of dates with activity (newest first)
    /// - Returns: StreakInfo with current and longest streak details
    public static func calculateStreak(from activityDates: [Date]) -> StreakInfo {
        guard !activityDates.isEmpty else {
            return StreakInfo(
                currentStreak: 0,
                longestStreak: 0,
                lastActivityDate: nil,
                streakStartDate: nil,
                isActiveToday: false
            )
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Convert to unique days (start of day)
        let uniqueDays = Set(activityDates.map { calendar.startOfDay(for: $0) })
            .sorted(by: >)
        
        let isActiveToday = uniqueDays.contains(today)
        let lastActivityDate = uniqueDays.first
        
        // Calculate current streak
        var currentStreak = 0
        var checkDate = isActiveToday ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        
        for day in uniqueDays {
            if calendar.isDate(day, inSameDayAs: checkDate) {
                currentStreak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else if day < checkDate {
                // Gap found, streak broken
                break
            }
        }
        
        // If not active today or yesterday, streak is 0
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        if !isActiveToday && !uniqueDays.contains(yesterday) {
            currentStreak = 0
        }
        
        // Calculate longest streak
        var longestStreak = 0
        var tempStreak = 0
        var previousDay: Date? = nil
        
        for day in uniqueDays.sorted() { // Oldest first
            if let prev = previousDay {
                let expectedNext = calendar.date(byAdding: .day, value: 1, to: prev)!
                if calendar.isDate(day, inSameDayAs: expectedNext) {
                    tempStreak += 1
                } else {
                    longestStreak = max(longestStreak, tempStreak)
                    tempStreak = 1
                }
            } else {
                tempStreak = 1
            }
            previousDay = day
        }
        longestStreak = max(longestStreak, tempStreak)
        
        // Calculate streak start date
        let streakStartDate: Date? = currentStreak > 0 
            ? calendar.date(byAdding: .day, value: -(currentStreak - 1), to: isActiveToday ? today : yesterday)
            : nil
        
        return StreakInfo(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            lastActivityDate: lastActivityDate,
            streakStartDate: streakStartDate,
            isActiveToday: isActiveToday
        )
    }
    
    /// Check if streak will break soon (not active today)
    /// - Parameter streakInfo: Current streak information
    /// - Returns: True if user should be reminded to journal
    public static func streakAtRisk(_ streakInfo: StreakInfo) -> Bool {
        return streakInfo.currentStreak > 0 && !streakInfo.isActiveToday
    }
}
