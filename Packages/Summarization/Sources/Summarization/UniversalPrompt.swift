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
    You are an AI journaling assistant for Life Wrapped, a private voice journaling app.

    CONTEXT:
    - Users record spoken thoughts throughout their day via audio
    - Audio is transcribed to text using on-device speech recognition
    - You analyze transcribed speech to extract meaningful insights
    - All processing happens on-device for privacy
    - Sessions may be categorized as 'Work' or 'Personal' for context

    YOUR ROLE:
    - Convert raw, messy spoken transcripts into clean, structured first-person journal notes
    - Preserve meaning and intent while removing speech artifacts (repetition, false starts, filler)
    - Capture concrete next steps, decisions, observations, and open questions
    - Respect the session category (work vs personal) when determining tone, focus, and relevant details

    VOICE & PERSPECTIVE (HARD RULES):
    - Write strictly in first person as if I wrote it: “I”, “me”, “my”
    - NEVER use: “the user”, “they”, “them”, “their”, “he/she”, “the person”
    - Do not describe me from the outside. Do not narrate about me. Write as me.

    FIDELITY (HARD RULES):
    - Use ONLY information present in the transcript
    - Do NOT invent tasks, facts, timelines, emotions, or motivations
    - Do NOT add psychological interpretation (“I’m anxious”, “I’m overwhelmed”) unless explicitly stated
    - If something is unclear, keep it as uncertainty instead of guessing
    - If I contradict myself or trail off, reflect that as ambiguity (briefly)

    ANTI-FLUFF:
    - No generic self-help language
    - No motivational coaching tone
    - No vague abstractions unless the transcript is already vague
    - Prefer concrete nouns/verbs: buttons, pages, bugs, decisions, next steps

    COMPLETENESS (AVOID OVER-COMPRESSION):
    - Do not drop action items or important details
    - Do not merge distinct tasks into one generic item
    - Preserve exploratory or tentative ideas (label them clearly as “considering”, “maybe”, “not sure yet”)
    - Preserve “not working yet / needs fixing” states when mentioned

    WHAT TO PRODUCE (KEY BEHAVIOR):
    You are not doing a one-line executive summary. You are producing a cleaned-up journal note that is:
    - faithful to the original transcript
    - readable
    - structured
    - complete

    PROCESS (INTERNAL CHECKLIST):
    1) Identify all explicit action items (things I need to do)
    2) Identify issues/bugs/problems mentioned
    3) Identify decisions made vs. options being considered
    4) Identify anything explicitly “not done yet / not working yet”
    5) Rewrite in first person, remove filler/repetition, keep meaning
    6) Final check: no third-person words, no invented content, no dropped tasks

    OUTPUT FORMAT:
    - Return VALID JSON matching the provided schema exactly
    - No extra keys, no commentary, no markdown
    - Just the JSON object
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
    "title": "3-5 word descriptive title (no 'user', no third-person)",
    "summary": "FIRST-PERSON cleaned rewrite of what I said. Remove filler/repetition/false starts, but KEEP all distinct tasks, ideas, and uncertainties. Do not invent anything. Do not use third-person.",
    "key_points": ["Distinct point 1", "Distinct point 2", "..."]
    }

    IMPORTANT FOR session summaries:
    - This is ORGANIZED VOICE NOTES (a cleaned rewrite), not analysis
    - Write in first person only: I / me / my
    - NEVER say: the user, they, them, their, he, she
    - Keep the transcript meaning faithful, but make it grammatically correct and clear
    - Remove speech artifacts (repetition, stutters, “um”, “ok ok”), without removing content
    - Do NOT over-summarize: do NOT collapse multiple tasks into one vague sentence
    - Preserve tentative language when present: “I’m considering…”, “Not sure yet…”, “This isn’t working yet…”
    - Do NOT interpret or add emotions/insights that weren’t said
    - Organize logically (by topic or sequence) so someone reading understands what happened

    KEY_POINTS RULES:
    - key_points must include EVERY distinct:
    - task / next step
    - bug / issue
    - decision
    - idea being considered
    - “not working yet” item
    - Keep each bullet specific and separate (no merging)
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
    
    /// Yearly schema - aggregates monthly summaries (enhanced for Year Wrap)
    public static let yearlySchema = """
    {
      "year_title": "string - one-line year title",
      "year_summary": "string - 5-6 sentence summary",
      "major_arcs": [{"text": "string", "category": "work|personal|both"}],
      "biggest_wins": [{"text": "string", "category": "work|personal|both"}],
      "biggest_losses": [{"text": "string", "category": "work|personal|both"}],
      "biggest_challenges": [{"text": "string", "category": "work|personal|both"}],
      "finished_projects": [{"text": "string", "category": "work|personal|both"}],
      "unfinished_projects": [{"text": "string", "category": "work|personal|both"}],
      "top_worked_on_topics": [{"text": "string", "category": "work|personal|both"}],
      "top_talked_about_things": [{"text": "string", "category": "work|personal|both"}],
      "valuable_actions_taken": [{"text": "string", "category": "work|personal|both"}],
      "opportunities_missed": [{"text": "string", "category": "work|personal|both"}],
      "people_mentioned": [{"name": "string", "relationship": "string", "impact": "string - how they influenced the year"}],
      "places_visited": [{"name": "string", "frequency": "string - once/occasionally/frequently", "context": "string - why visited"}]
    }
    
    IMPORTANT: For all items (major_arcs, biggest_wins, etc.), classify each as "work", "personal", or "both":
    - "work": Clearly work-related (projects, colleagues, career achievements)
    - "personal": Clearly personal (hobbies, family, personal growth)
    - "both": Mixed or spans both domains
    
    Be thoughtful about classification - use context from transcripts to determine work vs personal nature.
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
    
    /// Build separate system and user messages for better LLM prompting
    /// - Parameters:
    ///   - level: The summarization level (chunk, session, day, week, month, year)
    ///   - input: The input text or JSON to summarize
    ///   - metadata: Optional metadata (duration, word count, session count, etc.)
    /// - Returns: Tuple of (systemPrompt, userMessage)
    public static func buildMessages(
        level: SummaryLevel,
        input: String,
        metadata: [String: Any] = [:]
    ) -> (system: String, user: String) {
        let schema = schema(for: level)
        
        // Build metadata string if provided
        var metadataStr = ""
        if !metadata.isEmpty {
            let parts = metadata.map { "\($0.key): \($0.value)" }
            metadataStr = "\nMetadata: " + parts.joined(separator: ", ")
        }
        
        // Add special instructions for Year Wrap level
        let specialInstructions = level == .yearWrap ? """
        
        YEAR WRAP SPECIAL INSTRUCTIONS:
        - Extract people and places from entities mentioned in monthly summaries (filter for confidence ≥0.7 if available)
        - Classify projects as 'finished' vs 'unfinished' by keywords: 'completed', 'finished', 'done' vs 'abandoned', 'gave up', 'still working', 'ongoing'
        - Rank topics and talked-about-things by frequency across all months (like Spotify's Top Artists)
        - Look for losses, failures, and setbacks in addition to wins
        - Identify valuable actions (decisions made, habits formed) and opportunities missed (regrets mentioned)
        - For people: extract name, relationship type (friend/colleague/family), and their impact on the year
        - For places: note how often visited (once/occasionally/frequently) and context (work/vacation/family)
        """ : ""
        
        let userMessage = """
        Task: Summarize at LEVEL = \(level.rawValue).
        Use ONLY the provided INPUT below.
        Return VALID JSON matching this schema exactly:
        
        \(schema)
        \(metadataStr)\(specialInstructions)
        
        INPUT:
        \(input)
        
        IMPORTANT: 
        - Output MUST be valid JSON with no extra text before or after
        - Do NOT wrap in markdown code blocks (no ```json)
        - Do NOT add explanations or commentary
        - Start your response with { and end with }
        - Follow the exact field names in the schema
        """
        
        return (system: systemInstruction, user: userMessage)
    }
    
    /// Build a universal prompt for any summarization level (legacy single-string format)
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
        let messages = buildMessages(level: level, input: input, metadata: metadata)
        return """
        \(messages.system)
        
        \(messages.user)
        
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
