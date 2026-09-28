//
//  ModelFileManager.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/22/2025.
//

import Foundation
import Hub

/// Manages downloading and storing local LLM model files
public actor ModelFileManager: NSObject {
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    
    // Download progress tracking
    public typealias ProgressHandler = @Sendable (Double) -> Void
    
    /// Share of the progress bar for the files downloaded before the weights (config, tokenizer,
    /// chat template). They're about 16 MB of the 2.3 GB download, under 1%.
    static let setupFilesShare = 0.01
    
    // URLSession for downloads with progress
    private var urlSession: URLSession!
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes
        config.timeoutIntervalForResource = 3600 // 1 hour
        self.urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }
    
    // MARK: - Public API
    
    /// Check if a model is fully downloaded.
    /// Checking config.json alone could count an interrupted download as complete,
    /// so the weights and tokenizer must be there too.
    public func isModelDownloaded(_ modelType: LocalModelType) -> Bool {
        let hub = HubApi()
        let repo = HubApi.Repo(id: modelType.huggingFaceRepo)
        let localPath = hub.localRepoLocation(repo)
        let requiredFiles = ["config.json", "tokenizer.json", modelType.weightsFileName]
        return requiredFiles.allSatisfy {
            fileManager.fileExists(atPath: localPath.appendingPathComponent($0).path)
        }
    }
    
    /// Get the directory path for a model
    public func modelPath(for modelType: LocalModelType) -> URL? {
        let hub = HubApi()
        let repo = HubApi.Repo(id: modelType.huggingFaceRepo)
        return hub.localRepoLocation(repo)
    }
    
    /// Get the size of a downloaded model directory in bytes
    public func modelSize(_ modelType: LocalModelType) -> Int64? {
        guard let path = modelPath(for: modelType) else {
            return nil
        }
        
        guard let enumerator = fileManager.enumerator(at: path, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let fileSize = attributes[.size] as? Int64 else {
                continue
            }
            totalSize += fileSize
        }
        
        return totalSize
    }
    
    /// Download a model from Hugging Face.
    ///
    /// The small files (config, tokenizer, chat template) download first, then the weights.
    /// Progress follows bytes: the weights are over 99% of the download, so they fill the bar
    /// from 1% to 100%. Counting files instead made the bar jump to about 58% and then crawl.
    /// - Parameters:
    ///   - modelType: The model to download
    ///   - progress: Progress callback (0.0-1.0), called on the main actor
    /// - Throws: ModelDownloadError on failure
    public func downloadModel(
        _ modelType: LocalModelType,
        progress: ProgressHandler? = nil
    ) async throws {
        print("📥 [ModelFileManager] Downloading \(modelType.displayName) from \(modelType.huggingFaceRepo)...")
        
        let hub = HubApi()
        let repo = HubApi.Repo(id: modelType.huggingFaceRepo)
        let localPath = hub.localRepoLocation(repo)
        
        if isModelDownloaded(modelType) {
            print("✅ [ModelFileManager] Model already exists at: \(localPath.path)")
            Self.report(1.0, to: progress)
            return
        }
        
        // Pinned to the tested commit so every user gets the same files
        let revision = modelType.huggingFaceRevision
        let allFiles = try await hub.getFilenames(from: repo, revision: revision)
        let weightFiles = allFiles.filter { Self.isWeightsFile($0) }
        let setupFiles = allFiles.filter { !Self.isWeightsFile($0) }
        
        // Step 1: config, tokenizer and chat template, the first 1% of the bar.
        // (An empty list would mean "every file", so each step only runs when it has files.)
        if !setupFiles.isEmpty {
            try await hub.snapshot(from: repo, revision: revision, matching: setupFiles) { @Sendable stepProgress in
                Self.report(Self.overallProgress(setupFiles: stepProgress.fractionCompleted), to: progress)
            }
        }
        try Task.checkCancellation()
        
        // Step 2: the weights, the rest of the bar
        if !weightFiles.isEmpty {
            try await hub.snapshot(from: repo, revision: revision, matching: weightFiles) { @Sendable stepProgress in
                Self.report(Self.overallProgress(weights: stepProgress.fractionCompleted), to: progress)
            }
        }
        try Task.checkCancellation()
        
        Self.report(1.0, to: progress)
        print("✅ [ModelFileManager] Model downloaded to: \(localPath.path)")
    }
    
    /// Overall progress while the setup files download (0 to 1%)
    static func overallProgress(setupFiles fraction: Double) -> Double {
        setupFilesShare * min(max(fraction, 0), 1)
    }
    
    /// Overall progress while the weights download (1% to 100%)
    static func overallProgress(weights fraction: Double) -> Double {
        setupFilesShare + (1 - setupFilesShare) * min(max(fraction, 0), 1)
    }
    
    /// Weight files are the big ones, everything else is small setup files
    static func isWeightsFile(_ filename: String) -> Bool {
        filename.hasSuffix(".safetensors")
    }
    
    /// Send progress to the caller on the main actor
    private static func report(_ value: Double, to handler: ProgressHandler?) {
        guard let handler else { return }
        Task { @MainActor in
            handler(value)
        }
    }
    
    /// Delete a downloaded model
    public func deleteModel(_ modelType: LocalModelType) throws {
        let hub = HubApi()
        let repo = HubApi.Repo(id: modelType.huggingFaceRepo)
        let localPath = hub.localRepoLocation(repo)
        
        if fileManager.fileExists(atPath: localPath.path) {
            try fileManager.removeItem(at: localPath)
            print("🗑️ [ModelFileManager] Deleted \(modelType.displayName)")
        }
    }
    
    /// Get all downloaded models
    public func downloadedModels() -> [LocalModelType] {
        return LocalModelType.allCases.filter { isModelDownloaded($0) }
    }
    
    /// Delete models this device doesn't use: ones earlier versions of the app downloaded (Phi-3.5),
    /// and the other Smart model, for example Qwen3 4B downloaded before 4 GB phones moved to
    /// Qwen3 1.7B, or a model restored from a backup of a different device.
    /// - Parameter current: The model this device runs, which is kept
    /// - Returns: true if anything was deleted
    @discardableResult
    public func deleteRetiredModels(keeping current: LocalModelType) -> Bool {
        let hub = HubApi()
        let unusedRepos = RetiredLocalModel.allCases.map(\.huggingFaceRepo)
            + LocalModelType.allCases.filter { $0 != current }.map(\.huggingFaceRepo)
        var deletedAny = false
        for repo in unusedRepos {
            let localPath = hub.localRepoLocation(HubApi.Repo(id: repo))
            guard fileManager.fileExists(atPath: localPath.path) else { continue }
            do {
                try fileManager.removeItem(at: localPath)
                deletedAny = true
                print("🗑️ [ModelFileManager] Deleted unused model \(repo)")
            } catch {
                print("⚠️ [ModelFileManager] Could not delete unused model \(repo): \(error)")
            }
        }
        return deletedAny
    }
}

// MARK: - Errors

public enum ModelDownloadError: Error, LocalizedError {
    case invalidPath
    case downloadFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "Could not determine model storage path"
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        }
    }
}
