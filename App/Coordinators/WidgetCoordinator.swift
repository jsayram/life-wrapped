// =============================================================================
// WidgetCoordinator — Manages widget data updates and WidgetKit integration
// =============================================================================

import Foundation
import WidgetKit
import Storage
import WidgetCore
import InsightsRollup

/// Manages widget data synchronization and WidgetKit timeline updates
public final class WidgetCoordinator: Sendable {
    
    // MARK: - Dependencies
    
    private let databaseManager: DatabaseManager
    private let widgetDataManager: WidgetDataManager
    
    // MARK: - Initialization
    
    public init(databaseManager: DatabaseManager, widgetDataManager: WidgetDataManager) {
        self.databaseManager = databaseManager
        self.widgetDataManager = widgetDataManager
    }
    
    // MARK: - Widget Updates
    
    /// Update widget data with latest stats
    public func updateWidgetData() async {
        do {
            // Get latest daily rollups
            let dailyRollups = try await databaseManager.fetchRollups(bucketType: .day, limit: 365)
            
            // Extract dates with activity
            let activityDates = dailyRollups
                .filter { $0.segmentCount > 0 }
                .map { $0.bucketStart }
            
            let streakInfo = StreakCalculator.calculateStreak(from: activityDates)
            
            // Get today's stats
            let today = Calendar.current.startOfDay(for: Date())
            var todayWordCount = 0
            var todayMinutes = 0.0
            var todayEntries = 0
            
            if let todayRollup = dailyRollups.first,
               Calendar.current.isDate(todayRollup.bucketStart, inSameDayAs: today) {
                todayWordCount = todayRollup.wordCount
                todayMinutes = todayRollup.speakingSeconds / 60.0
                todayEntries = todayRollup.segmentCount
            }
            
            // Get weekly stats
            let calendar = Calendar.current
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
            let weeklyRollups = dailyRollups.filter { $0.bucketStart >= weekAgo }
            let weeklyWordCount = weeklyRollups.reduce(0) { $0 + $1.wordCount }
            let weeklyMinutes = weeklyRollups.reduce(0.0) { $0 + $1.speakingSeconds } / 60.0
            
            // Create widget data
            let widgetData = WidgetData(
                streakDays: streakInfo.currentStreak,
                todayWords: todayWordCount,
                todayMinutes: Int(todayMinutes),
                todayEntries: todayEntries,
                goalProgress: 0.0, // Can be enhanced with user goals
                lastEntryTime: activityDates.first,
                isStreakAtRisk: StreakCalculator.streakAtRisk(streakInfo),
                weeklyWords: weeklyWordCount,
                weeklyMinutes: Int(weeklyMinutes),
                lastUpdated: Date()
            )
            
            widgetDataManager.writeWidgetData(widgetData)
            
            // Tell WidgetKit to refresh widgets
            WidgetCenter.shared.reloadAllTimelines()
            
        } catch {
            print("Failed to update widget data: \(error)")
        }
    }
}
