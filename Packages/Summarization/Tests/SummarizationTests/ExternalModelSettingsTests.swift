// =============================================================================
// Summarization — External model settings and request tests
// =============================================================================

import Foundation
import Testing
@testable import Summarization

private func freshDefaults() -> UserDefaults {
    let suite = "ExternalModelSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private func errorBody(type: String? = nil, code: String? = nil, message: String? = nil) -> Data {
    var error: [String: Any] = [:]
    if let type { error["type"] = type }
    if let code { error["code"] = code }
    if let message { error["message"] = message }
    return try! JSONSerialization.data(withJSONObject: ["error": error])
}

@Suite("External model settings")
struct ExternalModelSettingsTests {

    @Test("Fresh install uses provider defaults")
    func freshDefaultsUsed() {
        let d = freshDefaults()
        #expect(ExternalModelSettings.provider(defaults: d) == .openai)
        #expect(ExternalModelSettings.model(for: .openai, defaults: d) == "gpt-6-luna")
        #expect(ExternalModelSettings.model(for: .anthropic, defaults: d) == "claude-sonnet-5")
    }

    @Test("Free text model is saved per provider and trimmed")
    func savesPerProvider() {
        let d = freshDefaults()
        ExternalModelSettings.setModel("  gpt-6-sol \n", for: .openai, defaults: d)
        ExternalModelSettings.setModel("claude-opus-5-5", for: .anthropic, defaults: d)
        #expect(ExternalModelSettings.model(for: .openai, defaults: d) == "gpt-6-sol")
        #expect(ExternalModelSettings.model(for: .anthropic, defaults: d) == "claude-opus-5-5")
    }

    @Test("Blank model falls back to default")
    func blankFallsBack() {
        let d = freshDefaults()
        ExternalModelSettings.setModel("gpt-6-sol", for: .openai, defaults: d)
        ExternalModelSettings.setModel("   ", for: .openai, defaults: d)
        #expect(ExternalModelSettings.model(for: .openai, defaults: d) == "gpt-6-luna")
    }

    @Test("Existing user keeps their still-working model after update")
    func migratesWorkingLegacyModel() {
        let d = freshDefaults()
        d.set("Anthropic", forKey: ExternalModelSettings.providerKey)
        d.set("claude-opus-4-5", forKey: ExternalModelSettings.legacyModelKey)
        #expect(ExternalModelSettings.model(for: .anthropic, defaults: d) == "claude-opus-4-5")
        #expect(ExternalModelSettings.model(for: .openai, defaults: d) == "gpt-6-luna")
    }

    @Test("Legacy model goes to the provider it belongs to")
    func migratesToMatchingProvider() {
        let d = freshDefaults()
        d.set("Anthropic", forKey: ExternalModelSettings.providerKey)
        d.set("gpt-4.1", forKey: ExternalModelSettings.legacyModelKey)
        #expect(ExternalModelSettings.model(for: .openai, defaults: d) == "gpt-4.1")
        #expect(ExternalModelSettings.model(for: .anthropic, defaults: d) == "claude-sonnet-5")
    }

    @Test("Retired legacy models are replaced with the default",
          arguments: ["claude-3-5-sonnet-20241022", "claude-sonnet-4-20250514", "claude-3-haiku-20240307", "gpt-3.5-turbo"])
    func retiredModelsReplaced(model: String) {
        let d = freshDefaults()
        d.set(model, forKey: ExternalModelSettings.legacyModelKey)
        let provider = ExternalModelSettings.inferProvider(forModel: model)!
        #expect(ExternalModelSettings.model(for: provider, defaults: d) == ExternalModelSettings.defaultModel(for: provider))
    }

    @Test("Migration runs once and never overwrites a newer choice")
    func migrationRunsOnce() {
        let d = freshDefaults()
        d.set("gpt-4o", forKey: ExternalModelSettings.legacyModelKey)
        _ = ExternalModelSettings.model(for: .openai, defaults: d)
        ExternalModelSettings.setModel("gpt-6-astra", for: .openai, defaults: d)
        d.set("gpt-4o-mini", forKey: ExternalModelSettings.legacyModelKey)
        #expect(ExternalModelSettings.model(for: .openai, defaults: d) == "gpt-6-astra")
    }
}

