//
//  TextGenerating.swift
//  Summarization
//
//  Raw prompt-in, text-out access to an engine's model, used by the month digest
//  and Year Wrap builders. Basic has no model and doesn't conform; the builders
//  fall back to deterministic extraction for it.
//

import Foundation

public protocol TextGenerating: Sendable {
    var tier: EngineTier { get }

    /// Rough token budget for the input part of one prompt (instructions excluded)
    var inputTokenBudget: Int { get }

    /// Output tokens to ask for when a step needs a long answer
    var outputTokenBudget: Int { get }

    func generateText(system: String, user: String, maxTokens: Int) async throws -> String
}

extension TextGenerating {
    /// Budgets large enough to send a whole year in one request
    var fitsWholeYear: Bool { inputTokenBudget >= 20_000 }
}

/// Same conservative estimate LocalEngine uses: about 3.5 characters per token
func estimatedTokens(_ text: String) -> Int {
    Int((Double(text.count) / 3.5).rounded(.up))
}
