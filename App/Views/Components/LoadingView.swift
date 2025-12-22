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
    
    // Theme colors (embedded since AppTheme isn't accessible in separate file)
    private let purple = Color(hex: "#8B5CF6")
    private let darkPurple = Color(hex: "#6D28D9")
    private let magenta = Color(hex: "#EC4899")
    private let skyBlue = Color(hex: "#60A5FA")
    
    var body: some View {
        ZStack {
            // Pulsing concentric circles (center)
            Circle()
                .strokeBorder(
                    RadialGradient(
                        colors: [purple, magenta.opacity(0.3)],
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
                        colors: [skyBlue, purple.opacity(0.3)],
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
                        colors: [darkPurple, skyBlue.opacity(0.3)],
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
            darkPurple,  // 0
            purple,      // 1
            magenta,     // 2
            magenta,     // 3
            purple,      // 4
            skyBlue,     // 5
            skyBlue,     // 6
            purple,      // 7
            darkPurple,  // 8
            darkPurple,  // 9
            purple,      // 10
            magenta      // 11
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

// MARK: - Color Hex Extension (for LoadingView)

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
