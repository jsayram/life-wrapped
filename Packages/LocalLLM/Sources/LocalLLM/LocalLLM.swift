//
//  LocalLLM.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/17/2025.
//

import Foundation
import SharedModels

/// LocalLLM package for on-device LLM inference using llama.cpp
/// This package provides local model execution without network calls.

// MARK: - Public Interface

/// Configuration for local LLM model
public struct LocalLLMConfiguration: Sendable {
    public let modelName: String
    public let contextSize: Int
    public let temperature: Float
    public let topP: Float
    public let maxTokens: Int
    
    public init(
        modelName: String = "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
        contextSize: Int = 4096,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        maxTokens: Int = 512
    ) {
        self.modelName = modelName
        self.contextSize = contextSize
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
    }
    
    public static let `default` = LocalLLMConfiguration()
}

/// Errors that can occur during local LLM operations
public enum LocalLLMError: Error, Sendable {
    case modelNotFound(String)
    case modelLoadFailed(String)
    case contextCreationFailed
    case generationFailed(String)
    case invalidOutput
    case notInitialized
    case configurationError(String)
    case downloadFailed(String)
}

extension LocalLLMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Model file not found: \(name)"
        case .modelLoadFailed(let message):
            return "Failed to load model: \(message)"
        case .contextCreationFailed:
            return "Failed to create LLM context"
        case .generationFailed(let message):
            return "Text generation failed: \(message)"
        case .invalidOutput:
            return "Model generated invalid output"
        case .notInitialized:
            return "LLM context not initialized"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        }
    }
}
