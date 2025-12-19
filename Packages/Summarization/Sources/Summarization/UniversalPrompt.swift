//
//  UniversalPrompt.swift
//  Summarization
//
//  Created by Life Wrapped on 12/18/2025.
//

import Foundation
import SharedModels

// MARK: - Summary Level

/// Hierarchical summarization levels
public enum SummaryLevel: String, Codable, Sendable, CaseIterable {
    case chunk
    case session
    case day
    case week
    case month
    case year
    case yearWrap
    
    public var displayName: String {
        switch self {
        case .chunk: return "Chunk"
        case .session: return "Session"
        case .day: return "Daily"
        case .week: return "Weekly"
        case .month: return "Monthly"
        case .year: return "Yearly"
        case .yearWrap: return "Year Wrap"
        }
    }
    
    /// Convert from PeriodType
    public static func from(periodType: PeriodType) -> SummaryLevel {
        switch periodType {
        case .session: return .session
        case .hour: return .chunk  // Treat hour as chunk level
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        case .yearWrap: return .yearWrap
        }
    }
}

// MARK: - Universal Prompt Builder

/// Universal prompt builder for hierarchical summarization
/// Uses the exact schemas specified in the requirements
public struct UniversalPrompt {
    
    // MARK: - System Prompt (same for all levels)
    
    private static let systemInstruction = """
    You are a private journaling assistant. You summarize faithfully and never invent facts. \
    If something is unclear, write "unclear". No generic motivational fluff.
    """
    
    // MARK: - Schemas per Level
    
    /// Chunk schema - individual audio chunk
    public static let chunkSchema = """
    {
      "headline": "string - one-line headline",
      "summary": "string - 1-2 sentence summary",
      "mood": "positive|neutral|negative|mixed|unclear",
      "topics": ["string array of main topics"],
      "people": ["string array of mentioned people"],
      "actions": ["string array of actions taken"],
      "plans": ["string array of future plans"],
      "open_loops": ["string array of unresolved items"]
    }
    """
    
    /// Session schema - one recording session (multiple chunks)
    public static let sessionSchema = """
    {
      "title": "string - short descriptive title",
      "session_summary": "string - 2-3 sentence summary",
      "key_moments": ["string array of important moments"],
      "mood_arc": "string - how mood changed during session",
      "topics": ["string array of main topics"],
      "people": ["string array of mentioned people"],
      "decisions": ["string array of decisions made"],
      "next_actions": ["string array of planned actions"],
      "open_loops": ["string array of unresolved items"]
    }
    """
    
    /// Daily schema - all sessions from one day
    public static let dailySchema = """
    {
      "daily_headline": "string - one-line day headline",
      "daily_summary": "string - 2-3 sentence summary",
      "top_topics": ["string array of main topics"],
      "wins": ["string array of accomplishments"],
      "stressors": ["string array of stress sources"],
      "health_notes": ["string array of health observations"],
      "relationships": ["string array of relationship notes"],
      "tomorrow_focus": ["string array of priorities for tomorrow"],
      "open_loops": ["string array of unresolved items"]
    }
    """
    
    /// Weekly schema - aggregates daily summaries
    public static let weeklySchema = """
    {
      "weekly_theme": "string - one-line week theme",
      "weekly_summary": "string - 3-4 sentence summary",
      "top_patterns": ["string array of recurring patterns"],
      "wins": ["string array of week's wins"],
      "challenges": ["string array of challenges faced"],
      "notable_events": ["string array of significant events"],
      "habit_trends": {
        "sleep": "string - sleep pattern observation",
        "fitness": "string - fitness observation",
        "diet": "string - diet observation",
        "work": "string - work pattern observation"
      },
      "next_week_intentions": ["string array of goals for next week"],
      "open_loops": ["string array of unresolved items"]
    }
    """
    
