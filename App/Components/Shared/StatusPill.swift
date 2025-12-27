// =============================================================================
// StatusPill.swift — Colored status badge component
// =============================================================================

import SwiftUI

// MARK: - Status Pill

struct StatusPill: View {
    let text: String
    let color: Color
    let icon: String?
    @Environment(\.colorScheme) var colorScheme
    
    init(text: String, color: Color, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RadialGradient(
                colors: [color.opacity(0.2), color.opacity(0.05)],
                center: .center,
                startRadius: 5,
                endRadius: 20
            )
        )
        .clipShape(Capsule())
    }
}
