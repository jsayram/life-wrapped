//
//  LocalLLMConfiguration.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/22/2025.
//

import Foundation

/// Configuration for the local LLM
public struct LocalLLMConfiguration: Sendable {
    public let modelType: LocalModelType
    public let contextSize: Int32
    public let batchSize: Int32
    public let maxTokens: Int32
    public let temperature: Float
    
    public init(
        modelType: LocalModelType = .phi35,
        contextSize: Int32? = nil,
        batchSize: Int32? = nil,
        maxTokens: Int32? = nil,
        temperature: Float? = nil
    ) {
        self.modelType = modelType
        let defaults = modelType.recommendedConfig
        self.contextSize = contextSize ?? defaults.nCTX
        self.batchSize = batchSize ?? defaults.batch
        self.maxTokens = maxTokens ?? defaults.maxTokens
        self.temperature = temperature ?? defaults.temp
    }
    
    /// Get current configuration from UserDefaults
    public static func current() -> LocalLLMConfiguration {
        let modelRaw = UserDefaults.standard.string(forKey: "localLLMModel") ?? LocalModelType.phi35.rawValue
        let modelType = LocalModelType(rawValue: modelRaw) ?? .phi35
        return LocalLLMConfiguration(modelType: modelType)
    }
    
    /// Save configuration to UserDefaults
    public func save() {
        UserDefaults.standard.set(modelType.rawValue, forKey: "localLLMModel")
    }
}
