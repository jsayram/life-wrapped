// =============================================================================
// PermissionsView — Permission Request UI
// =============================================================================

import SwiftUI
import AVFoundation
import Speech
import LocalLLM

/// Permission request view shown on first launch or when permissions are needed
struct PermissionsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    
    @State private var microphoneStatus: PermissionStatus = .notDetermined
    @State private var speechStatus: PermissionStatus = .notDetermined
    @State private var isRequestingPermissions = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.blue.gradient)
                        
                        Text("Life Wrapped")
                            .font(.title.bold())
                        
                        Text("Your personal audio journal")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                    
                    // Permissions List
                    VStack(spacing: 20) {
                        PermissionCard(
                            icon: "mic.fill",
                            title: "Microphone Access",
                            description: "Record audio throughout your day to create your personal journal",
                            status: microphoneStatus
                        )
                        
                        PermissionCard(
                            icon: "waveform",
                            title: "Speech Recognition",
                            description: "Transcribe your audio recordings into text, privately on your device",
                            status: speechStatus
                        )
                        
                        // Privacy Note
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your Privacy Matters")
                                    .font(.subheadline.bold())
                                
                                Text("All processing happens on your device. Nothing is sent to the cloud.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                        
                        // Local AI Recommendation
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "cpu.fill")
                                    .font(.title2)
                                    .foregroundStyle(.purple.gradient)
                                
                                Text("Enhance with Local AI")
                                    .font(.headline)
                                
                                Spacer()
                            }
                            
                            Text("Get AI-powered summaries similar to ChatGPT and Apple Intelligence, but running entirely on your device for maximum privacy.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Comparison badges
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "apple.logo")
                                        .foregroundColor(.secondary)
                                    Text("Apple Intelligence quality")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.green)
                                    Text("100% private, on-device")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "wifi.slash")
                                        .foregroundColor(.blue)
                                    Text("Works offline")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.top, 4)
                            
                            Text("~2.4GB download • Optional • Available in Settings after setup")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                        .padding()
                        .background(Color.purple.opacity(0.08))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        if allPermissionsGranted {
                            Button {
                                finishSetup()
                            } label: {
                                Text("Get Started")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                        } else {
                            Button {
                                requestPermissions()
                            } label: {
                                if isRequestingPermissions {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Grant Permissions")
                                        .font(.headline)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                            .disabled(isRequestingPermissions)
                            
                            if hasAnyDeniedPermissions {
                                Button {
                                    openSettings()
                                } label: {
                                    Text("Open Settings")
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await checkPermissions()
        }
    }
    
    // MARK: - Computed Properties
    
    private var allPermissionsGranted: Bool {
        microphoneStatus == .authorized && speechStatus == .authorized
    }
    
    private var hasAnyDeniedPermissions: Bool {
        microphoneStatus == .denied || speechStatus == .denied
    }
    
    // MARK: - Methods
    
    private func checkPermissions() async {
        // Check microphone permission
        let micStatus = AVAudioApplication.shared.recordPermission
        await MainActor.run {
            microphoneStatus = PermissionStatus(from: micStatus)
        }
        
        // Check speech recognition permission
        let speechAuthStatus = SFSpeechRecognizer.authorizationStatus()
        await MainActor.run {
            speechStatus = PermissionStatus(from: speechAuthStatus)
        }
        
        print("🔐 [PermissionsView] Mic: \(microphoneStatus), Speech: \(speechStatus)")
    }
    
    private func requestPermissions() {
        isRequestingPermissions = true
        
        Task {
            // Request microphone permission
            await requestMicrophonePermission()
            
            // Request speech recognition permission
            await requestSpeechRecognitionPermission()
            
            // Recheck status
            await checkPermissions()
            
            await MainActor.run {
                isRequestingPermissions = false
            }
        }
    }
    
    private func requestMicrophonePermission() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        
        await MainActor.run {
            microphoneStatus = granted ? .authorized : .denied
            print("🎤 [PermissionsView] Microphone permission: \(granted ? "granted" : "denied")")
        }
    }
    
    @MainActor
    private func requestSpeechRecognitionPermission() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                // Resume on the main actor to satisfy Speech API main-thread expectations.
                Task { @MainActor in
                    continuation.resume(returning: status)
                }
            }
        }
        
        speechStatus = PermissionStatus(from: status)
        print("🗣️ [PermissionsView] Speech recognition permission: \(status)")
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func finishSetup() {
        Task {
            print("🚀 [PermissionsView] Finishing setup...")
            await coordinator.permissionsGranted()
            print("✅ [PermissionsView] Setup complete, permissions sheet should close")
        }
    }
}

// MARK: - Permission Status

enum PermissionStatus {
    case notDetermined
    case authorized
    case denied
    case restricted
    
    init(from recordPermission: AVAudioApplication.recordPermission) {
        switch recordPermission {
        case .undetermined: self = .notDetermined
        case .denied: self = .denied
        case .granted: self = .authorized
        @unknown default: self = .notDetermined
        }
    }
    
    init(from speechAuthStatus: SFSpeechRecognizerAuthorizationStatus) {
        switch speechAuthStatus {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .authorized: self = .authorized
        @unknown default: self = .notDetermined
        }
    }
    
    var icon: String {
        switch self {
        case .notDetermined: return "questionmark.circle"
        case .authorized: return "checkmark.circle.fill"
        case .denied, .restricted: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .notDetermined: return .gray
        case .authorized: return .green
        case .denied, .restricted: return .red
        }
    }
}

// MARK: - Permission Card

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Status
            Image(systemName: status.icon)
                .font(.title2)
                .foregroundColor(status.color)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Preview

struct PermissionsView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionsView()
            .environmentObject(AppCoordinator())
    }
}
