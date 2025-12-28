// =============================================================================
// PermissionsView — Permission Request UI
// =============================================================================

import SwiftUI
import AVFoundation
import Speech

/// Permission request view shown on first launch or when permissions are needed
struct PermissionsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    
    @State private var microphoneStatus: PermissionStatus = .notDetermined
    @State private var speechStatus: PermissionStatus = .notDetermined
    @State private var isRequestingPermissions = false
    
    // Model download state
    @State private var setupStep: SetupStep = .permissions
    @State private var downloadProgress: Double = 0.0
    @State private var isDownloading = false
    @State private var downloadError: String? = nil
    
    enum SetupStep {
        case permissions
        case modelDownload
    }
    
    var body: some View {
        NavigationView {
            Group {
                switch setupStep {
                case .permissions:
                    permissionsContent
                case .modelDownload:
                    modelDownloadContent
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await checkPermissions()
        }
        .onAppear {
            // Recheck permissions when view appears (handles coming back from system permission dialogs)
            Task {
                await checkPermissions()
                print("🔄 [PermissionsView] onAppear - Rechecked permissions")
                
                // If we're still on permissions screen but permissions are granted, auto-proceed
                if setupStep == .permissions && allPermissionsGranted && !isRequestingPermissions {
                    print("🎯 [PermissionsView] Permissions already granted, auto-proceeding to model download")
                    // Small delay to show the checkmarks
                    try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s delay
                    await MainActor.run {
                        proceedToModelDownload()
                    }
                }
            }
        }
    }
    
    // MARK: - Permissions Content
    
    private var permissionsContent: some View {
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
                                
                                Text("Transcription happens entirely on your device. Nothing is sent to the cloud.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                        
                        // AI Summary Information
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.title2)
                                    .foregroundStyle(.purple.gradient)
                                
                                Text("AI-Powered Summaries")
                                    .font(.headline)
                                
                                Spacer()
                            }
                            
                            Text("Get intelligent summaries of your recordings and yearly insights using advanced AI.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Feature badges
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "waveform")
                                        .foregroundColor(.green)
                                    Text("Transcription: 100% on-device")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "wifi")
                                        .foregroundColor(.blue)
                                    Text("AI summaries: requires internet")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "key.fill")
                                        .foregroundColor(.secondary)
                                    Text("Optional: bring your own API key")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 4)
                            
                            Text("Configure AI settings after setup • OpenAI or Anthropic supported")
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
                                proceedToModelDownload()
                            } label: {
                                Text("Continue")
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
    }
    
    // MARK: - Model Download Content
    
    private var modelDownloadContent: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Header
            VStack(spacing: 16) {
                Image(systemName: "cpu")
                    .font(.system(size: 80))
                    .foregroundStyle(.purple.gradient)
                
                Text("On Device Artificial Intelligence")
                    .font(.title.bold())
                
                Text("Phi-3.5 Mini • \(coordinator.expectedLocalModelSizeMB)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Description
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.purple)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("On-Device AI Processing")
                            .font(.subheadline.bold())
                        
                        Text("This model powers real-time chunk summarization as you record. It runs entirely on your device for maximum privacy.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("100% Private")
                            .font(.subheadline.bold())
                        
                        Text("Your transcripts and summaries never leave your device. No cloud processing required.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.purple.opacity(0.08))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
            
            // Progress or Download Button
            VStack(spacing: 16) {
                if isDownloading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("Downloading \(coordinator.localModelDisplayName)...")
                            .font(.headline)
                        
                        Text("This may take a few minutes depending on your connection.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                } else if let error = downloadError {
                    VStack(spacing: 12) {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 8)
                        
                        Button {
                            startModelDownload()
                        } label: {
                            Text("Retry Download")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 12) {
                        Text("AI model download will begin automatically...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Computed Properties
    
    private var allPermissionsGranted: Bool {
        microphoneStatus == .authorized && speechStatus == .authorized
    }
    
    private var hasAnyDeniedPermissions: Bool {
        microphoneStatus == .denied || speechStatus == .denied
    }
    
    // MARK: - Setup Flow Methods
    
    private func proceedToModelDownload() {
        print("➡️ [PermissionsView] Proceeding to model download screen")
        withAnimation {
            setupStep = .modelDownload
        }
        print("✅ [PermissionsView] Transitioned to model download step")
        
        // Auto-start mandatory download after brief transition delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay for transition
            await MainActor.run {
                print("🚀 [PermissionsView] Auto-starting mandatory model download...")
                startModelDownload()
            }
        }
    }
    
    private func startModelDownload() {
        guard !isDownloading else {
            print("⚠️ [PermissionsView] Download already in progress")
            return
        }
        
        print("📥 [PermissionsView] Starting model download...")
        isDownloading = true
        downloadError = nil
        downloadProgress = 0.0
        
        Task {
            do {
                try await coordinator.downloadLocalModel { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }
                
                await MainActor.run {
                    print("✅ [PermissionsView] Model download complete")
                    isDownloading = false
                    finishSetup()
                }
            } catch {
                await MainActor.run {
                    print("❌ [PermissionsView] Model download failed: \(error)")
                    isDownloading = false
                    downloadError = "Download failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Permission Methods
    
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
                print("✅ [PermissionsView] Permissions requested, status updated")
                print("🔐 [PermissionsView] Mic: \(microphoneStatus), Speech: \(speechStatus)")
                
                // If both permissions granted, auto-proceed to model download
                if allPermissionsGranted {
                    print("🎉 [PermissionsView] All permissions granted, auto-proceeding to model download")
                    // Small delay to show the checkmarks
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                        await MainActor.run {
                            proceedToModelDownload()
                        }
                    }
                }
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
        print("🚀 [PermissionsView] Finishing setup...")
        Task {
            do {
                // Initialize coordinator (this may take a moment)
                print("🔧 [PermissionsView] Calling coordinator.permissionsGranted()...")
                await coordinator.permissionsGranted()
                print("✅ [PermissionsView] Setup complete, permissions sheet should close")
            } catch {
                print("❌ [PermissionsView] Setup failed with error: \(error)")
                await MainActor.run {
                    downloadError = "Setup failed: \(error.localizedDescription)"
                }
            }
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
