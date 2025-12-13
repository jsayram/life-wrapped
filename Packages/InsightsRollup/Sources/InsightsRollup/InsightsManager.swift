// =============================================================================
// InsightsRollup — Manager
// =============================================================================

import Foundation
import SharedModels
import Storage

/// Actor that manages insights generation and rollup aggregation
/// Calculates speaking statistics across different time periods
public actor InsightsManager {
    
    // MARK: - Properties
    
    private let storage: DatabaseManager
    
    // MARK: - Statistics
    
    private(set) var rollupsGenerated: Int = 0
    private(set) var lastCalculationTime: TimeInterval = 0
    
    // MARK: - Initialization
    
    public init(storage: DatabaseManager) {
        self.storage = storage
    }
    
    // MARK: - Rollup Generation
    
    /// Generate an insights rollup for a specific time bucket
    /// - Parameters:
    ///   - bucketType: The type of period (hour, day, week, month)
    ///   - date: A date within the bucket to calculate
    /// - Returns: Generated InsightsRollup object
    public func generateRollup(
        bucketType: PeriodType,
        for date: Date
    ) async throws -> InsightsRollup {
        let startTime = Date()
        
        // Calculate bucket boundaries
        let (bucketStart, bucketEnd) = calculateBucketBoundaries(for: date, bucketType: bucketType)
        
        // Validate date range
        guard bucketStart < bucketEnd else {
            throw InsightsError.invalidDateRange(start: bucketStart, end: bucketEnd)
        }
        
        // Fetch transcript segments for the bucket period
        let segments = try await storage.getTranscriptSegments(from: bucketStart, to: bucketEnd)
        
        // Calculate aggregated metrics
        let wordCount = segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let speakingSeconds = segments.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
        let segmentCount = segments.count
        
        // Create rollup
        let rollup = InsightsRollup(
            bucketType: bucketType,
            bucketStart: bucketStart,
            bucketEnd: bucketEnd,
            wordCount: wordCount,
            speakingSeconds: speakingSeconds,
            segmentCount: segmentCount
        )
        
        // Save to storage
        do {
            try await storage.insertRollup(rollup)
        } catch {
            throw InsightsError.storageError(error.localizedDescription)
        }
        
        // Update statistics
        lastCalculationTime = Date().timeIntervalSince(startTime)
        rollupsGenerated += 1
        
        return rollup
    }
    
    /// Generate hourly rollup for a specific hour
    public func generateHourlyRollup(for date: Date) async throws -> InsightsRollup {
        try await generateRollup(bucketType: .hour, for: date)
    }
    
    /// Generate daily rollup for a specific day
    public func generateDailyRollup(for date: Date) async throws -> InsightsRollup {
        try await generateRollup(bucketType: .day, for: date)
    }
    
    /// Generate weekly rollup for the week containing the date
    public func generateWeeklyRollup(for date: Date) async throws -> InsightsRollup {
        try await generateRollup(bucketType: .week, for: date)
    }
    
    /// Generate monthly rollup for the month containing the date
    public func generateMonthlyRollup(for date: Date) async throws -> InsightsRollup {
        try await generateRollup(bucketType: .month, for: date)
    }
    
    // MARK: - Batch Rollup Generation
    
    /// Generate all rollup types for a given date
    /// - Parameter date: The date to generate rollups for
    /// - Returns: Array of generated rollups (hour, day, week, month)
    public func generateAllRollups(for date: Date) async throws -> [InsightsRollup] {
        var rollups: [InsightsRollup] = []
        
        for bucketType in PeriodType.allCases {
            do {
                let rollup = try await generateRollup(bucketType: bucketType, for: date)
                rollups.append(rollup)
            } catch InsightsError.noDataAvailable {
                // Skip if no data for this bucket type
                continue
            }
        }
        
        return rollups
    }
    
    /// Generate rollups for a date range
    /// - Parameters:
    ///   - bucketType: Type of rollup to generate
    ///   - startDate: Start of the range
    ///   - endDate: End of the range
    ///   - onProgress: Optional progress callback
    /// - Returns: Number of rollups generated
    public func generateRollupsForRange(
        bucketType: PeriodType,
        from startDate: Date,
        to endDate: Date,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> Int {
        guard startDate < endDate else {
            throw InsightsError.invalidDateRange(start: startDate, end: endDate)
        }
        
        let calendar = Calendar.current
        var dates: [Date] = []
        var currentDate = startDate
        
        // Generate list of bucket start dates
        while currentDate < endDate {
            dates.append(currentDate)
            currentDate = nextBucketStart(after: currentDate, bucketType: bucketType, calendar: calendar)
        }
        
        var successCount = 0
        for (index, date) in dates.enumerated() {
            do {
                _ = try await generateRollup(bucketType: bucketType, for: date)
                successCount += 1
            } catch {
                // Continue on failure
            }
            onProgress?(index + 1, dates.count)
        }
        
        return successCount
    }
    
    // MARK: - Analytics Queries
    
    /// Get total speaking time for a date range
    public func getTotalSpeakingTime(from startDate: Date, to endDate: Date) async throws -> TimeInterval {
        let segments = try await storage.getTranscriptSegments(from: startDate, to: endDate)
        return segments.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
    }
    
    /// Get total word count for a date range
    public func getTotalWordCount(from startDate: Date, to endDate: Date) async throws -> Int {
        let segments = try await storage.getTranscriptSegments(from: startDate, to: endDate)
        return segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
    
    /// Get average words per day for a date range
    public func getAverageWordsPerDay(from startDate: Date, to endDate: Date) async throws -> Double {
        let segments = try await storage.getTranscriptSegments(from: startDate, to: endDate)
        let totalWords = segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
        
        let calendar = Calendar.current
        let days = max(1, calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
        
        return Double(totalWords) / Double(days)
    }
    
    /// Get speaking trends comparing two periods
    public func comparePeriods(
        period1Start: Date, period1End: Date,
        period2Start: Date, period2End: Date
    ) async throws -> PeriodComparison {
        let segments1 = try await storage.getTranscriptSegments(from: period1Start, to: period1End)
        let segments2 = try await storage.getTranscriptSegments(from: period2Start, to: period2End)
        
        let words1 = segments1.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let words2 = segments2.reduce(0) { $0 + $1.text.split(separator: " ").count }
        
        let speaking1 = segments1.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
        let speaking2 = segments2.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
        
        let entries1 = segments1.count
        let entries2 = segments2.count
        
        return PeriodComparison(
            period1Words: words1,
            period2Words: words2,
            period1Speaking: speaking1,
            period2Speaking: speaking2,
            period1Entries: entries1,
            period2Entries: entries2,
            wordChangePercent: calculatePercentChange(from: words1, to: words2),
            speakingChangePercent: calculatePercentChange(from: speaking1, to: speaking2),
            entryChangePercent: calculatePercentChange(from: entries1, to: entries2)
        )
    }
    
    /// Get statistics summary
    public func getStatistics() -> (rollupsGenerated: Int, lastCalculationTime: TimeInterval) {
        (rollupsGenerated, lastCalculationTime)
    }
    
    /// Reset statistics
    public func resetStatistics() {
        rollupsGenerated = 0
        lastCalculationTime = 0
    }
    
    // MARK: - Private Helpers
    
    private func calculateBucketBoundaries(for date: Date, bucketType: PeriodType) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        
        switch bucketType {
        case .hour:
            let start = calendar.date(bySetting: .minute, value: 0, of: date) ?? date
            let cleanStart = calendar.date(bySetting: .second, value: 0, of: start) ?? start
            let end = calendar.date(byAdding: .hour, value: 1, to: cleanStart) ?? date
            return (cleanStart, end)
            
        case .day:
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
            return (start, end)
            
        case .week:
            let weekday = calendar.component(.weekday, from: date)
            let daysToSubtract = weekday - 1
            let weekStart = calendar.date(byAdding: .day, value: -daysToSubtract, to: date) ?? date
            let start = calendar.startOfDay(for: weekStart)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? date
            return (start, end)
            
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            let start = calendar.date(from: components) ?? date
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? date
            return (start, end)
        }
    }
    
    private func nextBucketStart(after date: Date, bucketType: PeriodType, calendar: Calendar) -> Date {
        switch bucketType {
        case .hour:
            return calendar.date(byAdding: .hour, value: 1, to: date) ?? date
        case .day:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .week:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .month:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }
    
    private func calculatePercentChange<T: Numeric>(from oldValue: T, to newValue: T) -> Double where T: BinaryFloatingPoint {
        guard oldValue != 0 else { return newValue == 0 ? 0 : 100 }
        return Double((newValue - oldValue) / oldValue) * 100
    }
    
    private func calculatePercentChange(from oldValue: Int, to newValue: Int) -> Double {
        guard oldValue != 0 else { return newValue == 0 ? 0 : 100 }
        return Double(newValue - oldValue) / Double(oldValue) * 100
    }
}

// MARK: - Supporting Types

/// Comparison between two time periods
public struct PeriodComparison: Sendable {
    public let period1Words: Int
    public let period2Words: Int
    public let period1Speaking: TimeInterval
    public let period2Speaking: TimeInterval
    public let period1Entries: Int
    public let period2Entries: Int
    public let wordChangePercent: Double
    public let speakingChangePercent: Double
    public let entryChangePercent: Double
    
    /// Indicates if period2 shows improvement (more activity)
    public var isImproving: Bool {
        wordChangePercent > 0 || speakingChangePercent > 0 || entryChangePercent > 0
    }
    
    /// Human-readable trend description
    public var trendDescription: String {
        if wordChangePercent > 20 {
            return "Significantly more active"
        } else if wordChangePercent > 5 {
            return "Slightly more active"
        } else if wordChangePercent < -20 {
            return "Significantly less active"
        } else if wordChangePercent < -5 {
            return "Slightly less active"
        } else {
            return "About the same"
        }
    }
}
