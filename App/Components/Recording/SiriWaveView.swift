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
                LinearGradient(
                    colors: [
                        Color(hex: "#A855F7").opacity(Double(alphaComponent)),
                        Color(hex: "#3B82F6").opacity(Double(alphaComponent)),
                        Color(hex: "#06B6D4").opacity(Double(alphaComponent))
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 1.5 / CGFloat(index + 1)
            )
    }
}
