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
    
    // Timer that fires every 0.1 seconds to update the recording duration
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            if coordinator.recordingState.isRecording {
                VStack(spacing: 20) {
                    Text(formatDuration(recordingDuration))
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityLabel("Recording time \(formatDuration(recordingDuration))")
                    LevelBars()
                        .frame(height: 48)
                        .accessibilityHidden(true)
                }
                .transition(.opacity)
            }

            Button(action: handleRecordingAction) {
                recordButtonFace
                    .contentShape(Circle())
            }
            .disabled(coordinator.recordingState.isProcessing)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                if case .idle = coordinator.recordingState {
                    Text("Transcribed privately on this iPhone")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.top, -8)

            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.2), value: coordinator.recordingState.isRecording)
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

    /// Flat record button: a card-colored ring with a hairline border around a solid ink circle.
    /// Idle shows a microphone; recording shows a red stop square.
    private var recordButtonFace: some View {
        ZStack {
            Circle()
                .fill(AppTheme.card)
                .overlay(Circle().strokeBorder(AppTheme.hairline, lineWidth: 1))
                .frame(width: 168, height: 168)

            Circle()
                .fill(AppTheme.accent)
                .frame(width: 132, height: 132)

            if coordinator.recordingState.isRecording {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.recording)
                    .frame(width: 36, height: 36)
            } else if coordinator.recordingState.isProcessing {
                ProgressView()
                    .tint(AppTheme.onAccent)
                    .controlSize(.large)
            } else {
                Image(systemName: "mic")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(AppTheme.onAccent)
            }
        }
        .frame(width: 168, height: 168)
    }

    // MARK: - Helpers
    
    private var statusText: String {
        switch coordinator.recordingState {
        case .idle: return "Tap to record"
        case .recording: return "Tap to stop"
        case .processing: return "Saving"
        case .completed: return "Saved"
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

// MARK: - Level Bars

/// Minimal animated level meter shown while recording.
private struct LevelBars: View {
    private let count = 14

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { context in
            let seed = Int(context.date.timeIntervalSinceReferenceDate / 0.15)
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<count, id: \.self) { index in
                    let edge = index < 2 || index >= count - 3
                    RoundedRectangle(cornerRadius: 2)
                        .fill(edge ? AppTheme.textSecondary : AppTheme.textPrimary)
                        .frame(width: 3, height: height(for: index, seed: seed))
                }
            }
            .animation(.linear(duration: 0.15), value: seed)
        }
    }

    private func height(for index: Int, seed: Int) -> CGFloat {
        var hasher = Hasher()
        hasher.combine(index)
        hasher.combine(seed)
        let value = abs(hasher.finalize() % 1000)
        let fraction = CGFloat(value) / 1000
        let taper: CGFloat = (index < 2 || index >= count - 3) ? 0.45 : 1
        return max(6, 46 * fraction * taper)
    }
}
