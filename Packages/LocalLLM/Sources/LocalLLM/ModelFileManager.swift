//
//  ModelFileManager.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/22/2025.
//

import Foundation

/// Manages downloading and storing local LLM model files
public actor ModelFileManager {
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    
    // Download progress tracking
    public typealias ProgressHandler = @Sendable (Double) -> Void
    private var progressHandlers: [UUID: ProgressHandler] = [:]
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Public API
    
    /// Check if a model is downloaded
    public func isModelDownloaded(_ modelType: LocalModelType) -> Bool {
        guard let path = modelPath(for: modelType) else { return false }
        return fileManager.fileExists(atPath: path.path)
    }
    
    /// Get the file path for a model
    public func modelPath(for modelType: LocalModelType) -> URL? {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsURL.appendingPathComponent("Models/\(modelType.filename)")
    }
    
    /// Get the size of a downloaded model in bytes
    public func modelSize(_ modelType: LocalModelType) -> Int64? {
        guard let path = modelPath(for: modelType),
              let attrs = try? fileManager.attributesOfItem(atPath: path.path),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        return size
    }
    
    /// Download a model from Hugging Face
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
        }
        defer { progressHandlers.removeValue(forKey: progressId) }
        
        // Create Models directory if needed
        guard let destPath = modelPath(for: modelType) else {
            throw ModelDownloadError.invalidPath
        }
        
        let modelsDir = destPath.deletingLastPathComponent()
        try fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        
        // Check if already downloaded
        if fileManager.fileExists(atPath: destPath.path) {
            print("✅ [ModelFileManager] Model already exists: \(modelType.filename)")
            return
        }
        
        print("⬇️ [ModelFileManager] Downloading \(modelType.displayName)...")
        
        // Create download task
        let (tempURL, response) = try await URLSession.shared.download(from: modelType.downloadURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelDownloadError.downloadFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        // Move to final location
        do {
            if fileManager.fileExists(atPath: destPath.path) {
                try fileManager.removeItem(at: destPath)
            }
            try fileManager.moveItem(at: tempURL, to: destPath)
        } catch {
            throw ModelDownloadError.moveFailed(error: error)
        }
        
        // Verify size
        guard let size = modelSize(modelType) else {
            throw ModelDownloadError.verificationFailed
        }
        
        let sizeMB = size / (1024 * 1024)
        guard modelType.expectedSizeMB.contains(sizeMB) else {
            try? fileManager.removeItem(at: destPath)
            throw ModelDownloadError.invalidSize(expected: modelType.expectedSizeMB, actual: sizeMB)
        }
        
        print("✅ [ModelFileManager] Downloaded \(modelType.displayName) (\(sizeMB) MB)")
    }
    
    /// Delete a downloaded model
    public func deleteModel(_ modelType: LocalModelType) throws {
        guard let path = modelPath(for: modelType) else { return }
        if fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
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
