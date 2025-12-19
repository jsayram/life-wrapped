//
//  LlamaContext.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/17/2025.
//

import Foundation
import SharedModels
@preconcurrency import SwiftLlama

/// Actor wrapping SwiftLlama for thread-safe LLM inference
/// Note: SwiftLlama uses @SwiftLlamaActor internally, so all inference
/// happens on that actor's thread, not blocking the main thread.
public actor LlamaContext {
    
    private let configuration: LocalLLMConfiguration
    private let modelFileManager: ModelFileManager
    private var isLoaded: Bool = false
    private var modelPath: URL?
    
    // SwiftLlama instance - marked nonisolated(unsafe) because SwiftLlama
    // manages its own thread safety via @SwiftLlamaActor
    private nonisolated(unsafe) var swiftLlama: SwiftLlama?
    
    // MARK: - Initialization
    
    public init(configuration: LocalLLMConfiguration = .default) {
        self.configuration = configuration
        self.modelFileManager = ModelFileManager.shared
        
        print("🧠 [LlamaContext] Initialized with model: \(configuration.modelName)")
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
        let modelSize = ModelFileManager.ModelSize.llama32_1b
        guard await modelFileManager.isModelAvailable(modelSize) else {
            throw LocalLLMError.modelNotFound(configuration.modelName)
        }
        
        // Get model path
        let url = try await modelFileManager.modelURL(for: modelSize)
        modelPath = url
        
        // Initialize SwiftLlama with the model
        // Configure for Qwen2 model with ChatML stop tokens
        let modelConfig = Configuration(
            nCTX: configuration.contextSize,
            temperature: configuration.temperature,
            maxTokenCount: configuration.maxTokens,
            stopTokens: StopToken.chatML
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
        
        // Create a ChatML-format prompt for Qwen2 model
        let llamaPrompt = Prompt(
            type: .chatML,
            systemPrompt: "You are an AI assistant that creates concise summaries of audio journal entries. Always respond with valid JSON only, no explanations.",
            userMessage: prompt
        )
        
        // SwiftLlama.start runs on @SwiftLlamaActor, not blocking main thread
        let response: String = try await llama.start(for: llamaPrompt)
        
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
        
        // Create a ChatML-format prompt for Qwen2 model
        let llamaPrompt = Prompt(
            type: .chatML,
            systemPrompt: "You are an AI assistant that creates concise summaries of audio journal entries. Always respond with valid JSON only, no explanations.",
            userMessage: prompt
        )
        
        // Return SwiftLlama's async stream (runs on SwiftLlamaActor)
        return await llama.start(for: llamaPrompt)
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
