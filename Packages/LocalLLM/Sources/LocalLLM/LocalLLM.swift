//
//  LocalLLM.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/17/2025.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import SharedModels
@preconcurrency import SwiftLlama

// SwiftLlama models and errors are not annotated Sendable
extension Prompt: @retroactive @unchecked Sendable {}
extension Configuration: @retroactive @unchecked Sendable {}
extension SwiftLlama: @retroactive @unchecked Sendable {}

/// LocalLLM package for on-device LLM inference using llama.cpp
/// This package provides local model execution without network calls.

// MARK: - Public Interface

/// Configuration for local LLM model
public struct LocalLLMConfiguration: Sendable, Equatable {
    public enum Preset: String, CaseIterable, Sendable {
        case speed
        case balanced
        case quality

        public var displayName: String {
            switch self {
            case .speed: return "Speed"
            case .balanced: return "Balanced"
            case .quality: return "Quality"
            }
        }

        public var summary: String {
            switch self {
            case .speed: return "Lowest memory; fastest responses"
            case .balanced: return "Safe default; fits most devices"
            case .quality: return "Largest context; best quality"
            }
        }
    }

    public struct DeviceProfile: Sendable {
        public let memoryGB: Double
        public let isPad: Bool
        public let isLowMemory: Bool
        public let isProClass: Bool

        public static var current: DeviceProfile {
            let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
            #if canImport(UIKit)
            let idiom = UIDevice.current.userInterfaceIdiom
            let isPad = idiom == .pad
            #else
            let isPad = false
            #endif
            let isLowMemory = memoryGB < 5.5
            let isProClass: Bool
            #if canImport(UIKit)
            isProClass = memoryGB >= 7.5 || idiom == .pad
            #else
            isProClass = memoryGB >= 7.5
            #endif
            return DeviceProfile(memoryGB: memoryGB, isPad: isPad, isLowMemory: isLowMemory, isProClass: isProClass)
        }
    }

    public let modelName: String
    public let preset: Preset
    public let contextSize: Int
    public let temperature: Float
    public let topP: Float
    public let maxTokens: Int
    public let systemPrompt: String

    public init(
        modelName: String = "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        preset: Preset = LocalLLMConfiguration.recommendedPreset(),
        contextSize: Int = 2048,  // Safe default matching SwiftLlama defaults
        temperature: Float = 0.7,  // Higher for better reasoning and creativity
        topP: Float = 0.95,
        maxTokens: Int = 2048,  // Doubled for complete summaries
        systemPrompt: String = "You are a helpful AI assistant."
    ) {
        self.modelName = modelName
        self.preset = preset
        self.contextSize = contextSize
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
    }

    public static let `default` = LocalLLMConfiguration.current()
    private static let presetOverrideKey = "localLLM.presetOverride"

    public static func recommendedPreset(for profile: DeviceProfile = .current) -> Preset {
        // Always use quality - auto-optimized for device
        return .quality
    }

    public static func configuration(for preset: Preset) -> LocalLLMConfiguration {
        let profile = DeviceProfile.current
        
        // Auto-optimize based on device capabilities
        // Always maximize quality while respecting device limits
        let contextSize: Int
        let maxTokens: Int
        
        if profile.isLowMemory {
            // Low memory devices (< 5.5 GB) - conservative but still high quality
            contextSize = 2048
            maxTokens = 1024
        } else if profile.isProClass {
            // Pro devices (>= 7.5 GB or iPad) - maximum quality
            contextSize = 4096
            maxTokens = 2560
        } else {
            // Standard devices (5.5-7.5 GB) - high quality
            contextSize = 3072
            maxTokens = 2048
        }
        
        return LocalLLMConfiguration(
            preset: preset,
            contextSize: contextSize,
            temperature: 0.7,   // Higher for better reasoning
            topP: 0.95,
            maxTokens: maxTokens
        )
    }

