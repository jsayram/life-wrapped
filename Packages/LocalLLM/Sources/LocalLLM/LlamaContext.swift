//
//  LlamaContext.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/22/2025.
//
//  NOTE: This is a stub implementation. Full llama.cpp integration
//  requires a stable Swift wrapper. For now, this provides the interface
//  and uses extractive summarization as a fallback.
//

import Foundation

/// Thread-safe wrapper around llama.cpp for local LLM inference
/// Currently uses extractive fallback - full llama.cpp implementation requires stable Swift bindings
public actor LlamaContext {
    
    // MARK: - Properties
    
    private var isModelLoaded = false
    private var currentModelType: LocalModelType = .phi35
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Model Management
    
    /// Check if a model is loaded and ready
    public func isReady() -> Bool {
        return isModelLoaded
    }
    
    /// Get the currently loaded model type
    public func currentModel() -> LocalModelType {
        return currentModelType
    }
    
    /// Load a model from disk
    /// - Parameter modelType: The model type to load
    /// - Throws: LlamaError if loading fails
    public func loadModel(_ modelType: LocalModelType = .phi35) async throws {
        currentModelType = modelType
        
        // Get model path from app's Documents directory
        let modelPath = try getModelPath(for: modelType)
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LlamaError.modelNotFound(path: modelPath)
        }
        
        // Verify file size is reasonable
        let fileSize = try FileManager.default.attributesOfItem(atPath: modelPath)[.size] as? Int64 ?? 0
        let expectedRange = modelType.expectedSizeMB
        let fileSizeMB = fileSize / (1024 * 1024)
        
        guard expectedRange.contains(fileSizeMB) else {
            throw LlamaError.invalidModelSize(expected: expectedRange, actual: fileSizeMB)
        }
        
        // Mark as loaded if file exists with correct size
        isModelLoaded = true
        print("✅ [LlamaContext] Model file verified: \(modelType.displayName) (\(fileSizeMB) MB)")
        print("⚠️ [LlamaContext] Using extractive fallback - full llama.cpp integration pending")
    }
    
    /// Unload the current model
    public func unloadModel() {
        isModelLoaded = false
    }
    
    // MARK: - Text Generation
    
    /// Generate text using the loaded model
    /// Currently uses extractive summarization as fallback
    /// - Parameters:
    ///   - prompt: The input prompt (already formatted for model type)
    ///   - maxTokens: Maximum tokens to generate (overrides default)
    /// - Returns: Generated text
    /// - Throws: LlamaError if generation fails
    public func generate(prompt: String, maxTokens: Int32? = nil) async throws -> String {
        guard isModelLoaded else {
            throw LlamaError.modelNotLoaded
        }
        
        // Extract the transcript text from the structured prompt
        // The prompt format is:
        // <system prompt>
        // <|user|>
        // Summarize this transcript chunk:
        //
        // <transcript text>
        // <|end|>
        // <|assistant|>
        
        var transcriptText = ""
        
        // Find the text after "Summarize this transcript chunk:"
        if let range = prompt.range(of: "Summarize this transcript chunk:") {
            let afterMarker = prompt[range.upperBound...]
            // Get the text before the next special token
            if let endRange = afterMarker.range(of: "<|end|>") {
                transcriptText = String(afterMarker[..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                transcriptText = String(afterMarker)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        if transcriptText.isEmpty {
            return "Content recorded."
        }
        
        // Simple extractive summary: take first 1-2 meaningful sentences
        let sentences = transcriptText.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.split(separator: " ").count >= 3 }
        
        let summary = sentences.prefix(2).joined(separator: ". ")
        return summary.isEmpty ? "Content recorded." : summary + "."
    }
    
    // MARK: - Helpers
    
    private func getModelPath(for modelType: LocalModelType) throws -> String {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw LlamaError.documentsDirectoryNotFound
        }
        return documentsURL.appendingPathComponent("Models/\(modelType.filename)").path
    }
}

// MARK: - Errors

public enum LlamaError: Error, LocalizedError {
    case modelNotFound(path: String)
    case invalidModelSize(expected: ClosedRange<Int64>, actual: Int64)
    case failedToLoadModel
    case failedToCreateContext
    case modelNotLoaded
    case tokenizationFailed
    case contextOverflow(promptTokens: Int32, contextSize: Int32)
    case decodeFailed
    case documentsDirectoryNotFound
    case notImplemented
    
    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Model file not found at: \(path). Download the Phi-3.5 model first."
        case .invalidModelSize(let expected, let actual):
            return "Model file size \(actual)MB outside expected range \(expected)MB"
        case .failedToLoadModel:
            return "Failed to load the model"
        case .failedToCreateContext:
            return "Failed to create inference context"
        case .modelNotLoaded:
            return "No model is currently loaded. Download Phi-3.5 in Settings."
        case .tokenizationFailed:
            return "Failed to tokenize input"
        case .contextOverflow(let prompt, let ctx):
            return "Prompt (\(prompt) tokens) too long for context (\(ctx) tokens)"
        case .decodeFailed:
            return "Failed to decode tokens"
        case .documentsDirectoryNotFound:
            return "Documents directory not found"
        case .notImplemented:
            return "llama.cpp integration not yet implemented"
        }
    }
}
