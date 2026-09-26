//
//  LocalLLMTests.swift
//  LocalLLMTests
//
//  Created by Life Wrapped on 12/22/2025.
//

import XCTest
@testable import LocalLLM

final class LocalLLMTests: XCTestCase {

    func testCurrentModelIsQwen() {
        let model = LocalModelType.current
        XCTAssertEqual(model, .qwen3_4b)
        XCTAssertEqual(model.displayName, "Qwen3 4B")
        XCTAssertEqual(model.huggingFaceRepo, "mlx-community/Qwen3-4B-Instruct-2507-4bit")
        XCTAssertEqual(model.huggingFaceRevision.count, 40, "Downloads must be pinned to a full commit hash")
    }

    func testDownloadSizeIsDisclosedAccurately() {
        // App Store guideline 4.2.3: the size shown before downloading must be right
        let model = LocalModelType.current
        XCTAssertEqual(model.downloadSizeDescription, "~2.3 GB")
        XCTAssertGreaterThan(model.downloadSizeBytes, 2_000_000_000)
        XCTAssertLessThan(model.downloadSizeBytes, 2_500_000_000)
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