    /// Monthly schema - aggregates weekly summaries
    public static let monthlySchema = """
    {
      "month_theme": "string - one-line month theme",
      "month_summary": "string - 4-5 sentence summary",
      "big_wins": ["string array of major accomplishments"],
      "big_challenges": ["string array of major challenges"],
      "progress_markers": ["string array of progress indicators"],
      "recurring_themes": ["string array of repeated themes"],
      "relationships": ["string array of relationship developments"],
      "health_fitness_trends": ["string array of health trends"],
      "next_month_goals": ["string array of goals for next month"],
      "open_loops": ["string array of unresolved items"]
    }
    """
    
    /// Yearly schema - aggregates monthly summaries
    public static let yearlySchema = """
    {
      "year_title": "string - one-line year title",
      "year_summary": "string - 5-6 sentence summary",
      "major_arcs": ["string array of major life arcs"],
      "biggest_wins": ["string array of biggest accomplishments"],
      "biggest_challenges": ["string array of biggest challenges"],
      "key_relationships": ["string array of key relationship changes"],
      "health_overview": ["string array of health observations"],
      "work_learning_overview": ["string array of work/learning highlights"],
      "next_year_focus": ["string array of focus areas for next year"],
      "open_loops": ["string array of unresolved items"]
    }
    """
    
    // MARK: - Schema Selection
    
    public static func schema(for level: SummaryLevel) -> String {
        switch level {
        case .chunk: return chunkSchema
        case .session: return sessionSchema
        case .day: return dailySchema
        case .week: return weeklySchema
        case .month: return monthlySchema
        case .year: return yearlySchema
        case .yearWrap: return yearlySchema
        }
    }
    
    // MARK: - Prompt Builder
    
    /// Build a universal prompt for any summarization level
    /// - Parameters:
    ///   - level: The summarization level (chunk, session, day, week, month, year)
    ///   - input: The input text or JSON to summarize
    ///   - metadata: Optional metadata (duration, word count, session count, etc.)
    /// - Returns: Complete prompt string ready for LLM
    public static func build(
        level: SummaryLevel,
        input: String,
        metadata: [String: Any] = [:]
    ) -> String {
        let schema = schema(for: level)
        
        // Build metadata string if provided
        var metadataStr = ""
        if !metadata.isEmpty {
            let parts = metadata.map { "\($0.key): \($0.value)" }
            metadataStr = "\nMetadata: " + parts.joined(separator: ", ")
        }
        
        return """
        \(systemInstruction)
        
        Task: Summarize at LEVEL = \(level.rawValue).
        Use ONLY the provided INPUT.
        Return VALID JSON that matches the given schema exactly.
        Do not include any extra keys or commentary.
        
        Schema:
        \(schema)
        \(metadataStr)
        
        Input:
        \(input)
        
        JSON Response:
        """
    }
}

// MARK: - Summarization Logging

/// Logs summarization requests for debugging and audit
public struct SummarizationLogger {
    
    /// Log a summarization request with full details
    public static func log(
        level: SummaryLevel,
        engine: EngineTier,
        provider: String?,
        model: String?,
        temperature: Double = 0.3,
        maxTokens: Int = 2000,
        inputSize: Int,
        sessionId: UUID?
    ) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let sessionStr = sessionId.map { $0.uuidString.prefix(8) } ?? "N/A"
        
        print("""
        📊 [Summarization Request]
           ├─ Timestamp: \(timestamp)
           ├─ Level: \(level.displayName)
           ├─ Engine: \(engine.displayName)
           ├─ Provider: \(provider ?? "N/A")
           ├─ Model: \(model ?? "N/A")
           ├─ Temperature: \(temperature)
           ├─ Max Tokens: \(maxTokens)
           ├─ Input Size: \(inputSize)
           └─ Session: \(sessionStr)
        """)
    }
}

// MARK: - Extension for ExternalAPIEngine

extension ExternalAPIEngine {
    
    /// Log summarization request for external API
    internal func logSummarizationRequest(
        level: SummaryLevel,
        provider: Provider,
        model: String,
        inputSize: Int,
        sessionId: UUID?
    ) {
        SummarizationLogger.log(
            level: level,
            engine: .external,
            provider: provider.displayName,
            model: model,
            temperature: 0.7,  // OpenAI/Anthropic default
            maxTokens: 2000,
            inputSize: inputSize,
            sessionId: sessionId
        )
    }
}
