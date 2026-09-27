// =============================================================================
// LocalModelCoordinator — Manages local AI model download and lifecycle
// =============================================================================

import Foundation
import Summarization

/// Manages local AI model download, deletion, and status tracking
@MainActor
public final class LocalModelCoordinator: ObservableObject {
    
    // MARK: - Dependencies
    
    private let summarizationCoordinator: SummarizationCoordinator
    
    // MARK: - State
    
    @Published public private(set) var isDownloadingLocalModel: Bool = false
    /// Progress of the Settings download (0.0-1.0), by bytes
    @Published public private(set) var localModelDownloadProgress: Double = 0
    private var localModelDownloadTask: Task<Void, Never>?
    
    // MARK: - Callbacks
    
    /// Called when showing success feedback
    public var onSuccess: ((String) -> Void)?
    
    /// Called when showing error feedback
    public var onError: ((String) -> Void)?
    
    // MARK: - Constants
    
    /// Download size shown on every download button, for example "~2.3 GB"
    public let expectedLocalModelSizeMB: String = LocalEngine.modelDownloadSize
    /// Name of the model Smart runs
    public let localModelDisplayName: String = LocalEngine.modelDisplayName
    
    /// True when the old Smart model (Phi-3.5) was removed and the new one isn't downloaded yet
    public var showsModelReplacedNotice: Bool {
        UserDefaults.standard.bool(forKey: LocalEngine.modelReplacedNoticeKey)
    }
    
    private func clearModelReplacedNotice() {
        UserDefaults.standard.removeObject(forKey: LocalEngine.modelReplacedNoticeKey)
    }
    
    // MARK: - Initialization
    
    public init(summarizationCoordinator: SummarizationCoordinator) {
        self.summarizationCoordinator = summarizationCoordinator
    }
    
    // MARK: - Model Status
    
    /// Check if the local AI model is downloaded
    public func isLocalModelDownloaded() async -> Bool {
        return await summarizationCoordinator.getLocalEngine().isModelDownloaded()
    }
    
    /// Get formatted model size string: "Downloaded (2173 MB)" or "Not Downloaded"
    public func localModelSizeFormatted() async -> String {
        return await summarizationCoordinator.getLocalEngine().modelSizeFormatted()
    }
    
    /// Get model size in bytes, or nil if not downloaded
    public func modelSizeBytes() async -> Int64? {
        return await summarizationCoordinator.getLocalEngine().modelSizeBytes()
    }
    
    // MARK: - Model Download
    // =========================================================================
    // ⚠️ APP STORE GUIDELINE 4.2.3 COMPLIANCE ⚠️
    // =========================================================================
    //
    // Guideline 4.2.3 (Official Text):
    // (i)  Your app should work on its own without requiring installation
    //      of another app to function.
    // (ii) If your app needs to download additional resources in order to
    //      function on initial launch, disclose the size of the download
    //      and prompt users before doing so.
    //
    // ✅ COMPLIANCE VERIFICATION:
    //
    // Part (i) - App works without downloads:
    //   • BasicEngine (NaturalLanguage framework) is ALWAYS available
    //   • All core features (recording, transcription, basic summaries) work
    //     immediately on first launch without ANY downloads
    //   • Local AI model is OPTIONAL enhancement, not required for functionality
    //
    // Part (ii) - Size disclosure and user prompt:
    //   • Download size (LocalEngine.modelDownloadSize, ~2.3 GB) is clearly displayed on ALL download buttons
    //   • User must explicitly tap a button to initiate download
    //   • Skip/Cancel options available at every download prompt
    //   • Wi-Fi recommendation shown before download
    //   • NO auto-downloads in .task, .onAppear, or init()
    //
    // Download trigger points (all require explicit button tap):
    //   • PermissionsView: "Download (~2.3 GB)" button + "Skip for now"
    //   • SetupView: "Download (~2.3 GB)" button + "Skip for Now"
    //   • AISettingsView: "Download model (~2.3 GB)" button
    //   • HomeTab: "~2.3 GB" in the Basic-mode reminder
    //
    // =========================================================================
    
