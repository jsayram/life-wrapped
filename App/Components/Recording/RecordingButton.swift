// =============================================================================
// RecordingButton.swift — Main recording interface with waveform visualization
// =============================================================================

import SwiftUI

// MARK: - Recording Button

struct RecordingButton: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var recordingDuration: TimeInterval = 0
    @State private var waveAmplitude: CGFloat = 0.5
    @State private var wavePhase: CGFloat = 0.0
    
    // Timer that fires every 0.1 seconds to update the recording duration
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Spacer()
            
            Button(action: handleRecordingAction) {
                waveformView
                    .contentShape(Circle())
            }
            .disabled(coordinator.recordingState.isProcessing)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .buttonStyle(.plain)
            
            Text(statusText)
                .font(.headline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            
            Spacer()
            Spacer()
            Spacer()
        }
        .onReceive(timer) { _ in
            if case .recording(let startTime) = coordinator.recordingState {
                recordingDuration = Date().timeIntervalSince(startTime)
            } else {
                recordingDuration = 0
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {
                coordinator.resetRecordingState()
            }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: coordinator.recordingState) { _, newState in
            if case .failed(let message) = newState {
                errorMessage = message
                showError = true
            }
        }
    }
    
    // MARK: - Subviews
    
    private var waveformView: some View {
        ZStack {
            if coordinator.recordingState.isRecording {
                // Background gradient pulse
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#A855F7").opacity(0.3),
                                Color(hex: "#3B82F6").opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 90
                        )
                    )
                    .frame(width: 180, height: 180)
                    .scaleEffect(waveAmplitude * 0.3 + 0.9)
                    .animation(.easeInOut(duration: 0.15), value: waveAmplitude)
                
                // Floating orbs
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: CGFloat.random(in: 15...30), height: CGFloat.random(in: 15...30))
                        .blur(radius: 8)
                        .offset(
                            x: cos(wavePhase * 0.5 + CGFloat(index) * .pi / 3) * 50,
                            y: sin(wavePhase * 0.5 + CGFloat(index) * .pi / 3) * 50
                        )
                }
                
                // Siri-style wave animation clipped to circle
                SiriWaveView(amplitude: waveAmplitude, phase: wavePhase)
                    .frame(width: 180, height: 180)
                    .clipShape(Circle())
                
                // Thin circle outline
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(hex: "#A855F7").opacity(0.4),
                                Color(hex: "#3B82F6").opacity(0.4),
                                Color(hex: "#06B6D4").opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .frame(width: 180, height: 180)
                    .onAppear {
                        startWaveAnimation()
                    }
            } else {
                // Static circle when idle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#A855F7"),
                                Color(hex: "#3B82F6")
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 75
                        )
                    )
                    .frame(width: 150, height: 150)
                    .opacity(0.7)
            }
        }
        .frame(width: 180, height: 180)
        .shadow(color: Color(hex: "#A855F7").opacity(0.5), radius: 30, x: 0, y: 0)
        .shadow(color: Color(hex: "#3B82F6").opacity(0.3), radius: 50, x: 0, y: 0)
    }
    
    private func startWaveAnimation() {
        withAnimation(Animation.linear(duration: 0.15).repeatForever(autoreverses: false)) {
            wavePhase -= 1.5
        }
        
        // Random amplitude changes
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            guard coordinator.recordingState.isRecording else { return }
            withAnimation(.linear(duration: 0.15)) {
                waveAmplitude = CGFloat.random(in: 0.3...0.9)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var statusText: String {
        switch coordinator.recordingState {
        case .idle: return "Tap to start recording"
        case .recording: 
            return "Tap to stop Recording... \(formatDuration(recordingDuration))"
        case .processing: return "Processing..."
        case .completed: return "Saved!"
        case .failed(let message): return message
        }
    }
    
    private var accessibilityLabel: String {
        switch coordinator.recordingState {
        case .idle: return "Recording button. Tap to start recording"
        case .recording: return "Recording in progress. Tap to stop"
        case .processing: return "Processing audio"
        case .completed: return "Recording saved successfully"
        case .failed: return "Recording failed"
        }
    }
    
    private var accessibilityHint: String {
        switch coordinator.recordingState {
        case .idle: return "Double tap to begin audio recording"
        case .recording: return "Double tap to stop recording"
        default: return ""
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func handleRecordingAction() {
        print("🔘 [RecordingButton] Button tapped, current state: \(coordinator.recordingState)")
        
        // Trigger haptic immediately on button press (before async work)
        if coordinator.recordingState.isRecording {
            print("📳 [RecordingButton] Triggering STOP haptic (.medium)")
            coordinator.triggerHaptic(.medium)
        } else if case .idle = coordinator.recordingState {
            print("📳 [RecordingButton] Triggering START haptic (.heavy)")
            coordinator.triggerHaptic(.heavy)
        }
        
        Task {
            do {
                if coordinator.recordingState.isRecording {
                    print("⏹️ [RecordingButton] Stopping recording...")
                    _ = try await coordinator.stopRecording()
                    print("✅ [RecordingButton] Recording stopped")
                } else if case .idle = coordinator.recordingState {
                    print("▶️ [RecordingButton] Starting recording...")
                    try await coordinator.startRecording()
                    print("✅ [RecordingButton] Recording started")
                }
            } catch {
                print("❌ [RecordingButton] Action failed: \(error.localizedDescription)")
                coordinator.showError(error.localizedDescription)
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
