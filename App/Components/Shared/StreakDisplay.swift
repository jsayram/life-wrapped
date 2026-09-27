// =============================================================================
// StreakDisplay.swift — Minimalist streak indicator
// =============================================================================

import SwiftUI

// MARK: - Streak Display (Minimal)

struct StreakDisplay: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame")
                .scaledFont(size: 14, weight: .regular)
                .foregroundStyle(AppTheme.textSecondary)
            Text("\(Text("\(streak)").fontWeight(.semibold).foregroundColor(AppTheme.textPrimary)) day streak")
                .foregroundStyle(AppTheme.textSecondary)
                .font(.footnote)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(streak) day streak")
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
