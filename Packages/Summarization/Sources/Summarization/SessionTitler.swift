//
//  SessionTitler.swift
//  Summarization
//
//  Short titles for recordings, so lists show "Test harness for Piccolo Xpress"
//  instead of "Untitled recording". Titles come from the model when one is
//  available and from the summary's own words otherwise.
//

import Foundation

public enum SessionTitler {

    /// Longest title kept, in words
    static let maxWords = 7

    /// A model's title made presentable, or nil if it isn't usable
    public static func clean(_ raw: String?) -> String? {
        guard var title = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        // Copied placeholders and non-titles
        if title.contains("<") || title.contains(">") { return nil }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’*#.:;,- "))
        let lowered = title.lowercased()
        guard !lowered.isEmpty, !lowered.hasPrefix("untitled"), !lowered.contains("the user"), lowered != "title" else { return nil }
        let words = title.split(separator: " ")
        if words.count > maxWords {
            title = words.prefix(maxWords).joined(separator: " ")
        }
        return capitalizedFirst(title)
    }

    /// A title from the summary alone: its first key point or first sentence, shortened
    public static func fallback(summary: String, keyPoints: [String] = []) -> String? {
        // Key Sentences stores single-word topics as key points; one word is not a title
        let source = keyPoints.first { $0.split(separator: " ").count >= 3 }
            ?? summary.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init)
            ?? ""
        var words = source.split(separator: " ").map(String.init)
        // "I created a test harness..." reads better as a title without the leading "I"
        while let first = words.first, leadingFillers.contains(first.lowercased().trimmingCharacters(in: .punctuationCharacters)) {
            words.removeFirst()
        }
        words = Array(words.prefix(6))
        // "...a test harness for the" reads better as "...a test harness"
        while words.count > 2, let last = words.last, trailingFunctionWords.contains(last.lowercased().trimmingCharacters(in: .punctuationCharacters)) {
            words.removeLast()
        }
        guard !words.isEmpty else { return nil }
        return clean(words.joined(separator: " "))
    }

    private static let leadingFillers: Set<String> = [
        "i", "i'm", "i’m", "i've", "i’ve", "today", "so", "okay", "ok", "um", "uh", "yeah", "well", "alright"
    ]

    private static let trailingFunctionWords: Set<String> = [
        "a", "an", "the", "to", "of", "and", "or", "but", "for", "in", "on", "at", "with", "by", "from",
        "my", "your", "our", "their", "his", "her", "its", "is", "was", "are", "were", "be",
        "that", "this", "it", "i", "i'm", "i’m", "so", "then", "if", "as", "about"
    ]

    /// Titles for several recordings in one request. Returns one entry per summary, nil where
    /// the model gave nothing usable; the caller falls back for those.
    public static func titles(for summaries: [String], generator: any TextGenerating) async -> [String?] {
        guard !summaries.isEmpty else { return [] }
        let notes = summaries.enumerated()
            .map { "[\($0 + 1)] \($1.prefix(400))" }
            .joined(separator: "\n")
        let user = """
        Give each of my voice notes below a short title of 3 to 6 words that says what it is about.
        Use only what is written. No quotes, no dates, no "Untitled".

        \(notes)

        Return JSON with one title per note, in order: {"titles":["<title for 1>","<title for 2>"]}
        """
        let system = "You title my voice-journal notes. Return only valid JSON, with no markdown and no commentary."
        guard let output = try? await generator.generateText(system: system, user: user, maxTokens: 40 * summaries.count + 40),
              let json = ModelJSON.object(from: output),
              let titles = json["titles"] as? [Any] else {
            return Array(repeating: nil, count: summaries.count)
        }
        return summaries.indices.map { index in
            index < titles.count ? clean(titles[index] as? String) : nil
        }
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
