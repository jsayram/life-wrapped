//
//  YearWrapLoadingOverlay.swift
//  LifeWrapped
//
//  Created by Life Wrapped on 1/2/2026.
//

import SwiftUI

/// Full-screen loading overlay for Year Wrap generation with animated progress indicator
struct YearWrapLoadingOverlay: View {
    let statusMessage: String
    
    @State private var animationRotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Blurred background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Animated year wrap icon
                ZStack {
                    // Outer pulsing ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.purple.opacity(0.3), AppTheme.purple.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseScale)
                        .animation(
                            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                            value: pulseScale
                        )
                    
                    // Rotating gradient ring
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    AppTheme.purple,
                                    .blue,
                                    .cyan,
                                    AppTheme.purple
                                ]),
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(animationRotation))
                        .animation(
                            .linear(duration: 2).repeatForever(autoreverses: false),
                            value: animationRotation
                        )
                    
                    // Center icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.purple.opacity(0.3), AppTheme.purple.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 70, height: 70)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppTheme.purple, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.pulse.byLayer)
                    }
                }
                .frame(width: 120, height: 120)
                
                VStack(spacing: 12) {
                    // Title
                    Text("Generating Year Wrap")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    // Status message
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .animation(.easeInOut, value: statusMessage)
                    
                    // Progress indicator text
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \\.self) { index in
                            Circle()
                                .fill(Color.white.opacity(0.6))
                                .frame(width: 6, height: 6)
                                .scaleEffect(pulseScale)
                                .animation(
                                    .easeInOut(duration: 0.6)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.2),
                                    value: pulseScale
                                )
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .shadow(color: AppTheme.purple.opacity(0.3), radius: 30, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
        }
        .onAppear {
            animationRotation = 360
            pulseScale = 1.2
        }
    }
}

#Preview {
    YearWrapLoadingOverlay(statusMessage: "Analyzing with Local AI...\\nThis may take a minute")
}
