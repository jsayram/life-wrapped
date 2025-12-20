import XCTest
@testable import LocalLLM

/// Minimal harness to isolate the model loading + generation outside the main app.
/// Run on a real device/Mac with the model already downloaded to confirm the stack works.
final class LocalLLMSmokeTests: XCTestCase {

    func testModelLoadAndGenerate() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Simulator does not support llama.cpp; run on device/Mac")
        #endif

        let manager = ModelFileManager.shared
        let model = LocalLLM.ModelFileManager.ModelSize.llama32_1b

        guard await manager.isModelAvailable(model) else {
            throw XCTSkip("Model not downloaded; run after downloading \(model.rawValue)")
        }

        let context = LlamaContext(configuration: .default)

        // Load model
        try await context.loadModel()
        XCTAssertTrue(await context.isReady(), "Context should be ready after load")

        // Generate a tiny response to ensure end-to-end works
        let output = try await context.generate(prompt: "Hello! Summarize: I went for a run and felt great.")
        XCTAssertFalse(output.isEmpty, "Model should return text")
    }
}