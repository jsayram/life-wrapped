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
    @State private var isRequestingPermissions = false
    
    // Model download state
    @State private var setupStep: SetupStep = .modelDownload  // Start with AI download
    @State private var downloadProgress: Double = 0.0
    @State private var isDownloading = false
    @State private var downloadError: String? = nil
    
    enum SetupStep {
        case modelDownload  // Download AI first
        case permissions    // Then ask for permissions
    }
    
    var body: some View {
        NavigationView {
            Group {
                switch setupStep {
                case .modelDownload:
                    modelDownloadContent
                case .permissions:
                    permissionsContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .task {
            // Initialize minimal components needed for model download
            print("🔧 [PermissionsView] Initializing AppCoordinator for model download...")
            await coordinator.initializeForModelDownload()
            
            // Check if initialization succeeded
            if coordinator.getLocalModelCoordinator() == nil {
                await MainActor.run {
                    downloadError = "Failed to initialize AI system. Please restart the app."
                    print("❌ [PermissionsView] LocalModelCoordinator not initialized")
                }
                return
            }
            
            // Ready to download - wait for user confirmation (App Store requirement)
            print("✅ [PermissionsView] Ready for download, waiting for user confirmation...")
        }
    }
    
    // MARK: - Permissions Content
    
    private var permissionsContent: some View {
        ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(alignment: .leading, spacing: 14) {
                        OnboardingAppMark()

                        Text("Your year,\nin your own words.")
                            .font(AppTheme.titleFont(size: 34))
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        Text("Life Wrapped is a private audio journal. Speak, and it turns your days into summaries and a year in review.")
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 40)
                    
                    // Permissions List
                    VStack(spacing: 20) {
                        PermissionCard(
                            icon: "mic",
                            title: "Microphone",
                            description: "Record audio throughout your day to create your personal journal",
                            status: microphoneStatus
                        )
                        
                        // Info card about speech recognition (requested later)
                        HStack(spacing: 16) {
                            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 28)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Speech recognition")
                                    .font(.headline)
                                
                                Text("Requested when you start recording")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "clock")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.card).stroke(AppTheme.hairline, lineWidth: 1))
                        
                        // Privacy Note
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lock.shield")
                                .foregroundColor(AppTheme.accent)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Private by design")
                                    .font(.subheadline.bold())
                                
                                Text("Transcription happens on your iPhone. Nothing is sent to the cloud unless you choose Smartest.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                        
                        // AI Tiers Comparison
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.accent)
                                
                                Text("AI-Powered Summaries")
                                    .font(.headline)
                                
                                Spacer()
                            }
                            
                            // Two-tier comparison cards
                            HStack(spacing: 12) {
                                // On-Device (Free) Card
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: "iphone")
                                            .foregroundColor(AppTheme.accent)
                                        Text("On-Device")
                                            .font(.subheadline.bold())
                                        Spacer()
                                    }
                                    
                                    Text("INCLUDED")
                                        .font(.caption.bold())
                                        .foregroundColor(AppTheme.accent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppTheme.fill)
                                        .cornerRadius(6)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        FeatureBullet(text: "Works offline", color: AppTheme.accent)
                                        FeatureBullet(text: "100% private", color: AppTheme.accent)
                                        FeatureBullet(text: "Good summaries", color: AppTheme.accent)
                                        FeatureBullet(text: "Always available", color: AppTheme.accent)
                                    }
                                    .font(.caption2)
                                    
                                    Spacer()
                                    
                                    HStack {
                                        Image(systemName: "checkmark.circle")
                                            .foregroundColor(AppTheme.accent)
                                        Text("Included")
                                            .font(.caption.bold())
                                            .foregroundColor(AppTheme.accent)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.card).stroke(AppTheme.hairline, lineWidth: 1))
                                
                                // Smartest AI (Premium) Card
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: "sparkles")
                                            .foregroundColor(AppTheme.accent)
                                        Text("Smartest")
                                            .font(.subheadline.bold())
                                        Spacer()
                                    }
                                    
                                    Text("OPTIONAL")
                                        .font(.caption.bold())
                                        .foregroundColor(AppTheme.accent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppTheme.fill)
                                        .cornerRadius(6)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        FeatureBullet(text: "OpenAI & Anthropic", color: AppTheme.accent)
                                        FeatureBullet(text: "Best quality", color: AppTheme.accent)
                                        FeatureBullet(text: "Deep insights", color: AppTheme.accent)
                                        FeatureBullet(text: "Detailed analysis", color: AppTheme.accent)
                                    }
                                    .font(.caption2)
                                    
                                    Spacer()
                                    
                                    HStack {
                                        Image(systemName: "lock")
                                            .foregroundColor(.secondary)
                                        Text("Unlock in Settings")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.card).stroke(AppTheme.hairline, lineWidth: 1))
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            
                            // Reassurance text
                            Label("App is fully functional with On-Device AI", systemImage: "checkmark")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        if allPermissionsGranted {
                            Button {
                                finishSetup()
                            } label: {
                                Text("Continue")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.onAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(AppTheme.accent)
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
                                    Text("Continue")
                                        .font(.headline)
                                }
                            }
                            .foregroundStyle(AppTheme.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.accent)
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
            VStack(alignment: .leading, spacing: 14) {
                OnboardingAppMark()

                Text("Setting up\non-device AI")
                    .font(AppTheme.titleFont(size: 34))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("This might take a minute.")
                    .font(.body)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            
            // Description
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bolt")
                        .foregroundColor(AppTheme.accent)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("On-device AI")
                            .font(.subheadline.bold())
                        
                        Text("This model powers real-time chunk summarization as you record. It runs entirely on your device for maximum privacy.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(AppTheme.accent)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("100% Private")
                            .font(.subheadline.bold())
                        
                        Text("With on-device AI, your transcripts and summaries stay on your iPhone.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.card).stroke(AppTheme.hairline, lineWidth: 1))
            .padding(.horizontal)
            
            Spacer()
            
            // Progress or Download Button
            VStack(spacing: 16) {
                if isDownloading {
                    VStack(spacing: 16) {
                        ProgressView(value: downloadProgress)
                            .progressViewStyle(.linear)
                            .tint(AppTheme.accent)
                            .scaleEffect(x: 1, y: 2, anchor: .center)
                        
                        Text("Downloading AI Model... \(Int(downloadProgress * 100))%")
                            .font(.headline)
                        
                        Text("Phi-3.5 Mini • \(coordinator.expectedLocalModelSizeMB)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Cancel Download button
                        Button {
                            cancelDownload()
                        } label: {
                            Text("Cancel download")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(AppTheme.destructive)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 24)
                                .background(
                                    Capsule()
                                        .strokeBorder(AppTheme.destructive.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal)
                } else if let error = downloadError {
                    VStack(spacing: 12) {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(AppTheme.destructive)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 8)
                        
                        Button {
                            startModelDownload()
                        } label: {
                            Text("Retry download")
                                .font(.headline)
                                .foregroundStyle(AppTheme.onAccent)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppTheme.accent)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    // Explicit download confirmation (App Store Guideline 4.2.3)
                    VStack(spacing: 16) {
                        Text("Download AI model")
                            .font(.headline)
                        
                        Text("This will download the Phi-3.5 Mini model (\(coordinator.expectedLocalModelSizeMB)). Wi-Fi recommended.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button {
                            startModelDownload()
                        } label: {
                            Text("Download (\(coordinator.expectedLocalModelSizeMB))")
                                .font(.headline)
                                .foregroundStyle(AppTheme.onAccent)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppTheme.accent)
                                .cornerRadius(12)
                        }
                        
                        Button {
                            skipModelDownload()
                        } label: {
                            Text("Skip for now")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Computed Properties
    
    private var allPermissionsGranted: Bool {
        microphoneStatus == .authorized
    }
    
    private var hasAnyDeniedPermissions: Bool {
        microphoneStatus == .denied
    }
    
    // MARK: - Setup Flow Methods
    
    private func proceedToPermissions() {
        print("➡️ [PermissionsView] AI download complete, proceeding to permissions")
        withAnimation {
            setupStep = .permissions
        }
        print("✅ [PermissionsView] Transitioned to permissions step")
        
        // Check if permissions already granted
        Task {
            await checkPermissions()
            if allPermissionsGranted {
                print("🎯 [PermissionsView] Permissions already granted, finishing setup")
                await MainActor.run {
                    finishSetup()
                }
            }
        }
    }
    
    private func skipModelDownload() {
        print("⏭️ [PermissionsView] User skipped model download, proceeding to permissions")
        proceedToPermissions()
    }
    
    private func cancelDownload() {
        print("⏹️ [PermissionsView] User cancelled download")
        coordinator.getLocalModelCoordinator()?.cancelDownload()
        
        // Reset state to show Download/Skip buttons again
        withAnimation {
            isDownloading = false
            downloadProgress = 0.0
            downloadError = nil  // Clear any error so Download/Skip shows
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
                    proceedToPermissions()  // Move to permissions after download
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
        
        print("🔐 [PermissionsView] Mic: \(microphoneStatus) (Speech will be requested when recording)")
    }
    
    private func requestPermissions() {
        isRequestingPermissions = true
        
        Task {
            // Request microphone permission only
            await requestMicrophonePermission()
            
            // Recheck status
            await checkPermissions()
            
            await MainActor.run {
                isRequestingPermissions = false
                print("✅ [PermissionsView] Microphone permission requested")
                print("🔐 [PermissionsView] Mic: \(microphoneStatus)")
                
                // If microphone granted, finish setup
                if allPermissionsGranted {
                    print("🎉 [PermissionsView] Microphone granted, finishing setup")
                    print("ℹ️ [PermissionsView] Speech recognition will be requested when user starts recording")
                    finishSetup()
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
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func finishSetup() {
        print("🚀 [PermissionsView] Finishing setup...")
        Task {
            // Initialize coordinator (this may take a moment)
            print("🔧 [PermissionsView] Calling coordinator.permissionsGranted()...")
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
        case .authorized: return "checkmark.circle"
        case .denied, .restricted: return "xmark.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .notDetermined: return .gray
        case .authorized: return AppTheme.accent
        case .denied, .restricted: return AppTheme.destructive
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
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 28)
            
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
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(status.color)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.card).stroke(AppTheme.hairline, lineWidth: 1))
    }
}

// MARK: - Feature Bullet

private struct FeatureBullet: View {
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.caption2.bold())
                .foregroundColor(color)
            Text(text)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

struct PermissionsView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionsView()
            .environmentObject(AppCoordinator())
    }
}

// MARK: - Onboarding App Mark

/// Small ink square with a waveform, echoing the app icon at the top of onboarding.
private struct OnboardingAppMark: View {
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(AppTheme.onAccent)
            .frame(width: 56, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.accent)
            )
            .accessibilityHidden(true)
    }
}