    public static func recommended(for profile: DeviceProfile = .current) -> LocalLLMConfiguration {
        let preset = recommendedPreset(for: profile)
        return configuration(for: preset)
    }

    public static func current(profile: DeviceProfile = .current) -> LocalLLMConfiguration {
        // Always use auto-optimized quality settings
        return configuration(for: .quality)
    }

    public static func persistPresetOverride(_ preset: Preset?) {
        if let preset {
            UserDefaults.standard.set(preset.rawValue, forKey: presetOverrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: presetOverrideKey)
        }
    }

    public static func loadPresetOverride() -> Preset? {
        guard let raw = UserDefaults.standard.string(forKey: presetOverrideKey) else { return nil }
        return Preset(rawValue: raw)
    }

    public var tokensDescription: String {
        "\(contextSize) ctx • \(maxTokens) max tokens"
    }

    public static func deviceSummary(profile: DeviceProfile = .current) -> String {
        let rounded = String(format: "%.1f", profile.memoryGB)
        let idiomLabel = profile.isPad ? "iPad" : "iPhone"
        let tier = profile.isProClass ? "Pro" : "Standard"
        return "\(idiomLabel) \(tier), \(rounded) GB RAM"
    }
}

/// Errors that can occur during local LLM operations
public enum LocalLLMError: Error, Sendable {
    case modelNotFound(String)
    case modelLoadFailed(String)
    case contextCreationFailed
    case generationFailed(String)
    case invalidOutput
    case notInitialized
    case configurationError(String)
    case downloadFailed(String)
}

extension LocalLLMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Model file not found: \(name)"
        case .modelLoadFailed(let message):
            return "Failed to load model: \(message)"
        case .contextCreationFailed:
            return "Failed to create LLM context"
        case .generationFailed(let message):
            return "Text generation failed: \(message)"
        case .invalidOutput:
            return "Model generated invalid output"
        case .notInitialized:
            return "LLM context not initialized"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        }
    }
}

