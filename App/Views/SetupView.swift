// =============================================================================
// SetupView — Initial App Setup (Model Download Only)
// =============================================================================

import SwiftUI
import Speech

/// Setup view shown on first launch to download the AI model
/// Speech permission requested after download, microphone when recording
struct SetupView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    
    @State private var downloadProgress: Double = 0.0
    @State private var isDownloading = false
    @State private var downloadError: String? = nil
    @State private var isReady = false
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "cpu")
                        .font(.system(size: 80))
                        .foregroundStyle(.purple.gradient)
                    
                    Text("Setting Up Life Wrapped")
                        .font(.title.bold())
                    
                    Text("Downloading on-device AI...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Privacy Info
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("100% Private")
                                .font(.subheadline.bold())
                            
                            Text("All processing happens on your device. Nothing is sent to the cloud.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.purple)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Smart Summaries")
                                .font(.subheadline.bold())
                            
                            Text("AI-powered insights from your audio recordings, processed locally.")
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
                
                // Progress Section
                VStack(spacing: 16) {
                    if isDownloading {
                        VStack(spacing: 16) {
                            ProgressView(value: downloadProgress)
                                .progressViewStyle(.linear)
                                .tint(.purple)
                                .scaleEffect(x: 1, y: 2, anchor: .center)
                            
                            Text("Downloading... \(Int(downloadProgress * 100))%")
                                .font(.headline)
                            
                            Text("Phi-3.5 Mini • \(coordinator.expectedLocalModelSizeMB)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    } else if let error = downloadError {
                        VStack(spacing: 12) {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                            
                            Button {
                                startDownload()
                            } label: {
                                Text("Retry")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.purple)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                    } else if isReady {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.green)
                            
                            Text("Ready to go!")
                                .font(.headline)
                            
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
                        }
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Preparing...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .task {
            await initialize()
        }
    }
    
    // MARK: - Setup Flow
    
    private func initialize() async {
        print("🔧 [SetupView] Initializing...")
        
        await coordinator.initializeForModelDownload()
        
        if coordinator.getLocalModelCoordinator() == nil {
            await MainActor.run {
                downloadError = "Failed to initialize. Please restart the app."
            }
            return
        }
        
        // Small delay for UI
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        await MainActor.run {
            startDownload()
        }
    }
    
    private func startDownload() {
        guard !isDownloading else { return }
        
        print("📥 [SetupView] Starting model download...")
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
                    print("✅ [SetupView] Download complete")
                    self.isDownloading = false
                }
                
                print("ℹ️ [SetupView] Speech recognition will be requested when user starts recording")
                
                // Small delay before marking ready
                print("⏳ [SetupView] Waiting before marking ready...")
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                
                await MainActor.run {
                    print("✅ [SetupView] Marking as ready")
                    self.isReady = true
                }
            } catch {
                await MainActor.run {
                    print("❌ [SetupView] Download failed: \(error)")
                    self.isDownloading = false
                    self.downloadError = error.localizedDescription
                }
            }
        }
    }
    
    private func finishSetup() {
        print("🚀 [SetupView] Finishing setup...")
        Task { @MainActor in
            await coordinator.permissionsGranted()
        }
    }
}

#Preview {
    SetupView()
        .environmentObject(AppCoordinator())
}