@Suite("External API requests")
struct ExternalAPIRequestTests {

    @Test("Summary requests never send temperature", arguments: ExternalAPIEngine.Provider.allCases)
    func noTemperature(provider: ExternalAPIEngine.Provider) {
        let body = ExternalAPIEngine.buildRequestBody(provider: provider, model: "m", systemPrompt: "s", userMessage: "u")
        #expect(body["temperature"] == nil)
        #expect(body["model"] as? String == "m")
    }

    @Test("Anthropic request carries system prompt and max_tokens")
    func anthropicBody() {
        let body = ExternalAPIEngine.buildRequestBody(provider: .anthropic, model: "claude-sonnet-5", systemPrompt: "sys", userMessage: "u")
        #expect(body["system"] as? String == "sys")
        #expect(body["max_tokens"] as? Int == 2000)
    }

    @Test("Test request uses the typed model")
    func testBodyUsesModel() {
        let openai = ExternalAPIEngine.buildTestRequestBody(provider: .openai, model: "gpt-6-sol")
        let anthropic = ExternalAPIEngine.buildTestRequestBody(provider: .anthropic, model: "claude-haiku-4-5")
        #expect(openai["model"] as? String == "gpt-6-sol")
        #expect(openai["max_completion_tokens"] as? Int == 16)
        #expect(anthropic["model"] as? String == "claude-haiku-4-5")
        #expect(anthropic["max_tokens"] as? Int == 1)
    }
}

@Suite("Test Connection results")
struct TestConnectionResultTests {

    private func result(_ status: Int, _ body: Data = Data(), provider: ExternalAPIEngine.Provider = .openai) -> ExternalAPIEngine.APIKeyValidationResult {
        ExternalAPIEngine.interpretTestResponse(statusCode: status, data: body, provider: provider, model: "some-model")
    }

    @Test("200 means connected")
    func connected() {
        let r = result(200)
        #expect(r.isValid)
        #expect(r.message.contains("some-model"))
    }

    @Test("401 means bad key")
    func badKey() {
        let r = result(401, errorBody(type: "authentication_error", message: "invalid x-api-key"), provider: .anthropic)
        #expect(!r.isValid)
        #expect(r.message.contains("Invalid API key"))
    }

    @Test("Anthropic 404 means model not found")
    func anthropicModelNotFound() {
        let r = result(404, errorBody(type: "not_found_error", message: "model: claude-nope"), provider: .anthropic)
        #expect(!r.isValid)
        #expect(r.message.contains("wasn't found"))
    }

    @Test("OpenAI model_not_found means model not found")
    func openAIModelNotFound() {
        let r = result(404, errorBody(type: "invalid_request_error", code: "model_not_found", message: "The model `gpt-nope` does not exist"))
        #expect(!r.isValid)
        #expect(r.message.contains("wasn't found"))
    }

    @Test("Out of quota is a failure, plain rate limit is not")
    func quotaVersusRateLimit() {
        #expect(!result(429, errorBody(type: "insufficient_quota", code: "insufficient_quota")).isValid)
        #expect(result(429, errorBody(type: "rate_limit_error")).isValid)
    }

    @Test("Low credit balance reads as billing problem")
    func billing() {
        let r = result(400, errorBody(type: "invalid_request_error", message: "Your credit balance is too low"), provider: .anthropic)
        #expect(!r.isValid)
        #expect(r.message.contains("Billing"))
    }

    @Test("Other 400s are failures, not a false pass")
    func other400() {
        let r = result(400, errorBody(type: "invalid_request_error", message: "max_tokens: too large"), provider: .anthropic)
        #expect(!r.isValid)
    }

    @Test("Server errors say try later")
    func serverError() {
        let r = result(529, errorBody(type: "overloaded_error", message: "Overloaded"), provider: .anthropic)
        #expect(!r.isValid)
        #expect(r.message.contains("Try again later"))
    }
}
