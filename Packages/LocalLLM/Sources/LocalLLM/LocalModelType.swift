//
//  LocalModelType.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/22/2025.
//

import Foundation

/// The on-device model behind the Smart summary tier.
///
/// Devices with 6 GB of memory or more run Qwen3 4B. Phones with 4 GB (iPhone 12, 12 mini, 13,
/// 13 mini, SE 3rd gen) can't fit it, so they run the smaller Qwen3 1.7B.
///
/// Prompts are sent as chat messages (system + user) and the model's own chat
/// template, shipped with the download, formats them. Nothing in the app hand-writes
/// model-specific tags, so changing models only means changing this file.
public enum LocalModelType: String, Codable, CaseIterable, Sendable {
    case qwen3_4b = "qwen3-4b-instruct-2507"
    case qwen3_1_7b = "qwen3-1.7b"

    /// The model Smart uses on this device
    public static let current: LocalModelType = forDevice(physicalMemory: DeviceMemory.physicalBytes)

    /// The biggest model that fits a device with this much RAM. On devices too small for either,
    /// this is the smaller one, and `DeviceMemory.canRun` says it can't run.
    public static func forDevice(physicalMemory: UInt64) -> LocalModelType {
        physicalMemory >= qwen3_4b.minimumDeviceMemoryBytes ? .qwen3_4b : .qwen3_1_7b
    }

    public var displayName: String {
        switch self {
        case .qwen3_4b: return "Qwen3 4B"
        case .qwen3_1_7b: return "Qwen3 1.7B"
        }
    }

    /// Hugging Face repository the model is downloaded from
    public var huggingFaceRepo: String {
        switch self {
        case .qwen3_4b: return "mlx-community/Qwen3-4B-Instruct-2507-4bit"
        case .qwen3_1_7b: return "mlx-community/Qwen3-1.7B-4bit"
        }
    }

    /// Exact repository commit to download, so every user gets the files the app was tested with
    public var huggingFaceRevision: String {
        switch self {
        case .qwen3_4b: return "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b"
        case .qwen3_1_7b: return "3b1b1768f8f8cf8351c712464f906e86c2b8269e"
        }
    }

    /// Total size of the repository files at `huggingFaceRevision` (weights, tokenizer, configs), in bytes
    public var downloadSizeBytes: Int64 {
        switch self {
        case .qwen3_4b: return 2_278_972_236   // 13 files
        case .qwen3_1_7b: return 984_015_687   // 11 files
        }
    }

    /// Download size for display before downloading, for example "~2.3 GB"
    public var downloadSizeDescription: String {
        String(format: "~%.1f GB", Double(downloadSizeBytes) / 1_000_000_000)
    }

    /// Least device RAM this model runs on. Devices report a little under what they're sold with,
    /// so the limits sit between sizes: 5 GiB splits 6 GB devices from 4 GB ones, and 3 GiB splits
    /// 4 GB devices from 3 GB ones (iPhone XR, SE 2nd gen), which get no Smart at all.
    public var minimumDeviceMemoryBytes: UInt64 {
        switch self {
        case .qwen3_4b: return 5 * 1024 * 1024 * 1024
        case .qwen3_1_7b: return 3 * 1024 * 1024 * 1024
        }
    }

    /// Free memory the app needs right before loading: the weights plus the cache for a full
    /// 4,096-token window (about 0.6 GB for 4B, 0.5 GB for 1.7B). Estimated, not measured on
    /// every device, so check the load logs on a real iPhone when changing models.
    public var requiredFreeMemoryBytes: UInt64 {
        switch self {
        case .qwen3_4b: return UInt64(downloadSizeBytes) + 600_000_000
        case .qwen3_1_7b: return UInt64(downloadSizeBytes) + 500_000_000
        }
    }

    /// Weight file name that must exist for the download to count as complete
    public var weightsFileName: String {
        switch self {
        case .qwen3_4b, .qwen3_1_7b: return "model.safetensors"
        }
    }

    /// Generation settings.
    /// contextTokens: working window for one request (prompt plus output). The model supports far more,
    /// but on-device memory grows with the window. At 4,096 tokens Qwen3 4B needs about 0.6 GB of cache,
    /// less than Phi-3.5 needed at 2,048.
    public var recommendedConfig: (contextTokens: Int, maxTokens: Int, temperature: Float, topP: Float) {
        switch self {
        case .qwen3_4b, .qwen3_1_7b:
            return (contextTokens: 4096, maxTokens: 256, temperature: 0.3, topP: 0.8)
        }
    }

    /// Longest prompt (system + user, in characters) sent in one request. About 3,400 tokens,
    /// which leaves room in the context window for the answer.
    public var maxPromptCharacters: Int {
        switch self {
        case .qwen3_4b, .qwen3_1_7b: return 12_000
        }
    }

    /// Extra end-of-turn tokens. The tokenizer's own end token (<|im_end|>) already stops generation.
    public var extraEOSTokens: Set<String> {
        switch self {
        case .qwen3_4b, .qwen3_1_7b: return ["<|im_end|>", "<|endoftext|>"]
        }
    }

    /// Extra values for the model's chat template. Qwen3 1.7B thinks out loud by default, which
    /// would spend the output budget on reasoning, so its template is told not to.
    /// Qwen3-4B-Instruct-2507 never thinks and needs nothing.
    public var chatTemplateContext: [String: any Sendable]? {
        switch self {
        case .qwen3_4b: return nil
        case .qwen3_1_7b: return ["enable_thinking": false]
        }
    }

    /// Text that must never appear in output. If it does, the output is cut there.
    public var stopSequences: [String] {
        switch self {
        case .qwen3_4b, .qwen3_1_7b: return ["<|im_end|>", "<|endoftext|>", "<|im_start|>"]
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
