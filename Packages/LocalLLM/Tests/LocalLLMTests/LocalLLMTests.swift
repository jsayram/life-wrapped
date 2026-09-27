//
//  LocalLLMTests.swift
//  LocalLLMTests
//
//  Created by Life Wrapped on 12/22/2025.
//

import XCTest
@testable import LocalLLM

final class LocalLLMTests: XCTestCase {

    func testModelsAreQwen() {
        XCTAssertEqual(LocalModelType.qwen3_4b.displayName, "Qwen3 4B")
        XCTAssertEqual(LocalModelType.qwen3_4b.huggingFaceRepo, "mlx-community/Qwen3-4B-Instruct-2507-4bit")
        XCTAssertEqual(LocalModelType.qwen3_1_7b.displayName, "Qwen3 1.7B")
        XCTAssertEqual(LocalModelType.qwen3_1_7b.huggingFaceRepo, "mlx-community/Qwen3-1.7B-4bit")
        for model in LocalModelType.allCases {
            XCTAssertEqual(model.huggingFaceRevision.count, 40, "Downloads must be pinned to a full commit hash")
        }
    }

    func testModelIsChosenByDeviceMemory() {
        // What devices report: a little under the RAM they're sold with
        let sixGB: UInt64 = 5_900_000_000
        let fourGB: UInt64 = 3_900_000_000
        let threeGB: UInt64 = 2_900_000_000
        XCTAssertEqual(LocalModelType.forDevice(physicalMemory: 8_000_000_000), .qwen3_4b)
        XCTAssertEqual(LocalModelType.forDevice(physicalMemory: sixGB), .qwen3_4b)
        XCTAssertEqual(LocalModelType.forDevice(physicalMemory: fourGB), .qwen3_1_7b)
        // 3 GB devices get the small model's settings but can't run it, so Smart isn't offered
        XCTAssertEqual(LocalModelType.forDevice(physicalMemory: threeGB), .qwen3_1_7b)
        XCTAssertGreaterThan(LocalModelType.qwen3_1_7b.minimumDeviceMemoryBytes, threeGB)
        XCTAssertLessThanOrEqual(LocalModelType.qwen3_1_7b.minimumDeviceMemoryBytes, fourGB)
    }

    func testDownloadSizeIsDisclosedAccurately() {
        // App Store guideline 4.2.3: the size shown before downloading must be right
        XCTAssertEqual(LocalModelType.qwen3_4b.downloadSizeDescription, "~2.3 GB")
        XCTAssertEqual(LocalModelType.qwen3_1_7b.downloadSizeDescription, "~1.0 GB")
    }

    func testSmallModelFitsInFreeMemoryOfA4GBPhone() {
        // A 4 GB phone gives one app roughly 2 GB before iOS ends it
        XCTAssertLessThan(LocalModelType.qwen3_1_7b.requiredFreeMemoryBytes, 2_000_000_000)
    }

    func testOnlyHybridModelHasThinkingTurnedOff() {
        XCTAssertNil(LocalModelType.qwen3_4b.chatTemplateContext)
        XCTAssertEqual(LocalModelType.qwen3_1_7b.chatTemplateContext?["enable_thinking"] as? Bool, false)
    }

    func testGenerationSettings() {
        let config = LocalModelType.current.recommendedConfig
        XCTAssertEqual(config.contextTokens, 4096)
        XCTAssertEqual(config.maxTokens, 256)
        XCTAssertEqual(config.temperature, 0.3, accuracy: 0.001)
        XCTAssertEqual(config.topP, 0.8, accuracy: 0.001)
        // The prompt limit must leave room for an answer inside the context window
        // (about 3.5 characters per token)
        let promptTokens = LocalModelType.current.maxPromptCharacters * 2 / 7
        XCTAssertLessThan(promptTokens + config.maxTokens, config.contextTokens)
    }

    func testStopSequencesMatchQwenNotPhi() {
        let stops = LocalModelType.current.stopSequences
        XCTAssertTrue(stops.contains("<|im_end|>"))
        XCTAssertFalse(stops.contains("<|end|>"), "Phi-3.5 tags must not be used with Qwen")
        XCTAssertFalse(stops.contains("<|user|>"))
    }

    func testPhiIsRetired() {
        XCTAssertEqual(RetiredLocalModel.allCases.map(\.huggingFaceRepo), ["mlx-community/Phi-3.5-mini-instruct-4bit"])
        XCTAssertFalse(LocalModelType.allCases.map(\.huggingFaceRepo).contains("mlx-community/Phi-3.5-mini-instruct-4bit"))
    }

    func testReasoningBlocksAreRemoved() {
        XCTAssertEqual(LlamaContext.removeReasoning(from: "<think>\nplanning\n</think>\n\nThe summary."), "\n\nThe summary.")
        XCTAssertEqual(LlamaContext.removeReasoning(from: "The summary.<think>cut off"), "The summary.")
        XCTAssertEqual(LlamaContext.removeReasoning(from: "No reasoning here."), "No reasoning here.")
    }

    func testDownloadProgressFollowsBytes() {
        // Setup files fill the first 1%, the weights fill the rest, and the two steps meet
        XCTAssertEqual(ModelFileManager.overallProgress(setupFiles: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(ModelFileManager.overallProgress(setupFiles: 1), 0.01, accuracy: 0.0001)
        XCTAssertEqual(ModelFileManager.overallProgress(weights: 0), 0.01, accuracy: 0.0001)
        XCTAssertEqual(ModelFileManager.overallProgress(weights: 0.5), 0.505, accuracy: 0.0001)
        XCTAssertEqual(ModelFileManager.overallProgress(weights: 1), 1, accuracy: 0.0001)
        // Out-of-range input never pushes the bar outside 0...1
        XCTAssertEqual(ModelFileManager.overallProgress(weights: 1.2), 1, accuracy: 0.0001)
        XCTAssertEqual(ModelFileManager.overallProgress(setupFiles: -0.1), 0, accuracy: 0.0001)
    }

    func testWeightsFilesAreSeparatedFromSetupFiles() {
        XCTAssertTrue(ModelFileManager.isWeightsFile("model.safetensors"))
        XCTAssertTrue(ModelFileManager.isWeightsFile("model-00001-of-00002.safetensors"))
        XCTAssertFalse(ModelFileManager.isWeightsFile("model.safetensors.index.json"))
        XCTAssertFalse(ModelFileManager.isWeightsFile("tokenizer.json"))
        XCTAssertFalse(ModelFileManager.isWeightsFile("chat_template.jinja"))
    }

    func testConfigurationDefaults() {
        let config = LocalLLMConfiguration()
        XCTAssertEqual(config.modelType, .current)
        XCTAssertEqual(config.contextTokens, 4096)
        XCTAssertEqual(config.maxTokens, 256)
    }
}
