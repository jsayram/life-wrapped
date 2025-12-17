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
    
    /// Supported model configurations
    public enum ModelSize: String, CaseIterable, Sendable {
        case phi3Mini4K = "phi-3-mini-4k-instruct-q4.gguf"  // ~2.4GB quantized
        case phi3Mini128K = "phi-3-mini-128k-instruct-q4.gguf"  // ~2.4GB with longer context
        
        public var displayName: String {
            switch self {
            case .phi3Mini4K: return "Phi-3 Mini (4K context)"
            case .phi3Mini128K: return "Phi-3 Mini (128K context)"
            }
        }
        
        public var approximateSizeMB: Int {
            switch self {
            case .phi3Mini4K: return 2400
            case .phi3Mini128K: return 2400
            }
        }
        
        public var contextLength: Int {
            switch self {
            case .phi3Mini4K: return 4096
            case .phi3Mini128K: return 131072
            }
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
    
    /// Get the models directory URL for external downloads
    public func getModelsDirectory() -> URL {
        return modelsDirectory
    }
    
    // MARK: - Model Download
    
    /// Download URLs for models (Hugging Face)
    private func downloadURL(for model: ModelSize) -> URL? {
        switch model {
        case .phi3Mini4K:
            // Hugging Face GGUF model URL
            return URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf")
        case .phi3Mini128K:
            return URL(string: "https://huggingface.co/microsoft/Phi-3-mini-128k-instruct-gguf/resolve/main/Phi-3-mini-128k-instruct-q4.gguf")
        }
    }
    
    /// Download a model file with progress tracking
    public func downloadModel(_ model: ModelSize, progress: @Sendable @escaping (Double) -> Void) async throws {
        guard let downloadURL = downloadURL(for: model) else {
            throw LocalLLMError.modelNotFound("No download URL configured for \(model.rawValue)")
        }
        
        let destinationURL = modelsDirectory.appendingPathComponent(model.rawValue)
        
        // Check if already exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            throw LocalLLMError.configurationError("Model \(model.rawValue) already exists")
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
    
    private let progressHandler: @Sendable (Double) -> Void
    
    init(progress: @Sendable @escaping (Double) -> Void) {
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
        progressHandler(progress)
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Final 100% progress
        progressHandler(1.0)
    }
}
