// =============================================================================
// Transcription — Statistics Tracker
// =============================================================================

import Foundation

/// Tracks transcription statistics and performance metrics
public actor TranscriptionStatistics {
    
    // MARK: - Statistics
    
    private(set) var totalChunksProcessed: Int = 0
    private(set) var totalSegmentsCreated: Int = 0
    private(set) var totalDuration: TimeInterval = 0
    private(set) var failureCount: Int = 0
    private(set) var successCount: Int = 0
    
    // MARK: - Public Methods
    
    /// Record a successful transcription
    public func recordSuccess(segmentCount: Int, duration: TimeInterval) {
        totalChunksProcessed += 1
        totalSegmentsCreated += segmentCount
        totalDuration += duration
        successCount += 1
    }
    
    /// Record a failed transcription
    public func recordFailure() {
        totalChunksProcessed += 1
        failureCount += 1
    }
    
    /// Get success rate
    public var successRate: Double {
        guard totalChunksProcessed > 0 else { return 0.0 }
        return Double(successCount) / Double(totalChunksProcessed)
    }
    
    /// Get average segments per chunk
    public var averageSegmentsPerChunk: Double {
        guard successCount > 0 else { return 0.0 }
        return Double(totalSegmentsCreated) / Double(successCount)
    }
    
    /// Get average processing time per chunk
    public var averageProcessingTime: TimeInterval {
        guard successCount > 0 else { return 0.0 }
        return totalDuration / Double(successCount)
    }
    
    /// Reset all statistics
    public func reset() {
        totalChunksProcessed = 0
        totalSegmentsCreated = 0
        totalDuration = 0
        failureCount = 0
        successCount = 0
    }
    
    /// Get statistics summary
    public func getSummary() -> StatisticsSummary {
        StatisticsSummary(
            totalChunksProcessed: totalChunksProcessed,
            totalSegmentsCreated: totalSegmentsCreated,
            totalDuration: totalDuration,
            successCount: successCount,
            failureCount: failureCount,
            successRate: successRate,
            averageSegmentsPerChunk: averageSegmentsPerChunk,
            averageProcessingTime: averageProcessingTime
        )
    }
}

/// Summary of transcription statistics
public struct StatisticsSummary: Sendable {
    public let totalChunksProcessed: Int
    public let totalSegmentsCreated: Int
    public let totalDuration: TimeInterval
    public let successCount: Int
    public let failureCount: Int
    public let successRate: Double
    public let averageSegmentsPerChunk: Double
    public let averageProcessingTime: TimeInterval
}
