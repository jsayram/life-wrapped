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

/// Main context for MLX-based LLM inference
/// Handles model loading, tokenization, and text generation using Apple's MLX framework
///
/// ⚠️ **Simulator Note:** MLX requires Metal GPU support which is only available on
/// physical Apple Silicon devices. This actor will gracefully handle simulator environments
/// by returning `isRunningOnSimulator = true` and preventing Metal operations.
public actor LlamaContext {
    
    // MARK: - Properties
    
    private var modelContainer: ModelContainer?
    private var modelType: LocalModelType?
    
    private var isModelLoaded = false
    
    /// Check if running on iOS Simulator (MLX/Metal not supported)
    private let isRunningOnSimulator: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()
    
    // MARK: - Initialization
    
    public init() {
        // Only initialize Metal/GPU on real devices - simulators don't support MLX
        #if !targetEnvironment(simulator)
        // Set reasonable memory limits for iOS
        MLX.GPU.set(cacheLimit: 256 * 1024 * 1024) // 256 MB cache
        #else
        print("⚠️ [LlamaContext] Running on simulator - MLX/Metal disabled")
        #endif
    }
    
    // MARK: - Model Management
    
    /// Check if model is loaded and ready
    public func isReady() -> Bool {
        #if targetEnvironment(simulator)
        return false // MLX not available on simulator
        #else
        return isModelLoaded
        #endif
    }
    
    /// Load a model into memory
    public func loadModel(_ modelType: LocalModelType) async throws {
        #if targetEnvironment(simulator)
        print("⚠️ [LlamaContext] Cannot load model on simulator - MLX requires Metal GPU")
        throw LlamaError.metalNotAvailable
        #else
        // Unload existing model if any
        if isModelLoaded {
            unloadModel()
        }
        
        let modelPath = try getModelPath(for: modelType)
        
        // Verify model directory exists
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LlamaError.modelNotFound(path: modelPath)
        }
        
        print("✅ [LlamaContext] Model directory found: \(modelType.displayName)")
        print("📂 [LlamaContext] Path: \(modelPath)")
        
        // Load model using MLX LLM infrastructure
        let modelURL = URL(fileURLWithPath: modelPath)
        let configuration = ModelConfiguration(directory: modelURL)
        
        print("🔄 [LlamaContext] Loading model with MLX...")
        
        // Load model container using MLX LLM factory
        let container = try await LLMModelFactory.shared.loadContainer(configuration: configuration)
        
        self.modelContainer = container
        self.modelType = modelType
        self.isModelLoaded = true
        
        print("✅ [LlamaContext] Model loaded with MLX: \(modelType.displayName)")
        
        // Eval model to ensure weights are loaded
        await container.perform { context in
            eval(context.model)
        }
        
        let config = modelType.recommendedConfig
        print("📊 [LlamaContext] Context size: \(config.nCTX) tokens, Temperature: \(config.temp)")
        #endif
    }
    
    /// Unload the model from memory
    public func unloadModel() {
        modelContainer = nil
        isModelLoaded = false
        modelType = nil
    }
    
    // MARK: - Text Generation
    
    /// Generate text using the loaded model
    /// - Parameters:
    ///   - prompt: The input prompt (already formatted for model type)
    ///   - maxTokens: Maximum tokens to generate (overrides default)
    /// - Returns: Generated text
    /// - Throws: LlamaError if generation fails
    public func generate(prompt: String, maxTokens: Int32? = nil) async throws -> String {
        #if targetEnvironment(simulator)
        throw LlamaError.metalNotAvailable
        #else
        guard isModelLoaded, let container = modelContainer, let modelType = modelType else {
            throw LlamaError.modelNotLoaded
        }
        
        let config = modelType.recommendedConfig
        let maxTokensToGenerate = maxTokens ?? config.maxTokens
        
        print("🔄 [LlamaContext] Generating with temperature: \(config.temp), maxTokens: \(maxTokensToGenerate)")
        print("📝 [LlamaContext] Prompt length: \(prompt.count) characters")
        
        // Validate prompt isn't too large
        guard prompt.count < 8000 else {
            print("⚠️ [LlamaContext] Prompt too large (\(prompt.count) chars), truncating...")
            let truncatedPrompt = String(prompt.prefix(7000)) + "\n\nSummary:"
            return try await generate(prompt: truncatedPrompt, maxTokens: maxTokens)
        }
        
        do {
            // Get stop sequences before the closure to avoid capturing self
            let stopSequences = self.modelType?.stopTokens ?? []
            
            // Generate using MLX with error handling
            let (result, _) = try await container.perform { context in
                // Prepare input
                let input = try await context.processor.prepare(input: .init(prompt: prompt))
                
                // Set generation parameters with conservative settings
                let parameters = GenerateParameters(
                    maxTokens: Int(maxTokensToGenerate),
                    temperature: config.temp,
                    topP: 0.95
                )
                
                // Generate text
                var output = ""
                let stream = try MLXLMCommon.generate(input: input, parameters: parameters, context: context)
            
                for try await item in stream {
                    switch item {
                    case .chunk(let text):
                        output += text
                        
                        // Check for stop sequences
                        var shouldStop = false
                        for stopSeq in stopSequences {
                            if output.contains(stopSeq) {
                                // Trim everything after the stop sequence
                                if let range = output.range(of: stopSeq) {
                                    output = String(output[..<range.lowerBound])
                                }
                                shouldStop = true
                                break
                            }
                        }
                        
                        if shouldStop {
                            break
                        }
                        
                        // Safety check: stop if output gets too long
                        if output.count > 4000 {
                            print("⚠️ [LlamaContext] Output exceeding 4000 chars, stopping generation")
                            break
                        }
                    case .info:
                        break
                    case .toolCall:
                        break
                    }
                }
            
                return (output, ())
            }
        
            print("✅ [LlamaContext] Generated \(result.count) characters")
            return result.trimmingCharacters(in: Foundation.CharacterSet.whitespacesAndNewlines)
            
        } catch {
            print("❌ [LlamaContext] Generation failed: \(error)")
            throw LlamaError.generationFailed(underlying: error)
        }
        #endif
    }
    
    // MARK: - Helpers
    
    private func getModelPath(for modelType: LocalModelType) throws -> String {
        // Use HubApi to get the local repo location
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
        case .modelNotFound(let path):
            return "Model file not found at: \(path). Download the Phi-3.5 model first."
        case .invalidModelSize(let expected, let actual):
            return "Model file size \(actual)MB outside expected range \(expected)MB"
        case .failedToLoadModel:
            return "Failed to load the model"
        case .failedToCreateContext:
            return "Failed to create inference context"
        case .modelNotLoaded:
            return "No model is currently loaded. Download Phi-3.5 in Settings."
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
            return "Local AI requires a physical device with Apple Silicon. Simulators are not supported."
        }
    }
}
