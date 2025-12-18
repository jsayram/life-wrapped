//
//  LlamaContext.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/17/2025.
//

import Foundation
import SharedModels
@preconcurrency import SwiftLlama

/// Wrapper to make SwiftLlama Sendable for Swift 6
/// SwiftLlama uses its own actor isolation (@SwiftLlamaActor) which is compatible
private final class SwiftLlamaWrapper: @unchecked Sendable {
    let llama: SwiftLlama
    
    init(modelPath: String, configuration: Configuration) throws {
        self.llama = try SwiftLlama(modelPath: modelPath, modelConfiguration: configuration)
    }
}

/// Actor wrapping SwiftLlama for thread-safe LLM inference
public actor LlamaContext {
    
    private let configuration: LocalLLMConfiguration
    private let modelFileManager: ModelFileManager
    private var isLoaded: Bool = false
    private var modelPath: URL?
    private var llamaWrapper: SwiftLlamaWrapper?
    
    // MARK: - Initialization
    
    public init(configuration: LocalLLMConfiguration = .default) {
        self.configuration = configuration
        self.modelFileManager = ModelFileManager.shared
        
        print("🧠 [LlamaContext] Initialized with model: \(configuration.modelName)")
    }
    
    // MARK: - Model Loading
    
    /// Load the model from disk
    /// Model loading is CPU-intensive and runs on a background thread
    public func loadModel() async throws {
        guard !isLoaded else {
            print("ℹ️ [LlamaContext] Model already loaded")
            return
        }
        
        print("📥 [LlamaContext] Loading model: \(configuration.modelName)")
        
        // Check if model file exists
        let modelSize = ModelFileManager.ModelSize.phi35Mini
        guard await modelFileManager.isModelAvailable(modelSize) else {
            throw LocalLLMError.modelNotFound(configuration.modelName)
        }
        
        // Get model path
        let url = try await modelFileManager.modelURL(for: modelSize)
        modelPath = url
        
        // Initialize SwiftLlama with the model
        // Configure for Phi-3.5 model with appropriate stop tokens
        let modelConfig = Configuration(
            nCTX: configuration.contextSize,
            temperature: configuration.temperature,
            maxTokenCount: configuration.maxTokens,
            stopTokens: StopToken.phi
        )
        
        // Run model loading on background thread to prevent UI freezing
        // Loading a 2.4GB model can take several seconds
        let path = url.path
        let wrapper = try await Task.detached(priority: .userInitiated) {
            try SwiftLlamaWrapper(modelPath: path, configuration: modelConfig)
        }.value
        
        self.llamaWrapper = wrapper
        isLoaded = true
        print("✅ [LlamaContext] Model loaded successfully from: \(url.path)")
    }
    
    /// Unload the model to free memory
    public func unloadModel() async {
        guard isLoaded else { return }
        
        print("📤 [LlamaContext] Unloading model")
        
        llamaWrapper = nil
        isLoaded = false
        modelPath = nil
        
        print("✅ [LlamaContext] Model unloaded")
    }
    
    // MARK: - Text Generation
    
    /// Generate text completion from prompt
    /// Runs inference on a background thread to avoid blocking the main thread
    public func generate(prompt: String) async throws -> String {
        guard isLoaded, let wrapper = llamaWrapper else {
            throw LocalLLMError.notInitialized
        }
        
        print("🤖 [LlamaContext] Generating response...")
        print("📝 [LlamaContext] Prompt length: \(prompt.count) characters")
        
        let startTime = Date()
        
        // Create a Phi-format prompt for the model
        let llamaPrompt = Prompt(
            type: .phi,
            systemPrompt: "You are an AI assistant that creates concise summaries of audio journal entries. Always respond with valid JSON only, no explanations.",
            userMessage: prompt
        )
        
        // Run LLM inference on a background thread to prevent UI freezing
        // SwiftLlama's inference is CPU-intensive and can block for seconds
        let response = try await Task.detached(priority: .userInitiated) {
            try await wrapper.llama.start(for: llamaPrompt)
        }.value
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ [LlamaContext] Generated \(response.count) characters in \(String(format: "%.2f", elapsed))s")
        
        return response
    }
    
    /// Generate text with streaming (returns AsyncThrowingStream)
    /// Runs inference on a background thread to avoid blocking the main thread
    public func generateStream(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        guard isLoaded, let wrapper = llamaWrapper else {
            throw LocalLLMError.notInitialized
        }
        
        print("🤖 [LlamaContext] Starting streaming generation...")
        print("📝 [LlamaContext] Prompt length: \(prompt.count) characters")
        
        // Create a Phi-format prompt for the model
        let llamaPrompt = Prompt(
            type: .phi,
            systemPrompt: "You are an AI assistant that creates concise summaries of audio journal entries. Always respond with valid JSON only, no explanations.",
            userMessage: prompt
        )
        
        // Return SwiftLlama's async stream (runs on SwiftLlamaActor)
        return await wrapper.llama.start(for: llamaPrompt)
    }
    
    /// Check if context is ready for inference
    public func isReady() -> Bool {
        return isLoaded && llamaWrapper != nil
    }
    
    /// Get current configuration
    public func getConfiguration() -> LocalLLMConfiguration {
        return configuration
    }
}
