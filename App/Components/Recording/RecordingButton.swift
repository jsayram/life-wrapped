// =============================================================================
// RecordingButton.swift — Main recording interface with waveform visualization
// =============================================================================

import SwiftUI
import AudioCapture

// MARK: - Recording Button

struct RecordingButton: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var recordingDuration: TimeInterval = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Bigger on iPad so the button holds the larger screen
    private var faceScale: CGFloat { sizeClass == .regular ? 1.35 : 1 }
    
    // Timer that fires every 0.1 seconds to update the recording duration
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            if coordinator.recordingState.isRecording {
                VStack(spacing: 20) {
                    Text(formatDuration(recordingDuration))
                        .scaledFont(size: 48, weight: .light, design: .monospaced)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityLabel("Recording time \(formatDuration(recordingDuration))")
                    LevelBars(audio: coordinator.audioCapture)
                        .frame(height: 48)
                        .accessibilityHidden(true)
                    InputWarning(audio: coordinator.audioCapture)
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
                    Text("Transcribed privately on this \(DeviceName.current)")
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
                .frame(width: 168 * faceScale, height: 168 * faceScale)

            Circle()
                .fill(AppTheme.accent)
                .frame(width: 132 * faceScale, height: 132 * faceScale)

            if coordinator.recordingState.isRecording {
                RoundedRectangle(cornerRadius: 8 * faceScale, style: .continuous)
                    .fill(AppTheme.recording)
                    .frame(width: 36 * faceScale, height: 36 * faceScale)
            } else if coordinator.recordingState.isProcessing {
                ProgressView()
                    .tint(AppTheme.onAccent)
                    .controlSize(.large)
            } else {
                Image(systemName: "mic")
                    .scaledFont(size: 40 * faceScale, weight: .regular)
                    .foregroundStyle(AppTheme.onAccent)
            }
        }
        .frame(width: 168 * faceScale, height: 168 * faceScale)
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

/// Scrolling level meter driven by the microphone: newest reading on the right.
private struct LevelBars: View {
    @ObservedObject var audio: AudioCaptureManager

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(audio.levelHistory.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < 4 ? AppTheme.textSecondary : AppTheme.textPrimary)
                    .frame(width: 3, height: max(4, 46 * CGFloat(level)))
            }
        }
        .animation(.easeOut(duration: 0.08), value: audio.levelHistory)
    }
}

// MARK: - Input Warning

/// Tells the user when the mic isn't picking them up, so a silent recording isn't a surprise later.
private struct InputWarning: View {
    let audio: AudioCaptureManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let message = message(for: audio.inputStatus(at: context.date))
            Label(message ?? " ", systemImage: "mic.slash")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .opacity(message == nil ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: message)
                .accessibilityHidden(message == nil)
        }
        .frame(minHeight: 40)
    }

    private func message(for status: AudioCaptureManager.InputStatus) -> String? {
        switch status {
        case .hearing: return nil
        case .quiet: return "Can't hear you. Move closer or speak up."
        case .noSignal: return "The mic isn't picking up any sound. It may be blocked or in use by another app."
        }
    }
}
