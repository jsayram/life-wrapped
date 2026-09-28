//
//  ExternalModelSettings.swift
//  Summarization
//
//  Single source of truth for the External API provider and model the user picked.
//  Models are free text so users can type any current model ID from OpenAI or Anthropic.
//

import Foundation

public enum ExternalModelSettings {

    // MARK: - Storage keys

    public static let providerKey = "externalAPIProvider"

    /// Pre-1.1 builds stored one model for both providers under this key.
    static let legacyModelKey = "externalAPIModel"
    static let migrationDoneKey = "externalAPIModel.migratedToPerProvider"

    static func modelKey(for provider: ExternalAPIEngine.Provider) -> String {
        switch provider {
        case .openai: return "externalAPIModel.openai"
        case .anthropic: return "externalAPIModel.anthropic"
        }
    }

    // MARK: - Defaults and retired models

    public static func defaultModel(for provider: ExternalAPIEngine.Provider) -> String {
        switch provider {
        case .openai: return "gpt-6-luna"
        case .anthropic: return "claude-sonnet-5"
        }
    }

    /// Model IDs the providers have shut down (or will shortly). A saved value in this
    /// list is replaced with the provider default so summaries keep working.
    static let retiredModels: Set<String> = [
        "gpt-3.5-turbo",
        "claude-3-haiku-20240307",
        "claude-3-5-sonnet-20241022",
        "claude-sonnet-4-20250514",
    ]

    /// Where users can look up valid model IDs.
    public static func modelListURL(for provider: ExternalAPIEngine.Provider) -> URL {
        switch provider {
        case .openai: return URL(string: "https://platform.openai.com/docs/models")!
        case .anthropic: return URL(string: "https://docs.claude.com/en/docs/about-claude/models/overview")!
        }
    }

    public static func placeholder(for provider: ExternalAPIEngine.Provider) -> String {
        "e.g. \(defaultModel(for: provider))"
    }

    // MARK: - Read / write

    public static func provider(defaults: UserDefaults = .standard) -> ExternalAPIEngine.Provider {
        defaults.string(forKey: providerKey).flatMap { ExternalAPIEngine.Provider(rawValue: $0) } ?? .openai
    }

    public static func setProvider(_ provider: ExternalAPIEngine.Provider, defaults: UserDefaults = .standard) {
        defaults.set(provider.rawValue, forKey: providerKey)
    }

    /// The model to use for a provider: the user's saved ID, or the default when
    /// nothing is saved, the value is blank, or the saved ID has been retired.
    public static func model(for provider: ExternalAPIEngine.Provider, defaults: UserDefaults = .standard) -> String {
        migrateIfNeeded(defaults: defaults)
        let saved = normalize(defaults.string(forKey: modelKey(for: provider)) ?? "")
        if saved.isEmpty || retiredModels.contains(saved) {
            return defaultModel(for: provider)
        }
        return saved
    }

    /// Saves a model ID. A blank value clears the choice so the default is used.
    public static func setModel(_ model: String, for provider: ExternalAPIEngine.Provider, defaults: UserDefaults = .standard) {
        let value = normalize(model)
        if value.isEmpty {
            defaults.removeObject(forKey: modelKey(for: provider))
        } else {
            defaults.set(value, forKey: modelKey(for: provider))
        }
    }

    public static func normalize(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Migration from the single legacy key

    /// Moves the model saved by older builds into the matching per-provider slot.
    /// Runs once; safe to call any number of times.
    public static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migrationDoneKey) else { return }
        defer { defaults.set(true, forKey: migrationDoneKey) }

        let legacy = normalize(defaults.string(forKey: legacyModelKey) ?? "")
        guard !legacy.isEmpty, !retiredModels.contains(legacy) else { return }

        let owner = inferProvider(forModel: legacy) ?? provider(defaults: defaults)
        if defaults.string(forKey: modelKey(for: owner)) == nil {
            defaults.set(legacy, forKey: modelKey(for: owner))
        }
    }

    static func inferProvider(forModel model: String) -> ExternalAPIEngine.Provider? {
        let id = model.lowercased()
        if id.hasPrefix("claude") { return .anthropic }
        if id.hasPrefix("gpt") || id.hasPrefix("chatgpt") || id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") {
            return .openai
        }
        return nil
    }
}
