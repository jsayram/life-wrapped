//
//  LocalLLM.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/22/2025.
//

import Foundation

// Re-export public types
@_exported import struct Foundation.UUID

/// LocalLLM provides on-device LLM inference using llama.cpp with Phi-3.5
///
/// Usage:
/// ```swift
/// let context = LlamaContext()
/// try await context.loadModel(.phi35)
///
/// let prompt = PromptType.phi.format(
///     system: "You are a helpful assistant.",
///     user: "Summarize this text: ..."
/// )
/// let response = try await context.generate(prompt: prompt)
/// ```
public enum LocalLLM {
    /// Version of the LocalLLM package
    public static let version = "1.0.0"
    
    /// System prompt for chunk summarization
    public static let chunkSummarizationPrompt = """
    You are a concise summarizer for audio journal transcripts. Extract the key points from the transcript.
    Output a brief 1-2 sentence summary focusing on the main topic or activity discussed.
    Do not include timestamps or filler words. Be direct and clear.
    """
    
    /// Build a chunk summarization prompt
    public static func buildChunkPrompt(transcript: String) -> String {
        return PromptType.phi.format(
            system: chunkSummarizationPrompt,
            user: "Summarize this transcript chunk:\n\n\(transcript)"
        )
    }
}
