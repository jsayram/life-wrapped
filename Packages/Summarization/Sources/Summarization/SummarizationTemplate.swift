// =============================================================================
// Summarization — Prompt Templates
// =============================================================================

import Foundation

/// Templates and configurations for generating summaries
public struct SummarizationTemplate: Sendable {
    public let name: String
    public let systemPrompt: String
    public let userPromptTemplate: String
    public let maxWords: Int
    public let includeEmotionalTone: Bool
    public let includeKeyTopics: Bool
    
    public init(
        name: String,
        systemPrompt: String,
        userPromptTemplate: String,
        maxWords: Int = 150,
        includeEmotionalTone: Bool = true,
        includeKeyTopics: Bool = true
    ) {
        self.name = name
        self.systemPrompt = systemPrompt
        self.userPromptTemplate = userPromptTemplate
        self.maxWords = maxWords
        self.includeEmotionalTone = includeEmotionalTone
        self.includeKeyTopics = includeKeyTopics
    }
}

/// Predefined templates for common summary types
public enum SummarizationTemplates {
    
    /// Template for daily summaries
    public static let daily = SummarizationTemplate(
        name: "daily",
        systemPrompt: """
        You are a helpful assistant that creates concise, insightful daily summaries from voice journal transcripts. \
        Focus on key activities, emotions, and meaningful moments. Be empathetic and preserve the user's authentic voice.
        """,
        userPromptTemplate: """
        Create a brief daily summary from this voice journal transcript:
        
        Date: {date}
        Transcript:
        {content}
        
        Provide a summary that captures:
        - Main activities and events
        - Emotional tone and feelings
        - Key topics or themes
        - Notable insights or reflections
        
        Keep it under {maxWords} words and write in a warm, personal tone.
        """,
        maxWords: 150
    )
    
    /// Template for weekly summaries
    public static let weekly = SummarizationTemplate(
        name: "weekly",
        systemPrompt: """
        You are a helpful assistant that creates weekly summaries from daily voice journal entries. \
        Identify patterns, growth, and recurring themes across the week. Highlight progress and challenges.
        """,
        userPromptTemplate: """
        Create a weekly summary from these voice journal entries:
        
        Week of: {startDate} to {endDate}
        Transcripts:
        {content}
        
        Provide a summary that captures:
        - Major themes and patterns across the week
        - Emotional journey and mood trends
        - Key accomplishments or challenges
        - Personal growth or insights
        
        Keep it under {maxWords} words and write in an encouraging, reflective tone.
        """,
        maxWords: 250
    )
    
    /// Template for custom summaries
    public static let custom = SummarizationTemplate(
        name: "custom",
        systemPrompt: """
        You are a helpful assistant that creates personalized summaries from voice journal transcripts. \
        Adapt your tone and focus based on the user's content and needs.
        """,
        userPromptTemplate: """
        Create a summary from this voice journal content:
        
        {content}
        
        Provide a thoughtful summary in under {maxWords} words.
        """,
        maxWords: 200
    )
    
    /// Get template by name
    public static func template(named name: String) -> SummarizationTemplate? {
        switch name.lowercased() {
        case "daily": return daily
        case "weekly": return weekly
        case "custom": return custom
        default: return nil
        }
    }
}
