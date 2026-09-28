//
//  LocalLLM.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/22/2025.
//

import Foundation

// Re-export public types
@_exported import struct Foundation.UUID

/// LocalLLM runs the Smart tier's on-device model (Qwen3 4B, 4-bit) with Apple's MLX framework.
///
/// Usage:
/// ```swift
/// let context = LlamaContext()
/// try await context.loadModel(.current)
///
/// let reply = try await context.generate(
///     system: "You are a helpful assistant.",
///     prompt: "Summarize this text: ..."
/// )
/// ```
///
/// Prompts are plain text. The model's chat template formats the system and user messages,
/// so never add model-specific tags like <|user|> or <|im_start|> yourself.
public enum LocalLLM {
    /// Version of the LocalLLM package
    public static let version = "2.0.0"
}
