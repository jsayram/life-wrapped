// =============================================================================
// Widget Data - Data model for widget display
// =============================================================================

import Foundation

// MARK: - Widget Data

/// Data structure for widget display, stored in App Group UserDefaults
public struct WidgetData: Codable, Sendable, Equatable {
    public let streakDays: Int
    public let todayWords: Int
    public let todayMinutes: Int
    public let todayEntries: Int
    public let lastEntryTime: Date?
    public let isStreakAtRisk: Bool
    public let weeklyWords: Int
    public let weeklyMinutes: Int
    public let lastUpdated: Date
    
    public init(
        streakDays: Int = 0,
        todayWords: Int = 0,
        todayMinutes: Int = 0,
        todayEntries: Int = 0,
        lastEntryTime: Date? = nil,
        isStreakAtRisk: Bool = false,
        weeklyWords: Int = 0,
        weeklyMinutes: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.streakDays = streakDays
        self.todayWords = todayWords
        self.todayMinutes = todayMinutes
        self.todayEntries = todayEntries
        self.lastEntryTime = lastEntryTime
        self.isStreakAtRisk = isStreakAtRisk
        self.weeklyWords = weeklyWords
        self.weeklyMinutes = weeklyMinutes
        self.lastUpdated = lastUpdated
    }
    
    public static let empty = WidgetData()
    
    public static let placeholder = WidgetData(
        streakDays: 7,
        todayWords: 350,
        todayMinutes: 5,
        todayEntries: 2,
        lastEntryTime: Date().addingTimeInterval(-3600),
        isStreakAtRisk: false,
        weeklyWords: 2450,
        weeklyMinutes: 35,
        lastUpdated: Date()
    )
}

// MARK: - Widget Data Factory

extension WidgetData {
    
    /// Creates widget data from rollup statistics
    public static func from(
        streakDays: Int,
        todayWordCount: Int,
        todayDuration: TimeInterval,
        todayEntryCount: Int,
        lastEntryDate: Date?,
        weeklyWordCount: Int,
        weeklyDuration: TimeInterval
    ) -> WidgetData {
        // Check if streak is at risk (no entry today and it's past noon)
        let calendar = Calendar.current
        let now = Date()
        let isAfternoon = calendar.component(.hour, from: now) >= 12
        let hasEntryToday = todayEntryCount > 0
        let isStreakAtRisk = streakDays > 0 && !hasEntryToday && isAfternoon
        
        return WidgetData(
            streakDays: streakDays,
            todayWords: todayWordCount,
            todayMinutes: Int(todayDuration / 60),
            todayEntries: todayEntryCount,
            lastEntryTime: lastEntryDate,
            isStreakAtRisk: isStreakAtRisk,
            weeklyWords: weeklyWordCount,
            weeklyMinutes: Int(weeklyDuration / 60),
            lastUpdated: Date()
        )
    }
}
