//
//  LocalModelType.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/22/2025.
//

import Foundation

/// The on-device model behind the Smart summary tier.
///
/// Prompts are sent as chat messages (system + user) and the model's own chat
/// template, shipped with the download, formats them. Nothing in the app hand-writes
/// model-specific tags, so changing models only means changing this file.
public enum LocalModelType: String, Codable, CaseIterable, Sendable {
    case qwen3_4b = "qwen3-4b-instruct-2507"

    /// The model Smart uses
    public static let current: LocalModelType = .qwen3_4b

    public var displayName: String {
        switch self {
        case .qwen3_4b: return "Qwen3 4B"
        }
    }

    /// Hugging Face repository the model is downloaded from
    public var huggingFaceRepo: String {
        switch self {
        case .qwen3_4b: return "mlx-community/Qwen3-4B-Instruct-2507-4bit"
        }
    }

    /// Exact repository commit to download, so every user gets the files the app was tested with
    public var huggingFaceRevision: String {
        switch self {
        case .qwen3_4b: return "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b"
        }
    }

    /// Total size of the repository files at `huggingFaceRevision` (13 files: weights, tokenizer, configs), in bytes
    public var downloadSizeBytes: Int64 {
        switch self {
        case .qwen3_4b: return 2_278_972_236
        }
    }

    /// Download size for display before downloading, for example "~2.3 GB"
    public var downloadSizeDescription: String {
        String(format: "~%.1f GB", Double(downloadSizeBytes) / 1_000_000_000)
    }

    /// Weight file name that must exist for the download to count as complete
    public var weightsFileName: String {
        switch self {
        case .qwen3_4b: return "model.safetensors"
        }
    }

    /// Generation settings.
    /// contextTokens: working window for one request (prompt plus output). The model supports far more,
    /// but on-device memory grows with the window. At 4,096 tokens Qwen3 4B needs about 0.6 GB of cache,
    /// less than Phi-3.5 needed at 2,048.
    public var recommendedConfig: (contextTokens: Int, maxTokens: Int, temperature: Float, topP: Float) {
        switch self {
        case .qwen3_4b:
            return (contextTokens: 4096, maxTokens: 256, temperature: 0.3, topP: 0.8)
        }
    }

    /// Longest prompt (system + user, in characters) sent in one request. About 3,400 tokens,
    /// which leaves room in the context window for the answer.
    public var maxPromptCharacters: Int {
        switch self {
        case .qwen3_4b: return 12_000
        }
    }

    /// Extra end-of-turn tokens. The tokenizer's own end token (<|im_end|>) already stops generation.
    public var extraEOSTokens: Set<String> {
        switch self {
        case .qwen3_4b: return ["<|im_end|>", "<|endoftext|>"]
        }
    }

    /// Text that must never appear in output. If it does, the output is cut there.
    public var stopSequences: [String] {
        switch self {
        case .qwen3_4b: return ["<|im_end|>", "<|endoftext|>", "<|im_start|>"]
        }
    }
}

/// Models Smart used in earlier versions of the app.
/// Only used to find and delete old downloads, never to run anything.
public enum RetiredLocalModel: String, CaseIterable, Sendable {
    case phi35 = "phi-3.5"

    public var huggingFaceRepo: String {
        switch self {
        case .phi35: return "mlx-community/Phi-3.5-mini-instruct-4bit"
        }
    }
}
