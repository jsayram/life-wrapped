// =============================================================================
// Extensions.swift — SwiftUI and Foundation extensions
// =============================================================================

import SwiftUI
import Foundation

// MARK: - Color Hex Extension

extension Color {
    /// Initialize Color from hex string (e.g., "#8B5CF6" or "8B5CF6")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let r, g, b, a: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 6: // RGB (24-bit)
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8: // ARGB (32-bit)
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - UserDefaults Extension for Rollup Settings

extension UserDefaults {
    var autoChunkDuration: TimeInterval {
        get {
            let value = double(forKey: "autoChunkDuration")
            return value > 0 ? value : 30  // Default 30s for fast processing
        }
        set { set(newValue, forKey: "autoChunkDuration") }
    }
    
    var rollupDateFormat: String {
        get { string(forKey: "rollupDateFormat") ?? "MMM d, yyyy" }
        set { set(newValue, forKey: "rollupDateFormat") }
    }
    
    var rollupTimeFormat: String {
        get { string(forKey: "rollupTimeFormat") ?? "h:mm a" }
        set { set(newValue, forKey: "rollupTimeFormat") }
    }
    
    var lastExportFormat: String? {
        get { string(forKey: "lastExportFormat") }
        set {
            if let value = newValue {
                set(value, forKey: "lastExportFormat")
            } else {
                removeObject(forKey: "lastExportFormat")
            }
        }
    }
}

// MARK: - Array Extensions

extension Array where Element: Hashable {
    var uniqueCount: Int {
        return Set(self).count
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
