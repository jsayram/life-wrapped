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
    private var progressHandlers: [UUID: ProgressHandler] = [:]
    private var activeDownloadProgressId: UUID?
    
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
    
    /// Check if a model is downloaded
    public func isModelDownloaded(_ modelType: LocalModelType) -> Bool {
        let hub = HubApi()
        let repo = HubApi.Repo(id: modelType.huggingFaceRepo)
        let localPath = hub.localRepoLocation(repo)
        let configPath = localPath.appendingPathComponent("config.json")
        return fileManager.fileExists(atPath: configPath.path)
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
    
    /// Download a model from Hugging Face using HubApi
    /// - Parameters:
    ///   - modelType: The model to download
    ///   - progress: Progress callback (0.0-1.0)
    /// - Throws: ModelDownloadError on failure
    public func downloadModel(
        _ modelType: LocalModelType,
        progress: ProgressHandler? = nil
    ) async throws {
        let progressId = UUID()
        if let progress = progress {
            progressHandlers[progressId] = progress
            activeDownloadProgressId = progressId
        }
        defer {
            progressHandlers.removeValue(forKey: progressId)
            activeDownloadProgressId = nil
        }
        
        print("📥 [ModelFileManager] Downloading \(modelType.displayName) from \(modelType.huggingFaceRepo)...")
        
        // Use HubApi to download the full model repo
        let hub = HubApi()
        let repo = HubApi.Repo(id: modelType.huggingFaceRepo)
        
        // Check if already downloaded (look for config.json)
        let localPath = hub.localRepoLocation(repo)
        let configPath = localPath.appendingPathComponent("config.json")
        
        if fileManager.fileExists(atPath: configPath.path) {
            print("✅ [ModelFileManager] Model already exists at: \(localPath.path)")
            if let handler = progressHandlers[progressId] {
                await handler(1.0)
            }
            return
        }
        
        // Download model with progress tracking
        let progressHandler = progressHandlers[progressId]
        try await hub.snapshot(from: repo) { @Sendable downloadProgress in
            if let handler = progressHandler {
                Task { @MainActor in
                    await handler(downloadProgress.fractionCompleted)
                }
            }
        }
        
        print("✅ [ModelFileManager] Model downloaded to: \(localPath.path)")
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
}

// MARK: - Errors

public enum ModelDownloadError: Error, LocalizedError {
    case invalidPath
    case downloadFailed(statusCode: Int)
    case moveFailed(error: Error)
    case verificationFailed
    case invalidSize(expected: ClosedRange<Int64>, actual: Int64)
    
    public var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "Could not determine model storage path"
        case .downloadFailed(let code):
            return "Download failed with status code: \(code)"
        case .moveFailed(let error):
            return "Failed to save model: \(error.localizedDescription)"
        case .verificationFailed:
            return "Could not verify downloaded file"
        case .invalidSize(let expected, let actual):
            return "Downloaded file size \(actual)MB outside expected range \(expected)MB"
        }
    }
}
