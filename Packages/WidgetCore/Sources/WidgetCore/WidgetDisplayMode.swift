// =============================================================================
// Widget Display Mode - Configuration options for widgets
// =============================================================================

import Foundation

// MARK: - Widget Display Mode

/// Configurable display modes for the widget
public enum WidgetDisplayMode: String, CaseIterable, Sendable, Codable {
    case overview = "Overview"
    case streak = "Streak Focus"
    case weekly = "Weekly Stats"
    
    public var displayName: String { rawValue }
    
    public var description: String {
        switch self {
        case .overview:
            return "Show all key metrics at a glance"
        case .streak:
            return "Focus on your journaling streak"
        case .weekly:
            return "View your weekly statistics"
        }
    }
    
    public var icon: String {
        switch self {
        case .overview: return "rectangle.grid.2x2"
        case .streak: return "flame.fill"
        case .weekly: return "calendar"
        }
    }
}
