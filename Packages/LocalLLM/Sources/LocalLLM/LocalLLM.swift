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
        contextSize: Int = 4096,
        temperature: Float = 0.6,
        topP: Float = 0.9,
        maxTokens: Int = 256,
        systemPrompt: String = "You are an on-device summarization model for Life Wrapped. Respond with concise, well-formed JSON only."
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
                contextSize: 2048,
                temperature: 0.4,
                topP: 0.8,
                maxTokens: 128
            )
        case .balanced:
            return LocalLLMConfiguration(
                preset: .balanced,
                contextSize: 4096,
                temperature: 0.6,
                topP: 0.9,
                maxTokens: 256
            )
        case .quality:
            return LocalLLMConfiguration(
                preset: .quality,
                contextSize: 6144,
                temperature: 0.65,
                topP: 0.92,
                maxTokens: 512
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
