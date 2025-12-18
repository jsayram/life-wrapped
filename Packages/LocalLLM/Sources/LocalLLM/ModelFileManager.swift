//
//  ModelFileManager.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/17/2025.
//

import Foundation

/// Manages local LLM model files (GGUF format)
public actor ModelFileManager {
    
    /// Directory where models are stored
    private let modelsDirectory: URL
    
    /// Track which models are currently being downloaded
    private var activeDownloads: Set<ModelSize> = []
    
    /// Supported model configurations
    public enum ModelSize: String, CaseIterable, Sendable {
        case phi35Mini = "Phi-3.5-mini-instruct-Q4_K_M.gguf"  // ~2.4GB quantized
        
        public var displayName: String {
            return "Phi-3.5 Mini (4-bit)"
        }
        
        public var fullDisplayName: String {
            return "Microsoft Phi-3.5 Mini Instruct (Q4_K_M)"
        }
        
        public var approximateSizeMB: Int {
            return 2390
        }
        
        public var contextLength: Int {
            return 131072  // 128K context
        }
    }
    
    public init() {
        // Models stored in Documents/Models directory
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.modelsDirectory = documentsURL.appendingPathComponent("Models", isDirectory: true)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }
    
    /// Check if a model file exists locally
    public func isModelAvailable(_ model: ModelSize) -> Bool {
        let modelURL = modelsDirectory.appendingPathComponent(model.rawValue)
        return FileManager.default.fileExists(atPath: modelURL.path)
    }
    
    /// Get URL for a model file
    public func modelURL(for model: ModelSize) throws -> URL {
        let modelURL = modelsDirectory.appendingPathComponent(model.rawValue)
        
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw LocalLLMError.modelNotFound(model.rawValue)
        }
        
        return modelURL
    }
    
    /// Get file size of a model
    public func modelFileSize(_ model: ModelSize) throws -> Int64 {
        let modelURL = modelsDirectory.appendingPathComponent(model.rawValue)
        let attributes = try FileManager.default.attributesOfItem(atPath: modelURL.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    /// Delete a model file to free up space
    public func deleteModel(_ model: ModelSize) throws {
        let modelURL = modelsDirectory.appendingPathComponent(model.rawValue)
        try FileManager.default.removeItem(at: modelURL)
    }
    
    /// List all available models
    public func availableModels() -> [ModelSize] {
        ModelSize.allCases.filter { isModelAvailable($0) }
    }
    
    /// Check if a model is currently being downloaded
    public func isDownloading(_ model: ModelSize) -> Bool {
        return activeDownloads.contains(model)
    }
    
    /// Get the models directory URL for external downloads
    public func getModelsDirectory() -> URL {
        return modelsDirectory
    }
    
    // MARK: - Model Download
    
    /// Download URLs for models (Hugging Face)
    private func downloadURL(for model: ModelSize) -> URL? {
        // Using bartowski's GGUF conversions (no auth required)
        return URL(string: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf")
    }
    
    /// Download a model file with progress tracking
    public func downloadModel(_ model: ModelSize, progress: @MainActor @Sendable @escaping (Double) -> Void) async throws {
        guard let downloadURL = downloadURL(for: model) else {
            throw LocalLLMError.modelNotFound("No download URL configured for \(model.rawValue)")
        }
        
        let destinationURL = modelsDirectory.appendingPathComponent(model.rawValue)
        
        // Check if already exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            throw LocalLLMError.configurationError("Model \(model.rawValue) already exists")
        }
        
        // Check if already downloading
        if activeDownloads.contains(model) {
            throw LocalLLMError.configurationError("Model \(model.displayName) is already being downloaded")
        }
        
        // Mark as downloading
        activeDownloads.insert(model)
        defer {
            activeDownloads.remove(model)
        }
        
        // Create download delegate
        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        
        // Start download
        let (tempURL, response) = try await session.download(from: downloadURL)
        
        // Verify response
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LocalLLMError.configurationError("Download failed with response: \(response)")
        }
        
        // Move to final location
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        
        print("✅ [ModelFileManager] Downloaded \(model.displayName) to \(destinationURL.path)")
    }
    
    /// Cancel an ongoing download
    public func cancelDownload() {
        // Downloads are managed by caller's Task cancellation
        print("⚠️ [ModelFileManager] Download cancellation requested")
    }
}

// MARK: - Download Delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    
    private let progressHandler: @MainActor @Sendable (Double) -> Void
    
    init(progress: @MainActor @Sendable @escaping (Double) -> Void) {
        self.progressHandler = progress
        super.init()
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        print("📥 [ModelFileManager] Download progress: \(Int(progress * 100))% (\(totalBytesWritten)/\(totalBytesExpectedToWrite) bytes)")
        MainActor.assumeIsolated {
            progressHandler(progress)
        }
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Final 100% progress
        print("✅ [ModelFileManager] Download complete!")
        MainActor.assumeIsolated {
            progressHandler(1.0)
        }
    }
}
