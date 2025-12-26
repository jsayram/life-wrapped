// =============================================================================
// WiggleModifier.swift — Wiggle animation view modifier
// =============================================================================

import SwiftUI

// MARK: - Wiggle Animation Modifier

struct WiggleModifier: ViewModifier {
    @Binding var wiggle: Bool
    
    func body(content: Content) -> some View {
        content
            .offset(x: wiggle ? -8 : 0)
            .animation(
                wiggle ? Animation.default.repeatCount(3, autoreverses: true).speed(6) : .default,
                value: wiggle
            )
    }
}