/// Manages local LLM model files (GGUF format)
public actor ModelFileManager {

    /// Shared singleton instance - use this to track downloads across view recreations
    public static let shared = ModelFileManager()

    /// Directory where models are stored
    private let modelsDirectory: URL

    /// Track which models are currently being downloaded
    private var activeDownloads: Set<ModelSize> = []

    /// Supported model configurations
    public enum ModelSize: String, CaseIterable, Sendable {
        case llama32_3b = "Llama-3.2-3B-Instruct-Q4_K_M.gguf"  // ~2.0GB quantized

        public var displayName: String {
            return "Llama 3.2 3B (4-bit)"
        }

        public var fullDisplayName: String {
            return "Llama 3.2 3B Instruct (Q4_K_M)"
        }

        public var approximateSizeMB: Int {
            return 2048
        }

        public var contextLength: Int {
            return 131072  // 128K context
        }
    }

    public init() {
        // Models stored in Documents/Models directory
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.modelsDirectory = documentsURL.appendingPathComponent("Models", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        // Prevent iCloud backup growth from large model files
        try? markExcludedFromBackup(at: modelsDirectory)
    }

    /// Check if a model file exists locally
    public func isModelAvailable(_ model: ModelSize) -> Bool {
        let modelURL = modelsDirectory.appendingPathComponent(model.rawValue)
        return FileManager.default.fileExists(atPath: modelURL.path)
    }

    /// Get URL for a model file
    public func modelURL(for model: ModelSize) throws -> URL {
        let modelURL = modelsDirectory.appendingPathComponent(model.rawValue)

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw LocalLLMError.modelNotFound(model.rawValue)
        }

        return modelURL
    }

    /// Get file size of a model
    public func modelFileSize(_ model: ModelSize) throws -> Int64 {
        let modelURL = modelsDirectory.appendingPathComponent(model.rawValue)
        let attributes = try FileManager.default.attributesOfItem(atPath: modelURL.path)
        return attributes[.size] as? Int64 ?? 0
    }

    /// Delete a model file to free up space
    public func deleteModel(_ model: ModelSize) throws {
        let modelURL = modelsDirectory.appendingPathComponent(model.rawValue)
        try FileManager.default.removeItem(at: modelURL)
    }

    /// List all available models
    public func availableModels() -> [ModelSize] {
        ModelSize.allCases.filter { isModelAvailable($0) }
    }

    /// Check if a model is currently being downloaded
    public func isDownloading(_ model: ModelSize) -> Bool {
        return activeDownloads.contains(model)
    }

    /// Get the models directory URL for external downloads
    public nonisolated func getModelsDirectory() -> URL {
        return modelsDirectory
    }

    // MARK: - Model Download

    /// Download URLs for models (Hugging Face)
    private func downloadURL(for model: ModelSize) -> URL? {
        switch model {
        case .llama32_3b:
            // Llama 3.2 3B Instruct - higher quality on-device model with 128K context
            return URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")
        }
    }

    /// Download a model file with progress tracking
    public func downloadModel(_ model: ModelSize, progress: @MainActor @Sendable @escaping (Double) -> Void) async throws {
        guard let downloadURL = downloadURL(for: model) else {
            throw LocalLLMError.modelNotFound("No download URL configured for \(model.rawValue)")
        }

        let destinationURL = modelsDirectory.appendingPathComponent(model.rawValue)

        // Check if already exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            throw LocalLLMError.configurationError("Model \(model.rawValue) already exists")
        }

        // Check if already downloading
        if activeDownloads.contains(model) {
            throw LocalLLMError.configurationError("Model \(model.displayName) is already being downloaded")
        }

        // Mark as downloading
        activeDownloads.insert(model)
        defer {
            activeDownloads.remove(model)
        }

        // Create download delegate
        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        // Start download
        let (tempURL, response) = try await session.download(from: downloadURL)

        // Verify response
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LocalLLMError.configurationError("Download failed with response: \(response)")
        }

        // Move to final location
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)

        // Exclude the downloaded model from iCloud backups to avoid quota impact
        try? markExcludedFromBackup(at: destinationURL)

        print("✅ [ModelFileManager] Downloaded \(model.displayName) to \(destinationURL.path)")
    }

    /// Cancel an ongoing download
    public func cancelDownload() {
        // Downloads are managed by caller's Task cancellation
        print("⚠️ [ModelFileManager] Download cancellation requested")
    }

    /// Mark a file or directory as excluded from iCloud backups
    private nonisolated func markExcludedFromBackup(at url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}

// MARK: - Download Delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private let progressHandler: @MainActor @Sendable (Double) -> Void

    init(progress: @MainActor @Sendable @escaping (Double) -> Void) {
        self.progressHandler = progress
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        print("📥 [ModelFileManager] Download progress: \(Int(progress * 100))% (\(totalBytesWritten)/\(totalBytesExpectedToWrite) bytes)")
        MainActor.assumeIsolated {
            progressHandler(progress)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Final 100% progress
        print("✅ [ModelFileManager] Download complete!")
        MainActor.assumeIsolated {
            progressHandler(1.0)
        }
    }
}