    /// Download the local AI model in the background
    /// Download continues even if user navigates away from Settings
    /// 
    /// **App Store Compliance (4.2.3):**
    /// - This method requires explicit user action (button tap)
    /// - Never call from .task, .onAppear, or init()
    /// - Download size must be shown to user before calling
    public func startLocalModelDownload() {
        guard !isDownloadingLocalModel else { return }
        
        isDownloadingLocalModel = true
        localModelDownloadProgress = 0
        
        localModelDownloadTask = Task {
            do {
                try await summarizationCoordinator.getLocalEngine().downloadModel { progress in
                    Task { @MainActor in
                        // Publish whole percents only (the whole app observes this), never backwards
                        let percent = (progress * 100).rounded(.down) / 100
                        if percent > self.localModelDownloadProgress {
                            self.localModelDownloadProgress = percent
                        }
                    }
                }
                // A cancelled download never switches the app to Smart
                try Task.checkCancellation()
                
                // After successful download, switch to Local AI
                await summarizationCoordinator.setPreferredEngine(.local)
                
                await MainActor.run {
                    self.clearModelReplacedNotice()
                    self.isDownloadingLocalModel = false
                    self.onSuccess?("Offline AI is ready and turned on")
                }
                
                // Notify that engine changed
                NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            } catch {
                // Cancelling is not a failure: cancelDownload() already reset the state
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isDownloadingLocalModel = false
                    self.onError?("Download failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Download the local AI model with progress tracking (for setup flow)
    /// - Parameter progress: Closure called with download progress (0.0-1.0)
    ///
    /// **App Store Compliance (4.2.3):**
    /// - This method requires explicit user action (button tap)
    /// - Never call from .task, .onAppear, or init()
    /// - Download size must be shown to user before calling
    public func downloadLocalModel(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        isDownloadingLocalModel = true
        defer { isDownloadingLocalModel = false }
        try await summarizationCoordinator.getLocalEngine().downloadModel(progress: progress)
        // A cancelled download never switches the app to Smart
        try Task.checkCancellation()
        
        // After successful download during onboarding, set Local AI as default
        await summarizationCoordinator.setPreferredEngine(.local)
        clearModelReplacedNotice()
        
        onSuccess?("Offline AI is ready and turned on")
        
        // Notify that engine changed
        NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
    }
    
    // MARK: - Cancel Download
    
    /// Cancel an ongoing model download and clean up partial files
    /// Call this when user taps "Cancel" during download
    public func cancelDownload() {
        guard isDownloadingLocalModel else { return }
        
        print("⏹️ [LocalModelCoordinator] User cancelled download")
        localModelDownloadTask?.cancel()
        localModelDownloadTask = nil
        isDownloadingLocalModel = false
        
        // Clean up any partially downloaded files
        Task {
            do {
                try await summarizationCoordinator.getLocalEngine().deleteModel()
                print("🧹 [LocalModelCoordinator] Cleaned up partial download files")
            } catch {
                print("⚠️ [LocalModelCoordinator] Failed to clean up partial files: \(error)")
            }
        }
    }
    
    // MARK: - Model Deletion
    
    /// Delete the local AI model and switch to Basic tier if needed
    public func deleteLocalModel() async throws {
        // Cancel any ongoing download
        localModelDownloadTask?.cancel()
        localModelDownloadTask = nil
        isDownloadingLocalModel = false
        
        // Delete the model
        try await summarizationCoordinator.getLocalEngine().deleteModel()
        
        // If current tier is .local, switch to .basic
        let currentTier = await summarizationCoordinator.getActiveEngine()
        if currentTier == .local {
            await summarizationCoordinator.setPreferredEngine(.basic)
        }
        
        onSuccess?("Offline AI model deleted")
    }
}
