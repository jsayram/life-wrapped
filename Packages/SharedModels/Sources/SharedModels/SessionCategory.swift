//
//  SessionCategory.swift
//  SharedModels
//
//  Created on 2025-12-27.
//

import Foundation

/// Category classification for recording sessions
public enum SessionCategory: String, Codable, Sendable, CaseIterable {
    case work
    case personal
    
    /// Display name for UI
    public var displayName: String {
        switch self {
        case .work: return "Work"
        case .personal: return "Personal"
        }
    }
    
    /// SF Symbol icon name
    public var systemImage: String {
        switch self {
        case .work: return "briefcase.fill"
        case .personal: return "person.fill"
        }
    }
    
    /// Hex color code for UI theming
    public var colorHex: String {
        switch self {
        case .work: return "#3B82F6"  // Blue
        case .personal: return "#A855F7"  // Purple
        }
    }
}
