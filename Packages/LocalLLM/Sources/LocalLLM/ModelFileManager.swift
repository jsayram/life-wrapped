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
    
    // MARK: - Placeholder for model download
    
    /// Download a model file (placeholder - will implement in Phase 3)
    public func downloadModel(_ model: ModelSize, progress: @Sendable @escaping (Double) -> Void) async throws {
        // TODO: Implement actual download in Phase 3
        // For now, throw not implemented error
        throw LocalLLMError.modelNotFound("Download not yet implemented. Please manually place \(model.rawValue) in \(modelsDirectory.path)")
    }
}
