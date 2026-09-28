//
//  LocalLLMConfiguration.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/22/2025.
//

import Foundation

/// Generation settings for the local model
public struct LocalLLMConfiguration: Sendable {
    public let modelType: LocalModelType
    public let contextTokens: Int
    public let maxTokens: Int
    public let temperature: Float
    public let topP: Float

    public init(
        modelType: LocalModelType = .current,
        contextTokens: Int? = nil,
        maxTokens: Int? = nil,
        temperature: Float? = nil,
        topP: Float? = nil
    ) {
        self.modelType = modelType
        let defaults = modelType.recommendedConfig
        self.contextTokens = contextTokens ?? defaults.contextTokens
        self.maxTokens = maxTokens ?? defaults.maxTokens
        self.temperature = temperature ?? defaults.temperature
        self.topP = topP ?? defaults.topP
    }

    /// Settings for the model Smart uses today
    public static func current() -> LocalLLMConfiguration {
        LocalLLMConfiguration(modelType: .current)
    }
}
