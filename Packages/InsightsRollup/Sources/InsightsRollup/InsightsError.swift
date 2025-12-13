// =============================================================================
// InsightsRollup — Error Types
// =============================================================================

import Foundation

/// Errors that can occur during insights operations
public enum InsightsError: LocalizedError, Sendable {
    case noDataAvailable
    case invalidDateRange(start: Date, end: Date)
    case aggregationFailed(String)
    case storageError(String)
    case insufficientData(minimumRequired: Int, actual: Int)
    case invalidBucketType(String)
    case calculationError(String)
    
    public var errorDescription: String? {
        switch self {
        case .noDataAvailable:
            return "No data available for insights calculation."
            
        case .invalidDateRange(let start, let end):
            return "Invalid date range: start (\(start)) must be before end (\(end))."
            
        case .aggregationFailed(let reason):
            return "Aggregation failed: \(reason)"
            
        case .storageError(let reason):
            return "Storage error during insights calculation: \(reason)"
            
        case .insufficientData(let minimum, let actual):
            return "Insufficient data for insights. Minimum \(minimum) entries required, got \(actual)."
            
        case .invalidBucketType(let type):
            return "Invalid bucket type: \(type)"
            
        case .calculationError(let reason):
            return "Calculation error: \(reason)"
        }
    }
}
