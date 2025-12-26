//
//  LocalLLMTests.swift
//  LocalLLMTests
//
//  Created by Life Wrapped on 12/22/2025.
//

import XCTest
@testable import LocalLLM

final class LocalLLMTests: XCTestCase {
    
    func testModelTypeConfiguration() {
        let config = LocalModelType.phi35.recommendedConfig
        XCTAssertEqual(config.nCTX, 1024)
        XCTAssertEqual(config.batch, 128)
        XCTAssertEqual(config.maxTokens, 256)
        XCTAssertEqual(config.temp, 0.2)
    }
    
    func testPromptFormatting() {
        let prompt = PromptType.phi.format(
            system: "You are helpful.",
            user: "Hello"
        )
        
        XCTAssertTrue(prompt.contains("You are helpful."))
        XCTAssertTrue(prompt.contains("<|user|>"))
        XCTAssertTrue(prompt.contains("Hello"))
        XCTAssertTrue(prompt.contains("<|end|>"))
        XCTAssertTrue(prompt.contains("<|assistant|>"))
    }
    
    func testChunkPromptBuilder() {
        let prompt = LocalLLM.buildChunkPrompt(transcript: "Test transcript")
        XCTAssertTrue(prompt.contains("Test transcript"))
        XCTAssertTrue(prompt.contains("summarizer"))
    }
    
    func testConfiguration() {
        let config = LocalLLMConfiguration(modelType: .phi35)
        XCTAssertEqual(config.modelType, .phi35)
        XCTAssertEqual(config.contextSize, 1024)
    }
}
