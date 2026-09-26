//
//  LlamaContext.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/22/2025.
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN
import Hub

/// Runs the Smart tier's on-device model with Apple's MLX framework.
/// (The name is historical: the first version used llama.cpp.)
///
/// Prompts go in as chat messages, a system message with the instructions and a user
/// message with the content. MLX formats them with the model's own chat template, which is
/// downloaded with the model, so no model-specific tags are ever written by hand.
///
/// Simulator note: MLX needs a Metal GPU, which the iOS Simulator doesn't provide.
/// On the simulator every call fails with `LlamaError.metalNotAvailable` and callers fall back.
public actor LlamaContext {

    // MARK: - Properties

    private var modelContainer: ModelContainer?
    private var modelType: LocalModelType?
    private var isModelLoaded = false

    // MARK: - Initialization

    public init() {
        #if !targetEnvironment(simulator)
        // Keep MLX's buffer cache small on iPhone
        MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)
        #else
        print("⚠️ [LlamaContext] Running on simulator - MLX/Metal disabled")
        #endif
    }

    // MARK: - Model Management

    /// Whether a model is loaded and ready
    public func isReady() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return isModelLoaded
        #endif
    }

    /// Load a downloaded model into memory
    public func loadModel(_ modelType: LocalModelType) async throws {
        #if targetEnvironment(simulator)
        print("⚠️ [LlamaContext] Cannot load model on simulator - MLX requires Metal GPU")
        throw LlamaError.metalNotAvailable
        #else
        if isModelLoaded {
            unloadModel()
        }

        let modelPath = getModelPath(for: modelType)
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LlamaError.modelNotFound(path: modelPath)
        }

        print("🔄 [LlamaContext] Loading \(modelType.displayName) with MLX from \(modelPath)")

        let configuration = ModelConfiguration(
            directory: URL(fileURLWithPath: modelPath),
            extraEOSTokens: modelType.extraEOSTokens
        )
        let container = try await LLMModelFactory.shared.loadContainer(configuration: configuration)

        self.modelContainer = container
        self.modelType = modelType
        self.isModelLoaded = true

        // Make sure the weights are actually in memory before the first request
        await container.perform { context in
            eval(context.model)
        }

        print("✅ [LlamaContext] Loaded \(modelType.displayName), context window \(modelType.recommendedConfig.contextTokens) tokens")
        #endif
    }

    /// Release the model from memory
    public func unloadModel() {
        modelContainer = nil
        isModelLoaded = false
        modelType = nil
    }

    // MARK: - Text Generation

    /// Generate a reply.
    /// - Parameters:
    ///   - system: Instructions for the model (sent as the system message). Optional.
    ///   - prompt: The content to work on (sent as the user message). Plain text, no chat tags.
    ///   - maxTokens: Most tokens to generate. Defaults to the model's recommended limit.
    /// - Returns: The generated text, trimmed.
    public func generate(system: String? = nil, prompt: String, maxTokens: Int32? = nil) async throws -> String {
        #if targetEnvironment(simulator)
        throw LlamaError.metalNotAvailable
        #else
        guard isModelLoaded, let container = modelContainer, let modelType = modelType else {
            throw LlamaError.modelNotLoaded
        }

        let config = modelType.recommendedConfig
        let maxTokensToGenerate = Int(maxTokens ?? Int32(config.maxTokens))
        let systemText = system ?? ""

        // Keep the request inside the context window. The instructions stay whole;
        // only the content is shortened if it's too long.
        var userText = prompt
        let userBudget = max(modelType.maxPromptCharacters - systemText.count, 500)
        if userText.count > userBudget {
            print("⚠️ [LlamaContext] Prompt too long (\(systemText.count + userText.count) chars), shortening content to \(userBudget) chars")
            userText = String(userText.prefix(userBudget))
        }

        let contentText = userText
        print("🔄 [LlamaContext] Generating: \(systemText.count + contentText.count) chars in, up to \(maxTokensToGenerate) tokens out")

        let stopSequences = modelType.stopSequences
        // Safety net in case the token limit is ever misconfigured
        let maxCharacters = max(4000, maxTokensToGenerate * 8)

        do {
            let result: String = try await container.perform { context in
                var messages: [Chat.Message] = []
                if !systemText.isEmpty {
                    messages.append(.system(systemText))
                }
                messages.append(.user(contentText))

                // The processor applies the model's chat template exactly once
                let input = try await context.processor.prepare(input: UserInput(chat: messages))

                let parameters = GenerateParameters(
                    maxTokens: maxTokensToGenerate,
                    temperature: config.temperature,
                    topP: config.topP
                )

                var output = ""
                let stream = try MLXLMCommon.generate(input: input, parameters: parameters, context: context)

                generation: for try await item in stream {
                    switch item {
                    case .chunk(let text):
                        output += text

                        // Stop at any end-of-turn text that slipped through (labelled break
                        // leaves the loop, not just the switch)
                        if let stop = stopSequences.first(where: { output.contains($0) }),
                           let range = output.range(of: stop) {
                            output = String(output[..<range.lowerBound])
                            break generation
                        }

                        if output.count > maxCharacters {
                            print("⚠️ [LlamaContext] Output passed \(maxCharacters) chars, stopping")
                            break generation
                        }
                    case .info, .toolCall:
                        continue
                    }
                }

                return output
            }

            let cleaned = Self.removeReasoning(from: result)
            print("✅ [LlamaContext] Generated \(cleaned.count) characters")
            return cleaned.trimmingCharacters(in: Foundation.CharacterSet.whitespacesAndNewlines)
        } catch {
            print("❌ [LlamaContext] Generation failed: \(error)")
            throw LlamaError.generationFailed(underlying: error)
        }
        #endif
    }

    // MARK: - Helpers

    /// Qwen3-4B-Instruct-2507 never "thinks" out loud, but if a <think> block ever appears
    /// it must not end up in a summary.
    static func removeReasoning(from text: String) -> String {
        var cleaned = text.replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#,
            with: "",
            options: .regularExpression
        )
        // An unfinished block at the end (output cut off mid-thought)
        if let start = cleaned.range(of: "<think>") {
            cleaned = String(cleaned[..<start.lowerBound])
        }
        return cleaned
    }

    private func getModelPath(for modelType: LocalModelType) -> String {
        let hub = HubApi()
        let repo = HubApi.Repo(id: modelType.huggingFaceRepo)
        return hub.localRepoLocation(repo).path
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
    case generationFailed(underlying: Error)
    case metalNotAvailable  // MLX requires Metal GPU (not available on simulator)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "The Smart model isn't downloaded. Download it in Settings, AI & Summaries."
        case .invalidModelSize(let expected, let actual):
            return "Model file size \(actual)MB outside expected range \(expected)MB"
        case .failedToLoadModel:
            return "Failed to load the model"
        case .failedToCreateContext:
            return "Failed to create inference context"
        case .modelNotLoaded:
            return "The Smart model isn't loaded. Download it in Settings, AI & Summaries."
        case .tokenizationFailed:
            return "Failed to tokenize input"
        case .contextOverflow(let prompt, let ctx):
            return "Prompt (\(prompt) tokens) too long for context (\(ctx) tokens)"
        case .decodeFailed:
            return "Failed to decode model output"
        case .documentsDirectoryNotFound:
            return "Could not access documents directory"
        case .notImplemented:
            return "Feature not yet implemented"
        case .generationFailed(let error):
            return "Text generation failed: \(error.localizedDescription)"
        case .metalNotAvailable:
            return "Smart needs a real iPhone or iPad. It doesn't run in the Simulator."
        }
    }
}
