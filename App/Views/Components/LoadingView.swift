import SwiftUI

/// Custom loading indicator with Apple Intelligence aesthetic
/// Features 12 rotating dots in outer circle + 3 pulsing concentric circles
struct LoadingView: View {
    enum Size {
        case small  // 60pt
        case medium // 120pt
        case large  // 180pt
        
        var diameter: CGFloat {
            switch self {
            case .small: return 60
            case .medium: return 120
            case .large: return 180
            }
        }
        
        var dotSize: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            case .large: return 8
            }
        }
    }
    
    let size: Size
    
    @State private var rotationDegrees: Double = 0
    @State private var pulse1Scale: CGFloat = 0.8
    @State private var pulse2Scale: CGFloat = 0.8
    @State private var pulse3Scale: CGFloat = 0.8
    
    var body: some View {
        ZStack {
            // Pulsing concentric circles (center)
            Circle()
                .strokeBorder(
                    RadialGradient(
                        colors: [AppTheme.purple, AppTheme.magenta.opacity(0.3)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.diameter * 0.15
                    ),
                    lineWidth: 2
                )
                .frame(width: size.diameter * 0.3, height: size.diameter * 0.3)
                .scaleEffect(pulse1Scale)
                .opacity(2.0 - pulse1Scale)
            
            Circle()
                .strokeBorder(
                    RadialGradient(
                        colors: [AppTheme.skyBlue, AppTheme.purple.opacity(0.3)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.diameter * 0.25
                    ),
                    lineWidth: 2
                )
                .frame(width: size.diameter * 0.5, height: size.diameter * 0.5)
                .scaleEffect(pulse2Scale)
                .opacity(2.0 - pulse2Scale)
            
            Circle()
                .strokeBorder(
                    RadialGradient(
                        colors: [AppTheme.darkPurple, AppTheme.skyBlue.opacity(0.3)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.diameter * 0.38
                    ),
                    lineWidth: 2
                )
                .frame(width: size.diameter * 0.75, height: size.diameter * 0.75)
                .scaleEffect(pulse3Scale)
                .opacity(2.0 - pulse3Scale)
            
            // Rotating dots (outer ring)
            ZStack {
                ForEach(0..<12) { index in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    colorForDot(index),
                                    colorForDot(index).opacity(0.5)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size.dotSize
                            )
                        )
                        .frame(width: size.dotSize, height: size.dotSize)
                        .offset(y: -size.diameter / 2 + size.dotSize)
                        .rotationEffect(.degrees(Double(index) * 30))
                        .opacity(opacityForDot(index))
                }
            }
            .rotationEffect(.degrees(rotationDegrees))
        }
        .frame(width: size.diameter, height: size.diameter)
        .onAppear {
            // Rotation animation for dots
            withAnimation(
                .linear(duration: 2.0)
                .repeatForever(autoreverses: false)
            ) {
                rotationDegrees = 360
            }
            
            // Pulse animations for concentric circles (staggered)
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
                pulse1Scale = 1.2
            }
            
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
                .delay(0.2)
            ) {
                pulse2Scale = 1.2
            }
            
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
                .delay(0.4)
            ) {
                pulse3Scale = 1.2
            }
        }
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
    
    // MARK: - Helpers
    
    /// Assign gradient colors to dots for rainbow effect
    private func colorForDot(_ index: Int) -> Color {
        let colors: [Color] = [
            AppTheme.darkPurple,  // 0
            AppTheme.purple,      // 1
            AppTheme.magenta,     // 2
            AppTheme.magenta,     // 3
            AppTheme.purple,      // 4
            AppTheme.skyBlue,     // 5
            AppTheme.skyBlue,     // 6
            AppTheme.purple,      // 7
            AppTheme.darkPurple,  // 8
            AppTheme.darkPurple,  // 9
            AppTheme.purple,      // 10
            AppTheme.magenta      // 11
        ]
        return colors[index % colors.count]
    }
    
    /// Create trailing fade effect for rotating dots
    private func opacityForDot(_ index: Int) -> Double {
        // Dots fade from 1.0 to 0.3 for trailing effect
        let normalizedIndex = Double(index) / 12.0
        return 1.0 - (normalizedIndex * 0.7)
    }
}

// MARK: - Previews

#Preview("Small") {
    VStack(spacing: 40) {
        LoadingView(size: .small)
        Text("Small (60pt)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
}

#Preview("Medium") {
    VStack(spacing: 40) {
        LoadingView(size: .medium)
        Text("Medium (120pt)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
}

#Preview("Large") {
    VStack(spacing: 40) {
        LoadingView(size: .large)
        Text("Large (180pt)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
}

#Preview("Dark Mode") {
    VStack(spacing: 40) {
        LoadingView(size: .medium)
        Text("Medium in Dark Mode")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
    .preferredColorScheme(.dark)
}
