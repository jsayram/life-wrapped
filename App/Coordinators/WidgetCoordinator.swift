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
            
            // Create widget data
            let widgetData = WidgetData(
                streakDays: streakInfo.currentStreak,
                todayWords: todayWordCount,
                todayMinutes: Int(todayMinutes),
                todayEntries: todayEntries,
                lastEntryTime: activityDates.first,
                isStreakAtRisk: StreakCalculator.streakAtRisk(streakInfo),
                lastUpdated: Date()
            )
            
            widgetDataManager.writeWidgetData(widgetData)
            
            // Tell WidgetKit to refresh all widget timelines immediately
            WidgetCenter.shared.reloadAllTimelines()
            
            print("✅ [WidgetCoordinator] Updated widget data: streak=\(streakInfo.currentStreak), words=\(todayWordCount), sessions=\(todayEntries)")
            
        } catch {
            print("❌ [WidgetCoordinator] Failed to update widget data: \(error)")
        }
    }
}
