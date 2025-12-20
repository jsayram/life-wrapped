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
        modelName: String = "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
        preset: Preset = LocalLLMConfiguration.recommendedPreset(),
        contextSize: Int = 2048,  // Safe default matching SwiftLlama defaults
        temperature: Float = 0.2,  // SwiftLlama default
        topP: Float = 0.9,
        maxTokens: Int = 1024,  // SwiftLlama default
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
        if profile.isLowMemory {
            return .speed
        }
        if profile.isProClass {
            return .quality
        }
        return .balanced
    }

    public static func configuration(for preset: Preset) -> LocalLLMConfiguration {
        switch preset {
        case .speed:
            return LocalLLMConfiguration(
                preset: .speed,
                contextSize: 2048,  // SwiftLlama default
                temperature: 0.2,   // SwiftLlama default
                topP: 0.9,
                maxTokens: 512
            )
        case .balanced:
            return LocalLLMConfiguration(
                preset: .balanced,
                contextSize: 2048,  // Safe default
                temperature: 0.2,   // SwiftLlama default
                topP: 0.9,
                maxTokens: 1024     // SwiftLlama default
            )
        case .quality:
            return LocalLLMConfiguration(
                preset: .quality,
                contextSize: 2048,  // Keep same for stability
                temperature: 0.2,   // SwiftLlama default
                topP: 0.9,
                maxTokens: 1024
            )
        }
    }

    public static func recommended(for profile: DeviceProfile = .current) -> LocalLLMConfiguration {
        let preset = recommendedPreset(for: profile)
        return configuration(for: preset)
    }

    public static func current(profile: DeviceProfile = .current) -> LocalLLMConfiguration {
        if let raw = UserDefaults.standard.string(forKey: presetOverrideKey),
           let preset = Preset(rawValue: raw) {
            return configuration(for: preset)
        }
        return recommended(for: profile)
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
        case llama32_1b = "Llama-3.2-1B-Instruct-Q4_K_M.gguf"  // ~771MB quantized

        public var displayName: String {
            return "Llama 3.2 1B (4-bit)"
        }

        public var fullDisplayName: String {
            return "Llama 3.2 1B Instruct (Q4_K_M)"
        }

        public var approximateSizeMB: Int {
            return 771
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
    public func getModelsDirectory() -> URL {
        return modelsDirectory
    }

    // MARK: - Model Download

    /// Download URLs for models (Hugging Face)
    private func downloadURL(for model: ModelSize) -> URL? {
        switch model {
        case .llama32_1b:
            // Llama 3.2 1B Instruct - efficient on-device model with 128K context
            return URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")
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
    private func markExcludedFromBackup(at url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
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

/// Templates for generating LLM prompts optimized for small models
public struct PromptTemplate {

    // MARK: - Session Summary

    /// Generate prompt for session-level summarization
    public static func sessionSummary(transcript: String, duration: TimeInterval, wordCount: Int) -> String {
        let durationMinutes = Int(duration / 60)

        return """
        You are an AI assistant that creates concise summaries of audio journal entries. Extract key information and return valid JSON.

        Transcript (\(wordCount) words, \(durationMinutes) minutes):
        \(transcript)

        Instructions:
        1. Create a 2-3 sentence summary capturing the main points
        2. Extract 3-5 key topics (single words or short phrases, lowercase)
        3. Identify named entities (people, places, organizations, events)
        4. Analyze overall sentiment (-1.0 to 1.0)
        5. Identify 1-2 key moments with timestamps

        Respond ONLY with valid JSON in this exact format:
        {
          "summary": "Brief summary here",
          "topics": ["topic1", "topic2", "topic3"],
          "entities": [
            {"name": "John", "type": "person", "confidence": 0.95}
          ],
          "sentiment": 0.5,
          "keyMoments": [
            {"timestamp": 45.0, "description": "Important point discussed"}
          ]
        }

        JSON:
        """
    }

    // MARK: - Period Summary

    /// Generate prompt for period-level summarization (day/week/month)
    public static func periodSummary(sessionSummaries: [String], periodType: PeriodType, sessionCount: Int) -> String {
        let summariesText = sessionSummaries.enumerated()
            .map { "Session \($0.offset + 1):\n\($0.element)" }
            .joined(separator: "\n\n")

        return """
        You are an AI assistant that creates unified summaries from multiple audio journal entries. Synthesize insights and return valid JSON.

        Period: \(periodType.displayName)
        Sessions: \(sessionCount)

        Individual Session Summaries:
        \(summariesText)

        Instructions:
        1. Create a unified 3-5 sentence summary covering all sessions
        2. Extract the most frequently mentioned topics (5-10 topics)
        3. Consolidate all named entities, removing duplicates
        4. Calculate average sentiment across all sessions
        5. Identify 2-3 overarching themes or trends

        Respond ONLY with valid JSON in this exact format:
        {
          "summary": "Unified summary of the period",
          "topics": ["topic1", "topic2", "topic3"],
          "entities": [
            {"name": "John", "type": "person", "confidence": 0.95}
          ],
          "sentiment": 0.3,
          "trends": ["trend1", "trend2"]
        }

        JSON:
        """
    }

    // MARK: - Extractive Fallback

    /// Simple extractive prompt for when generative fails
    public static func extractiveAnalysis(text: String) -> String {
        return """
        Analyze this text and extract:
        - Main topics (keywords)
        - Named entities (people, places, organizations)
        - Overall sentiment (positive/neutral/negative)

        Text:
        \(text)

        Respond with JSON.
        """
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
        let modelSize = ModelFileManager.ModelSize.llama32_1b
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
              let fileSize = attrs[.size] as? Int64 else {
            print("❌ [LlamaContext] Cannot read file attributes")
            throw LocalLLMError.modelLoadFailed("Invalid model file")
        }
        
        let fileSizeMB = fileSize / 1_048_576
        print("📂 [LlamaContext] Model file: \(fileSizeMB) MB")
        
        // Sanity check - file should be ~770-810 MB
        guard fileSizeMB > 700 && fileSizeMB < 900 else {
            print("❌ [LlamaContext] Invalid file size: \(fileSizeMB) MB (expected ~771 MB)")
            throw LocalLLMError.modelLoadFailed("Corrupted model file")
        }

        print("📂 [LlamaContext] Path: \(url.path)")

        do {
            // MINIMAL CONFIG - exactly like the article's working examples
            // Just stopTokens, everything else uses defaults
            print("⚙️ [LlamaContext] Using minimal config with just stopTokens")
            let config = Configuration(stopTokens: StopToken.llama3)

            print("🔄 [LlamaContext] Creating SwiftLlama instance...")
            print("   Model path: \(url.path)")
            print("   Stop tokens: \(StopToken.llama3)")
            print("   ⏳ This may take 10-30 seconds...")

            // CRITICAL: Wrap in detached task to manage memory
            let newLlama = try await withCheckedThrowingContinuation { continuation in
                Task.detached(priority: .userInitiated) {
                    do {
                        let llama = try SwiftLlama(modelPath: url.path, modelConfiguration: config)
                        continuation.resume(returning: llama)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

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

    /// Generate text - following article's async/await pattern
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
            // Create prompt - exactly like article
            let promptObj = Prompt(
                type: .llama3,
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
