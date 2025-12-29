// =============================================================================
// Widget Display Mode - Configuration options for widgets
// =============================================================================

import Foundation

// MARK: - Widget Display Mode

/// Configurable display modes for the widget (simplified)
public enum WidgetDisplayMode: String, CaseIterable, Sendable, Codable {
    case today = "Today"
    case record = "Record"
    case sessions = "Sessions"
    
    public var displayName: String { rawValue }
    
    public var description: String {
        switch self {
        case .today:
            return "View today's journaling stats"
        case .record:
            return "Quick record with category selection"
        case .sessions:
            return "View today's session count"
        }
    }
    
    public var icon: String {
        switch self {
        case .today: return "calendar"
        case .record: return "mic.fill"
        case .sessions: return "waveform"
        }
    }
}
