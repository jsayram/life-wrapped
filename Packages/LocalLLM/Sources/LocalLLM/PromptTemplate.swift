//
//  PromptTemplate.swift
//  LocalLLM
//
//  Created by Life Wrapped on 12/17/2025.
//

import Foundation
import SharedModels

/// Templates for generating LLM prompts optimized for small models
public struct PromptTemplate {
    
    // MARK: - Session Summary
    
    /// Generate prompt for session-level summarization
    public static func sessionSummary(transcript: String, duration: TimeInterval, wordCount: Int) -> String {
        let durationMinutes = Int(duration / 60)
        
        return """
        You are an AI assistant that creates concise summaries of audio journal entries. Extract key information and return valid JSON.
        
        Transcript (\(wordCount) words, \(durationMinutes) minutes):
        \(transcript)
        
        Instructions:
        1. Create a 2-3 sentence summary capturing the main points
        2. Extract 3-5 key topics (single words or short phrases, lowercase)
        3. Identify named entities (people, places, organizations, events)
        4. Analyze overall sentiment (-1.0 to 1.0)
        5. Identify 1-2 key moments with timestamps
        
        Respond ONLY with valid JSON in this exact format:
        {
          "summary": "Brief summary here",
          "topics": ["topic1", "topic2", "topic3"],
          "entities": [
            {"name": "John", "type": "person", "confidence": 0.95}
          ],
          "sentiment": 0.5,
          "keyMoments": [
            {"timestamp": 45.0, "description": "Important point discussed"}
          ]
        }
        
        JSON:
        """
    }
    
    // MARK: - Period Summary
    
    /// Generate prompt for period-level summarization (day/week/month)
    public static func periodSummary(sessionSummaries: [String], periodType: PeriodType, sessionCount: Int) -> String {
        let summariesText = sessionSummaries.enumerated()
            .map { "Session \($0.offset + 1):\n\($0.element)" }
            .joined(separator: "\n\n")
        
        return """
        You are an AI assistant that creates unified summaries from multiple audio journal entries. Synthesize insights and return valid JSON.
        
        Period: \(periodType.displayName)
        Sessions: \(sessionCount)
        
        Individual Session Summaries:
        \(summariesText)
        
        Instructions:
        1. Create a unified 3-5 sentence summary covering all sessions
        2. Extract the most frequently mentioned topics (5-10 topics)
        3. Consolidate all named entities, removing duplicates
        4. Calculate average sentiment across all sessions
        5. Identify 2-3 overarching themes or trends
        
        Respond ONLY with valid JSON in this exact format:
        {
          "summary": "Unified summary of the period",
          "topics": ["topic1", "topic2", "topic3"],
          "entities": [
            {"name": "John", "type": "person", "confidence": 0.95}
          ],
          "sentiment": 0.3,
          "trends": ["trend1", "trend2"]
        }
        
        JSON:
        """
    }
    
    // MARK: - Extractive Fallback
    
    /// Simple extractive prompt for when generative fails
    public static func extractiveAnalysis(text: String) -> String {
        return """
        Analyze this text and extract:
        - Main topics (keywords)
        - Named entities (people, places, organizations)
        - Overall sentiment (positive/neutral/negative)
        
        Text:
        \(text)
        
        Respond with JSON.
        """
    }
}
