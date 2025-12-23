//
//  LocalModelType.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/22/2025.
//

import Foundation

/// Supported local LLM models
public enum LocalModelType: String, Codable, CaseIterable, Sendable {
    case phi35 = "phi-3.5"
    
    public var displayName: String {
        switch self {
        case .phi35: return "Phi-3.5 Mini"
        }
    }
    
    public var modelDirectory: String {
        switch self {
        case .phi35: return "Phi-3.5-mini-instruct-4bit"
        }
    }
    
    public var huggingFaceRepo: String {
        switch self {
        case .phi35: return "mlx-community/Phi-3.5-mini-instruct-4bit"
        }
    }
    
    public var expectedSizeMB: ClosedRange<Int64> {
        switch self {
        case .phi35: return 2000...2500   // ~2.1 GB (4-bit MLX quantization)
        }
    }
    
    /// Context window configuration
    public var recommendedConfig: (nCTX: Int32, batch: Int32, maxTokens: Int32, temp: Float) {
        switch self {
        case .phi35:
            return (nCTX: 2048, batch: 128, maxTokens: 256, temp: 0.2)
        }
    }
    
    /// Stop tokens for this model family
    public var stopTokens: [String] {
        switch self {
        case .phi35: return ["<|end|>"]
        }
    }
}

/// Prompt type for different model families
public enum PromptType: Sendable {
    case phi
    
    /// Format a prompt for this model type
    public func format(system: String, user: String) -> String {
        switch self {
        case .phi:
            return """
            \(system)
            <|user|>
            \(user)
            <|end|>
            <|assistant|>
            """
        }
    }
}
