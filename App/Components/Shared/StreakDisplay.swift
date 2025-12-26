// =============================================================================
// StreakDisplay.swift — Minimalist streak indicator
// =============================================================================

import SwiftUI

// MARK: - Streak Display (Minimal)

struct StreakDisplay: View {
    let streak: Int
    
    var body: some View {
        HStack(spacing: 8) {
            Text("🔥")
                .font(.system(size: 20))
            
            Text("\(streak) Day Streak")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.purple.opacity(0.9), AppTheme.magenta.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            if streak > 0 {
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(streakMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
    
    private var streakMessage: String {
        if streak == 0 {
            return ""
        } else if streak == 1 {
            return "Great start!"
        } else if streak < 7 {
            return "Building momentum!"
        } else if streak < 30 {
            return "Amazing!"
        } else {
            return "Incredible!"
        }
    }
}

// Legacy StreakCard kept for compatibility
struct StreakCard: View {
    let streak: Int
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        StreakDisplay(streak: streak)
    }
}
