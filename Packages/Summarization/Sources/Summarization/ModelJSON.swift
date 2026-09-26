//
//  ModelJSON.swift
//  Summarization
//
//  Language models often wrap JSON in markdown fences or add a sentence before it.
//  This pulls out the JSON object so the response is parsed instead of being
//  shown to the user as raw text.
//

import Foundation

enum ModelJSON {

    /// Returns the JSON object contained in a model response, or nil if there is none.
    static func object(from text: String) -> [String: Any]? {
        for candidate in candidates(from: text) {
            if let data = candidate.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        }
        return nil
    }

    private static func candidates(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = [trimmed]

        // ```json ... ``` or ``` ... ```
        if let fenceStart = trimmed.range(of: "```") {
            let afterFence = trimmed[fenceStart.upperBound...]
            let bodyStart = afterFence.firstIndex(of: "\n").map { afterFence.index(after: $0) } ?? afterFence.startIndex
            if let fenceEnd = afterFence[bodyStart...].range(of: "```") {
                result.append(String(afterFence[bodyStart..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        // Outermost { ... }
        if let open = trimmed.firstIndex(of: "{"), let close = trimmed.lastIndex(of: "}"), open < close {
            result.append(String(trimmed[open...close]))
        }
        return result
    }
}
