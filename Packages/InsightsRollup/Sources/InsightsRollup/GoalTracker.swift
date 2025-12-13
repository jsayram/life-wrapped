// =============================================================================
// InsightsRollup — Goal Tracker
// =============================================================================

import Foundation

/// Tracks user goals and progress
public struct GoalTracker: Sendable {
    
    // MARK: - Goal Types
    
    public enum GoalType: String, Codable, Sendable, CaseIterable {
        case dailyWords
        case dailyMinutes
        case dailyEntries
        case weeklyWords
        case weeklyMinutes
        case weeklyEntries
        
        public var displayName: String {
            switch self {
            case .dailyWords: return "Daily Words"
            case .dailyMinutes: return "Daily Speaking Time"
            case .dailyEntries: return "Daily Entries"
            case .weeklyWords: return "Weekly Words"
            case .weeklyMinutes: return "Weekly Speaking Time"
            case .weeklyEntries: return "Weekly Entries"
            }
        }
        
        public var unit: String {
            switch self {
            case .dailyWords, .weeklyWords: return "words"
            case .dailyMinutes, .weeklyMinutes: return "minutes"
            case .dailyEntries, .weeklyEntries: return "entries"
            }
        }
        
        public var isDaily: Bool {
            switch self {
            case .dailyWords, .dailyMinutes, .dailyEntries: return true
            case .weeklyWords, .weeklyMinutes, .weeklyEntries: return false
            }
        }
    }
    
    public struct Goal: Sendable, Codable, Identifiable {
        public let id: UUID
        public let type: GoalType
        public let target: Double
        public let createdAt: Date
        
        public init(id: UUID = UUID(), type: GoalType, target: Double, createdAt: Date = Date()) {
            self.id = id
            self.type = type
            self.target = target
            self.createdAt = createdAt
        }
    }
    
    public struct GoalProgress: Sendable {
        public let goal: Goal
        public let current: Double
        public let progressPercent: Double
        public let isComplete: Bool
        public let remaining: Double
        
        public init(goal: Goal, current: Double) {
            self.goal = goal
            self.current = current
            self.progressPercent = min(100, (current / goal.target) * 100)
            self.isComplete = current >= goal.target
            self.remaining = max(0, goal.target - current)
        }
        
        public var statusMessage: String {
            if isComplete {
                return "🎉 Goal achieved! You reached \(Int(current)) \(goal.type.unit)!"
            } else {
                return "\(Int(remaining)) \(goal.type.unit) to go (\(Int(progressPercent))% complete)"
            }
        }
        
        public var progressEmoji: String {
            switch progressPercent {
            case 0..<25: return "🌱"
            case 25..<50: return "🌿"
            case 50..<75: return "🌳"
            case 75..<100: return "🔥"
            default: return "🏆"
            }
        }
    }
    
    // MARK: - Default Goals
    
    public static let defaultDailyWordGoal: Double = 500
    public static let defaultDailyMinuteGoal: Double = 5
    public static let defaultDailyEntryGoal: Double = 1
    public static let defaultWeeklyWordGoal: Double = 3500
    public static let defaultWeeklyMinuteGoal: Double = 30
    public static let defaultWeeklyEntryGoal: Double = 5
    
    /// Create a set of default goals
    public static func createDefaultGoals() -> [Goal] {
        [
            Goal(type: .dailyWords, target: defaultDailyWordGoal),
            Goal(type: .dailyMinutes, target: defaultDailyMinuteGoal),
            Goal(type: .dailyEntries, target: defaultDailyEntryGoal),
            Goal(type: .weeklyWords, target: defaultWeeklyWordGoal),
            Goal(type: .weeklyMinutes, target: defaultWeeklyMinuteGoal),
            Goal(type: .weeklyEntries, target: defaultWeeklyEntryGoal)
        ]
    }
    
    // MARK: - Progress Calculation
    
    /// Calculate progress towards a goal
    public static func calculateProgress(
        goal: Goal,
        wordCount: Int,
        speakingSeconds: Double,
        entryCount: Int
    ) -> GoalProgress {
        let current: Double
        
        switch goal.type {
        case .dailyWords, .weeklyWords:
            current = Double(wordCount)
        case .dailyMinutes, .weeklyMinutes:
            current = speakingSeconds / 60.0
        case .dailyEntries, .weeklyEntries:
            current = Double(entryCount)
        }
        
        return GoalProgress(goal: goal, current: current)
    }
}
