// =============================================================================
// InsightsRollup — Tests
// =============================================================================

import Foundation
import Testing
@testable import InsightsRollup
@testable import SharedModels

@Suite("Insights Error Tests")
struct InsightsErrorTests {
    
    @Test("Error descriptions are meaningful")
    func testErrorDescriptions() throws {
        let errors: [InsightsError] = [
            .noDataAvailable,
            .invalidDateRange(start: Date(), end: Date().addingTimeInterval(-3600)),
            .aggregationFailed("test reason"),
            .storageError("test error"),
            .insufficientData(minimumRequired: 10, actual: 3),
            .invalidBucketType("custom"),
            .calculationError("division by zero")
        ]
        
        for error in errors {
            let description = error.errorDescription
            #expect(description != nil)
            #expect(description!.isEmpty == false)
        }
    }
    
    @Test("Insufficient data error includes counts")
    func testInsufficientDataError() throws {
        let error = InsightsError.insufficientData(minimumRequired: 50, actual: 10)
        let description = error.errorDescription!
        
        #expect(description.contains("50"))
        #expect(description.contains("10"))
    }
    
    @Test("Invalid bucket type error includes type name")
    func testInvalidBucketTypeError() throws {
        let error = InsightsError.invalidBucketType("hourly-custom")
        let description = error.errorDescription!
        
        #expect(description.contains("hourly-custom"))
    }
}

@Suite("Period Comparison Tests")
struct PeriodComparisonTests {
    
    @Test("Comparison detects improvement")
    func testImprovementDetection() throws {
        let comparison = PeriodComparison(
            period1Words: 100,
            period2Words: 150,
            period1Speaking: 60.0,
            period2Speaking: 90.0,
            period1Entries: 5,
            period2Entries: 8,
            wordChangePercent: 50.0,
            speakingChangePercent: 50.0,
            entryChangePercent: 60.0
        )
        
        #expect(comparison.isImproving == true)
    }
    
    @Test("Comparison detects decline")
    func testDeclineDetection() throws {
        let comparison = PeriodComparison(
            period1Words: 150,
            period2Words: 100,
            period1Speaking: 90.0,
            period2Speaking: 60.0,
            period1Entries: 8,
            period2Entries: 5,
            wordChangePercent: -33.3,
            speakingChangePercent: -33.3,
            entryChangePercent: -37.5
        )
        
        #expect(comparison.isImproving == false)
    }
    
    @Test("Trend description for significant increase")
    func testSignificantIncrease() throws {
        let comparison = PeriodComparison(
            period1Words: 100,
            period2Words: 150,
            period1Speaking: 60.0,
            period2Speaking: 90.0,
            period1Entries: 5,
            period2Entries: 8,
            wordChangePercent: 50.0,
            speakingChangePercent: 50.0,
            entryChangePercent: 60.0
        )
        
        #expect(comparison.trendDescription == "Significantly more active")
    }
    
    @Test("Trend description for significant decrease")
    func testSignificantDecrease() throws {
        let comparison = PeriodComparison(
            period1Words: 150,
            period2Words: 50,
            period1Speaking: 90.0,
            period2Speaking: 30.0,
            period1Entries: 8,
            period2Entries: 2,
            wordChangePercent: -66.7,
            speakingChangePercent: -66.7,
            entryChangePercent: -75.0
        )
        
        #expect(comparison.trendDescription == "Significantly less active")
    }
    
    @Test("Trend description for stable activity")
    func testStableActivity() throws {
        let comparison = PeriodComparison(
            period1Words: 100,
            period2Words: 102,
            period1Speaking: 60.0,
            period2Speaking: 61.0,
            period1Entries: 5,
            period2Entries: 5,
            wordChangePercent: 2.0,
            speakingChangePercent: 1.7,
            entryChangePercent: 0.0
        )
        
        #expect(comparison.trendDescription == "About the same")
    }
}

@Suite("Bucket Calculation Tests")
struct BucketCalculationTests {
    
    @Test("Daily bucket covers 24 hours")
    func testDailyBucket() throws {
        let calendar = Calendar.current
        let date = Date()
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let hours = calendar.dateComponents([.hour], from: startOfDay, to: endOfDay).hour
        #expect(hours == 24)
    }
    