/// Minimal SwiftLlama wrapper - following the article's working examples
public actor LlamaContext {

    private var configuration: LocalLLMConfiguration
    private let modelFileManager: ModelFileManager
    private var isLoaded: Bool = false
    private var modelPath: URL?

    // SwiftLlama instance - nonisolated(unsafe) since it manages its own actor
    private nonisolated(unsafe) var llama: SwiftLlama?

    // MARK: - Initialization

    public init(configuration: LocalLLMConfiguration = .default) {
        self.configuration = configuration
        self.modelFileManager = ModelFileManager.shared
        print("🧠 [LlamaContext] Initialized")
    }

    /// Update configuration and reload model
    public func updateConfiguration(_ configuration: LocalLLMConfiguration) async {
        self.configuration = configuration
        if isLoaded {
            await unloadModel()
        }
    }

    // MARK: - Model Loading

    /// Load the model - following article's minimal approach
    public func loadModel() async throws {
        guard !isLoaded else {
            print("ℹ️ [LlamaContext] Already loaded")
            return
        }

        // CRITICAL: Check if running on simulator
        #if targetEnvironment(simulator)
        print("❌ [LlamaContext] Cannot load model on simulator - llama.cpp requires real device")
        throw LocalLLMError.modelLoadFailed("Simulator not supported")
        #endif

        print("📥 [LlamaContext] Loading model...")

        // Check available memory before loading
        let availableMemoryMB = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576.0
        let freeMemoryMB = availableMemoryMB * 0.3 // Estimate ~30% available
        print("💾 [LlamaContext] Available memory: ~\(Int(freeMemoryMB)) MB")
        
        if freeMemoryMB < 1000 {
            print("⚠️ [LlamaContext] Low memory warning - model requires ~800MB")
        }

        // Get model path
        let modelSize = ModelFileManager.ModelSize.llama32_3b
        guard await modelFileManager.isModelAvailable(modelSize) else {
            print("❌ [LlamaContext] Model not available")
            throw LocalLLMError.modelNotFound(configuration.modelName)
        }

        let url = try await modelFileManager.modelURL(for: modelSize)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ [LlamaContext] File not found at path: \(url.path)")
            throw LocalLLMError.modelNotFound("Not found: \(url.path)")
        }

        // Verify file size
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[FileAttributeKey.size] as? Int64 else {
            print("❌ [LlamaContext] Cannot read file attributes")
            throw LocalLLMError.modelLoadFailed("Invalid model file")
        }
        
        let fileSizeMB = fileSize / 1_048_576
        print("📂 [LlamaContext] Model file: \(fileSizeMB) MB")
        
        // Sanity check - 3B model should be ~1.8-2.2 GB (1800-2200 MB)
        guard fileSizeMB > 1700 && fileSizeMB < 2300 else {
            print("❌ [LlamaContext] Invalid file size: \(fileSizeMB) MB (expected ~2000 MB for 3B model)")
            throw LocalLLMError.modelLoadFailed("Corrupted model file")
        }

        print("📂 [LlamaContext] Path: \(url.path)")

        do {
            // Use configuration from LocalLLMConfiguration for optimal performance
            print("⚙️ [LlamaContext] Using config (nCTX=\(configuration.contextSize), temp=\(configuration.temperature), maxTokens=\(configuration.maxTokens))")
            let config = Configuration(
                topK: 40,
                topP: configuration.topP,
                nCTX: configuration.contextSize,
                temperature: configuration.temperature,
                batchSize: 256,  // Higher batch for better throughput
                maxTokenCount: configuration.maxTokens,
                stopTokens: StopToken.llama3  // Llama 3.2 uses llama3 format
            )

            print("🔄 [LlamaContext] Creating SwiftLlama instance...")
            print("   Model path: \(url.path)")
            print("   Stop tokens: \(StopToken.phi)")
            print("   ⏳ This may take 10-30 seconds...")

            // CRITICAL: Wrap in detached task to manage memory; capture Sendable values only
            let modelPath = url.path
            let configCopy = config
            let newLlama = try await Task.detached(priority: .userInitiated) { () -> SwiftLlama in
                try SwiftLlama(modelPath: modelPath, modelConfiguration: configCopy)
            }.value

            self.llama = newLlama
            self.modelPath = url
            isLoaded = true

            print("✅ [LlamaContext] Model loaded successfully!")
        } catch let error as SwiftLlamaError {
            print("❌ [LlamaContext] SwiftLlamaError: \(error)")
            self.llama = nil
            isLoaded = false
            throw LocalLLMError.modelLoadFailed("SwiftLlama error: \(error)")
        } catch {
            print("❌ [LlamaContext] Unexpected error: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(error.localizedDescription)")
            self.llama = nil
            isLoaded = false
            throw LocalLLMError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Unload the model
    public func unloadModel() async {
        guard isLoaded else { return }

        print("📤 [LlamaContext] Unloading model")
        llama = nil
        isLoaded = false
        modelPath = nil
        print("✅ [LlamaContext] Unloaded")
    }

    // MARK: - Text Generation

    /// Generate text with custom system prompt and user message
    public func generate(systemPrompt: String, userMessage: String) async throws -> String {
        guard isLoaded, let llama = self.llama else {
            print("❌ [LlamaContext] Not initialized!")
            throw LocalLLMError.notInitialized
        }

        guard !userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ [LlamaContext] Empty user message!")
            throw LocalLLMError.invalidOutput
        }

        print("🤖 [LlamaContext] Generating with custom system prompt...")
        print("📝 [LlamaContext] System: \(systemPrompt.prefix(100))...")
        print("📝 [LlamaContext] User: \(userMessage.prefix(100))...")

        let startTime = Date()

        do {
            // Create prompt with custom system prompt
            let promptObj = Prompt(
                type: .llama3,  // Llama 3.2 uses llama3 format
                systemPrompt: systemPrompt,
                userMessage: userMessage
            )

            print("🎯 [LlamaContext] Starting generation loop...")

            // Generate using async/await
            var result = ""
            var tokenCount = 0
            for try await token in await llama.start(for: promptObj) {
                result += token
                tokenCount += 1
                if tokenCount % 10 == 0 {
                    print("   Generated \(tokenCount) tokens...")
                }
            }

            let elapsed = Date().timeIntervalSince(startTime)
            print("✅ [LlamaContext] Generated \(result.count) chars (\(tokenCount) tokens) in \(String(format: "%.2f", elapsed))s")

            return result

        } catch let error as SwiftLlamaError {
            print("❌ [LlamaContext] SwiftLlamaError during generation: \(error)")
            throw LocalLLMError.generationFailed(error.localizedDescription)
        } catch {
            print("❌ [LlamaContext] Error during generation: \(error)")
            throw LocalLLMError.generationFailed(error.localizedDescription)
        }
    }

    /// Generate text - legacy method for backward compatibility
    public func generate(prompt: String) async throws -> String {
        guard isLoaded, let llama = self.llama else {
            print("❌ [LlamaContext] Not initialized!")
            throw LocalLLMError.notInitialized
        }

        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ [LlamaContext] Empty prompt!")
            throw LocalLLMError.invalidOutput
        }

        print("🤖 [LlamaContext] Generating...")
        print("📝 [LlamaContext] Prompt: \(prompt.prefix(100))...")

        let startTime = Date()

        do {
            // Create prompt - using Phi format for Phi-3.5 model
            let promptObj = Prompt(
                type: .phi,
                systemPrompt: "You are a helpful AI assistant.",
                userMessage: prompt
            )

            print("🎯 [LlamaContext] Starting generation loop...")

            // Generate using async/await like the article
            var result = ""
            var tokenCount = 0
            for try await token in await llama.start(for: promptObj) {
                result += token
                tokenCount += 1
                if tokenCount % 10 == 0 {
                    print("   Generated \(tokenCount) tokens...")
                }
            }

            let elapsed = Date().timeIntervalSince(startTime)
            print("✅ [LlamaContext] Generated \(result.count) chars (\(tokenCount) tokens) in \(String(format: "%.2f", elapsed))s")

            return result

        } catch let error as SwiftLlamaError {
            print("❌ [LlamaContext] SwiftLlamaError during generation: \(error)")
            throw LocalLLMError.generationFailed("SwiftLlama error: \(error)")
        } catch {
            print("❌ [LlamaContext] Generation failed: \(error)")
            print("   Error type: \(type(of: error))")
            throw LocalLLMError.generationFailed(error.localizedDescription)
        }
    }

    /// Check if ready
    public func isReady() -> Bool {
        return isLoaded && llama != nil
    }

    /// Get configuration
    public func getConfiguration() -> LocalLLMConfiguration {
        return configuration
    }
}
