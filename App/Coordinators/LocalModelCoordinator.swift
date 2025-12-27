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
    private var localModelDownloadTask: Task<Void, Never>?
    
    // MARK: - Callbacks
    
    /// Called when showing success feedback
    public var onSuccess: ((String) -> Void)?
    
    /// Called when showing error feedback
    public var onError: ((String) -> Void)?
    
    // MARK: - Constants
    
    public let expectedLocalModelSizeMB: String = "~2.3 GB"
    public let localModelDisplayName: String = "Phi-3.5 Mini"
    
    // MARK: - Initialization
    
    public init(summarizationCoordinator: SummarizationCoordinator) {
        self.summarizationCoordinator = summarizationCoordinator
    }
    
    // MARK: - Model Status
    
    /// Check if the local AI model is downloaded
    public func isLocalModelDownloaded() async -> Bool {
        return await summarizationCoordinator.getLocalEngine().isModelDownloaded()
    }
    
    /// Get formatted model size string: "Downloaded (2282 MB)" or "Not Downloaded"
    public func localModelSizeFormatted() async -> String {
        return await summarizationCoordinator.getLocalEngine().modelSizeFormatted()
    }
    
    // MARK: - Model Download
    
    /// Download the local AI model in the background
    /// Download continues even if user navigates away from Settings
    public func startLocalModelDownload() {
        guard !isDownloadingLocalModel else { return }
        
        isDownloadingLocalModel = true
        
        localModelDownloadTask = Task {
            do {
                try await summarizationCoordinator.getLocalEngine().downloadModel(progress: nil)
                
                // After successful download, switch to Local AI
                await summarizationCoordinator.setPreferredEngine(.local)
                
                await MainActor.run {
                    self.isDownloadingLocalModel = false
                    self.onSuccess?("Local AI model downloaded and activated")
                }
                
                // Notify that engine changed
                NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            } catch {
                await MainActor.run {
                    self.isDownloadingLocalModel = false
                    self.onError?("Download failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Download the local AI model with progress tracking (for setup flow)
    /// - Parameter progress: Closure called with download progress (0.0-1.0)
    public func downloadLocalModel(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        isDownloadingLocalModel = true
        defer { isDownloadingLocalModel = false }
        try await summarizationCoordinator.getLocalEngine().downloadModel(progress: progress)
        onSuccess?("Local AI model downloaded")
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
        
        onSuccess?("Local AI model deleted")
    }
}