    @Test("Weekly bucket covers 7 days")
    func testWeeklyBucket() throws {
        let calendar = Calendar.current
        let date = Date()
        let weekday = calendar.component(.weekday, from: date)
        let daysToSubtract = weekday - 1
        let weekStart = calendar.date(byAdding: .day, value: -daysToSubtract, to: date)!
        let start = calendar.startOfDay(for: weekStart)
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        
        let days = calendar.dateComponents([.day], from: start, to: end).day
        #expect(days == 7)
    }
    
    @Test("Monthly bucket starts on first day")
    func testMonthlyBucket() throws {
        let calendar = Calendar.current
        let date = Date()
        let components = calendar.dateComponents([.year, .month], from: date)
        let monthStart = calendar.date(from: components)!
        
        let dayOfMonth = calendar.component(.day, from: monthStart)
        #expect(dayOfMonth == 1)
    }
    
    @Test("Hourly bucket covers 60 minutes")
    func testHourlyBucket() throws {
        let calendar = Calendar.current
        let date = Date()
        let hourStart = calendar.date(bySetting: .minute, value: 0, of: date)!
        let cleanStart = calendar.date(bySetting: .second, value: 0, of: hourStart)!
        let hourEnd = calendar.date(byAdding: .hour, value: 1, to: cleanStart)!
        
        let minutes = calendar.dateComponents([.minute], from: cleanStart, to: hourEnd).minute
        #expect(minutes == 60)
    }
}

@Suite("InsightsRollup Model Tests")
struct InsightsRollupModelTests {
    
    @Test("Words per minute calculation")
    func testWordsPerMinute() throws {
        let rollup = InsightsRollup(
            bucketType: .hour,
            bucketStart: Date(),
            bucketEnd: Date().addingTimeInterval(3600),
            wordCount: 150,
            speakingSeconds: 60.0,
            segmentCount: 5
        )
        
        // 150 words in 60 seconds = 150 wpm
        #expect(rollup.wordsPerMinute == 150.0)
    }
    
    @Test("Words per minute handles zero speaking time")
    func testWordsPerMinuteZero() throws {
        let rollup = InsightsRollup(
            bucketType: .hour,
            bucketStart: Date(),
            bucketEnd: Date().addingTimeInterval(3600),
            wordCount: 100,
            speakingSeconds: 0.0,
            segmentCount: 0
        )
        
        #expect(rollup.wordsPerMinute == 0.0)
    }
    
    @Test("All period types are iterable")
    func testPeriodTypesIterable() throws {
        let types = PeriodType.allCases
        
        #expect(types.count == 7)
        #expect(types.contains(.session))
        #expect(types.contains(.hour))
        #expect(types.contains(.day))
        #expect(types.contains(.week))
        #expect(types.contains(.month))
        #expect(types.contains(.year))
        #expect(types.contains(.yearWrap))
    }
    
    @Test("Period type display names are meaningful")
    func testPeriodTypeDisplayNames() throws {
        #expect(PeriodType.hour.displayName == "Hour")
        #expect(PeriodType.day.displayName == "Day")
        #expect(PeriodType.week.displayName == "Week")
        #expect(PeriodType.month.displayName == "Month")
    }
}

@Suite("Streak Calculator Tests")
struct StreakCalculatorTests {
    
    @Test("Empty dates returns zero streak")
    func testEmptyDates() throws {
        let streakInfo = StreakCalculator.calculateStreak(from: [])
        
        #expect(streakInfo.currentStreak == 0)
        #expect(streakInfo.longestStreak == 0)
        #expect(streakInfo.lastActivityDate == nil)
        #expect(streakInfo.isActiveToday == false)
    }
    
    @Test("Today only gives streak of 1")
    func testTodayOnly() throws {
        let today = Date()
        let streakInfo = StreakCalculator.calculateStreak(from: [today])
        
        #expect(streakInfo.currentStreak == 1)
        #expect(streakInfo.longestStreak == 1)
        #expect(streakInfo.isActiveToday == true)
    }
    
    @Test("Streak at risk when not active today")
    func testStreakAtRisk() throws {
        let streakInfo = StreakCalculator.StreakInfo(
            currentStreak: 5,
            longestStreak: 5,
            lastActivityDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
            streakStartDate: Calendar.current.date(byAdding: .day, value: -5, to: Date()),
            isActiveToday: false
        )
        
        #expect(StreakCalculator.streakAtRisk(streakInfo) == true)
    }
    
