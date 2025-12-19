//
//  LlamaContext.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/17/2025.
//

import Foundation
import SharedModels
@preconcurrency import SwiftLlama

// SwiftLlama models are not annotated Sendable; mark the prompt type as unchecked to satisfy
// region-based isolation checking when crossing actor boundaries.
extension Prompt: @retroactive @unchecked Sendable {}

/// Actor wrapping SwiftLlama for thread-safe LLM inference
/// Note: SwiftLlama uses @SwiftLlamaActor internally, so all inference
/// happens on that actor's thread, not blocking the main thread.
public actor LlamaContext {
    
    private var configuration: LocalLLMConfiguration
    private let modelFileManager: ModelFileManager
    private var isLoaded: Bool = false
    private var modelPath: URL?

    // SwiftLlama instance - keep as nonisolated(unsafe) since SwiftLlama manages its own actor
    private nonisolated(unsafe) var swiftLlama: SwiftLlama?
    
    // MARK: - Initialization
    
    public init(configuration: LocalLLMConfiguration = .default) {
        self.configuration = configuration
        self.modelFileManager = ModelFileManager.shared
        
        print("🧠 [LlamaContext] Initialized with model: \(configuration.modelName)")
    }

    /// Update configuration and unload current model if needed so next load uses new settings
    public func updateConfiguration(_ configuration: LocalLLMConfiguration) async {
        let requiresReload = configuration != self.configuration
        self.configuration = configuration
        if requiresReload && isLoaded {
            await unloadModel()
        }
    }
    
    // MARK: - Model Loading
    
    /// Load the model from disk
    public func loadModel() async throws {
        guard !isLoaded else {
            print("ℹ️ [LlamaContext] Model already loaded")
            return
        }
        
        print("📥 [LlamaContext] Loading model: \(configuration.modelName)")
        
        // Check if model file exists
        let modelSize = ModelFileManager.ModelSize.allCases.first { $0.rawValue == configuration.modelName } ?? .llama32_1b
        guard await modelFileManager.isModelAvailable(modelSize) else {
            throw LocalLLMError.modelNotFound(configuration.modelName)
        }
        
        // Get model path
        let url = try await modelFileManager.modelURL(for: modelSize)
        modelPath = url
        
        // Initialize SwiftLlama with the model
        // Configure for Llama 3.2 with conservative decoding caps
        let modelConfig = Configuration(
            topP: configuration.topP,
            nCTX: configuration.contextSize,
            temperature: configuration.temperature,
            maxTokenCount: configuration.maxTokens,
            stopTokens: StopToken.llama3
        )
        
        do {
            // SwiftLlama handles its own threading via @SwiftLlamaActor
            let llama = try SwiftLlama(modelPath: url.path, modelConfiguration: modelConfig)
            self.swiftLlama = llama
            isLoaded = true
            print("✅ [LlamaContext] Model loaded successfully from: \(url.path)")
        } catch {
            print("❌ [LlamaContext] Failed to load model: \(error)")
            throw LocalLLMError.modelLoadFailed(error.localizedDescription)
        }
    }
    
    /// Unload the model to free memory
    public func unloadModel() async {
        guard isLoaded else { return }
        
        print("📤 [LlamaContext] Unloading model")
        
        swiftLlama = nil
        isLoaded = false
        modelPath = nil
        
        print("✅ [LlamaContext] Model unloaded")
    }
    
    // MARK: - Text Generation
    
    /// Generate text completion from prompt
    /// SwiftLlama runs inference on @SwiftLlamaActor, so this won't block the main thread
    public func generate(prompt: String) async throws -> String {
        guard isLoaded, let llama = swiftLlama else {
            throw LocalLLMError.notInitialized
        }
        
        print("🤖 [LlamaContext] Generating response...")
        print("📝 [LlamaContext] Prompt length: \(prompt.count) characters")
        
        let startTime = Date()
        
        // Cache prompt configuration to avoid isolation issues
        let systemPrompt = configuration.systemPrompt
        
        // SwiftLlama.start runs on @SwiftLlamaActor, not blocking main thread
        let response: String = try await llama.start(
            for: Prompt(
                type: .llama3,
                systemPrompt: systemPrompt,
                userMessage: prompt
            )
        )
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ [LlamaContext] Generated \(response.count) characters in \(String(format: "%.2f", elapsed))s")
        
        return response
    }
    
    /// Generate text with streaming (returns AsyncThrowingStream)
    public func generateStream(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard isLoaded, let llama = swiftLlama else {
            throw LocalLLMError.notInitialized
        }
        
        print("🤖 [LlamaContext] Starting streaming generation...")
        print("📝 [LlamaContext] Prompt length: \(prompt.count) characters")
        
        // Cache prompt configuration to avoid isolation issues
        let systemPrompt = configuration.systemPrompt
        
        // Return SwiftLlama's async stream (runs on SwiftLlamaActor)
        return await llama.start(
            for: Prompt(
                type: .llama3,
                systemPrompt: systemPrompt,
                userMessage: prompt
            )
        )
    }
    
    /// Check if context is ready for inference
    public func isReady() -> Bool {
        return isLoaded && swiftLlama != nil
    }
    
    /// Get current configuration
    public func getConfiguration() -> LocalLLMConfiguration {
        return configuration
    }
}
