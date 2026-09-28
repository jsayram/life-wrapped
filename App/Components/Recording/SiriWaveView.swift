// =============================================================================
// SiriWaveView.swift — Multi-layered Siri wave visualization
// =============================================================================

import SwiftUI

struct SiriWaveView: View {
    var amplitude: CGFloat
    var phase: CGFloat
    
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                singleWave(index: index)
            }
        }
    }
    
    func singleWave(index: Int) -> some View {
        let progress = 1.0 - CGFloat(index) / 5.0
        let normedAmplitude = (1.5 * progress - 0.8) * amplitude
        let alphaComponent = min(1.0, (progress / 3.0 * 2.0) + (1.0 / 3.0))
        
        return SiriWave(phase: phase, normedAmplitude: normedAmplitude)
            .stroke(
                AppTheme.accent.opacity(Double(alphaComponent)),
                lineWidth: 1.5 / CGFloat(index + 1)
            )
    }
}
