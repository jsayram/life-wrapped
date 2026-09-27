// =============================================================================
// TimeRange.swift — Time period selector enum
// =============================================================================

import Foundation

enum TimeRange: String, CaseIterable, Identifiable {
    case yesterday = "Yesterday"
    case today = "Today"
    case month = "Month"
    case allTime = "Year"
    
    var id: String { rawValue }
    
    var fullName: String {
        switch self {
        case .yesterday: return "Yesterday"
        case .today: return "Today"
        case .month: return "This Month"
        case .allTime: return "This Year"
        }
    }
}