    @Test("Streak not at risk when active today")
    func testStreakNotAtRisk() throws {
        let streakInfo = StreakCalculator.StreakInfo(
            currentStreak: 5,
            longestStreak: 5,
            lastActivityDate: Date(),
            streakStartDate: Calendar.current.date(byAdding: .day, value: -4, to: Date()),
            isActiveToday: true
        )
        
        #expect(StreakCalculator.streakAtRisk(streakInfo) == false)
    }
    
    @Test("Status message for active streak")
    func testStatusMessageActive() throws {
        let streakInfo = StreakCalculator.StreakInfo(
            currentStreak: 7,
            longestStreak: 7,
            lastActivityDate: Date(),
            streakStartDate: Calendar.current.date(byAdding: .day, value: -6, to: Date()),
            isActiveToday: true
        )
        
        #expect(streakInfo.statusMessage.contains("7 day streak"))
    }
}

@Suite("Goal Tracker Tests")
struct GoalTrackerTests {
    
    @Test("Default goals have expected values")
    func testDefaultGoals() throws {
        let goals = GoalTracker.createDefaultGoals()
        
        #expect(goals.count == 6)
        
        let dailyWords = goals.first { $0.type == .dailyWords }
        #expect(dailyWords?.target == 500)
        
        let weeklyEntries = goals.first { $0.type == .weeklyEntries }
        #expect(weeklyEntries?.target == 5)
    }
    
    @Test("Goal type display names are meaningful")
    func testGoalTypeDisplayNames() throws {
        #expect(GoalTracker.GoalType.dailyWords.displayName == "Daily Words")
        #expect(GoalTracker.GoalType.weeklyMinutes.displayName == "Weekly Speaking Time")
    }
    
    @Test("Goal type units are correct")
    func testGoalTypeUnits() throws {
        #expect(GoalTracker.GoalType.dailyWords.unit == "words")
        #expect(GoalTracker.GoalType.dailyMinutes.unit == "minutes")
        #expect(GoalTracker.GoalType.dailyEntries.unit == "entries")
    }
    
    @Test("Progress calculation for words goal")
    func testWordsProgress() throws {
        let goal = GoalTracker.Goal(type: .dailyWords, target: 500)
        let progress = GoalTracker.calculateProgress(
            goal: goal,
            wordCount: 250,
            speakingSeconds: 60,
            entryCount: 2
        )
        
        #expect(progress.current == 250)
        #expect(progress.progressPercent == 50)
        #expect(progress.isComplete == false)
        #expect(progress.remaining == 250)
    }
    
    @Test("Progress calculation for completed goal")
    func testCompletedProgress() throws {
        let goal = GoalTracker.Goal(type: .dailyEntries, target: 3)
        let progress = GoalTracker.calculateProgress(
            goal: goal,
            wordCount: 500,
            speakingSeconds: 300,
            entryCount: 5
        )
        
        #expect(progress.isComplete == true)
        #expect(progress.progressPercent == 100)
        #expect(progress.progressEmoji == "🏆")
    }
    
    @Test("Progress emoji reflects progress")
    func testProgressEmoji() throws {
        let goal = GoalTracker.Goal(type: .dailyWords, target: 100)
        
        let progress10 = GoalTracker.calculateProgress(goal: goal, wordCount: 10, speakingSeconds: 0, entryCount: 0)
        #expect(progress10.progressEmoji == "🌱")
        
        let progress30 = GoalTracker.calculateProgress(goal: goal, wordCount: 30, speakingSeconds: 0, entryCount: 0)
        #expect(progress30.progressEmoji == "🌿")
        
        let progress60 = GoalTracker.calculateProgress(goal: goal, wordCount: 60, speakingSeconds: 0, entryCount: 0)
        #expect(progress60.progressEmoji == "🌳")
        
        let progress80 = GoalTracker.calculateProgress(goal: goal, wordCount: 80, speakingSeconds: 0, entryCount: 0)
        #expect(progress80.progressEmoji == "🔥")
    }
    
    @Test("Daily vs weekly goal detection")
    func testDailyVsWeekly() throws {
        #expect(GoalTracker.GoalType.dailyWords.isDaily == true)
        #expect(GoalTracker.GoalType.weeklyWords.isDaily == false)
    }
}
