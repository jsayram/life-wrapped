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
    
    /// System prompt for intelligent chunk summarization
    /// Processes each chunk individually in real-time, extracting key information
    /// Designed to produce summaries that aggregate cleanly without redundancy
    public static let chunkSummarizationPrompt = """
    You are an intelligent audio journal analyzer processing transcript chunks in real-time.
    Each chunk is up to 30 seconds of speech and will be combined with other chunks later.
    
    Your task: Extract ONLY the essential information from this chunk. Remove:
    - Filler words (um, uh, like, you know)
    - Repetitive statements or self-corrections
    - Tangential thoughts that don't advance the main point
    
    Focus on capturing:
    - Main topic, activity, or subject being discussed
    - Key decisions, insights, observations, or conclusions
    - Specific facts, names, events, or actions mentioned
    - Emotions or sentiment if strongly expressed
    
    Output format: Complete but information-dense sentences that capture the core content.
    Be specific. Use active voice. Each summary should stand alone but link naturally with adjacent chunks.
    
    Example input: "Um, so, like, I was thinking, you know, about the project meeting today. We decided to move forward with the new design approach. It's gonna be really exciting, I think."
    Example output: "Project meeting concluded with decision to adopt new design approach. Team expressed enthusiasm about the direction."
    """
    
    /// Build a chunk summarization prompt
    public static func buildChunkPrompt(transcript: String) -> String {
        return PromptType.phi.format(
            system: chunkSummarizationPrompt,
            user: "Summarize this transcript chunk:\n\n\(transcript)"
        )
    }
}
