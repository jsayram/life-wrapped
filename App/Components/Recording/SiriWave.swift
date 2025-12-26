// =============================================================================
// SiriWave.swift — Siri-style waveform animation
// =============================================================================

import SwiftUI

// MARK: - Siri Wave Shape

struct SiriWave: Shape {
    var frequency: CGFloat = 1.5
    var density: CGFloat = 1.0
    var phase: CGFloat
    var normedAmplitude: CGFloat
    
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(normedAmplitude, phase) }
        set {
            normedAmplitude = newValue.first
            phase = newValue.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let maxAmplitude = rect.height / 2.0
        let mid = rect.width / 2
        
        for x in stride(from: 0, to: rect.width + density, by: density) {
            // Parabolic scaling
            let scaling = -pow(1 / mid * (x - mid), 2) + 1
            let y = scaling * maxAmplitude * normedAmplitude * sin(CGFloat(2 * Double.pi) * frequency * (x / rect.width) + phase) + rect.height / 2
            if x == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        return path
    }
}
