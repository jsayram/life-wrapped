import Foundation
import SharedModels
import Storage
import Summarization
import InsightsRollup

/// Manages all summary generation: session summaries, period summaries, and Year Wrap
@MainActor
public final class SummaryCoordinator {
    
    // MARK: - Dependencies
    
    private let databaseManager: DatabaseManager
    private let summarizationEngine: SummarizationCoordinator
    private let insightsManager: InsightsManager
    
    // MARK: - State
    
    /// Track which period summaries are currently being generated (prevent duplicates)
    private var generatingPeriodSummaries: Set<String> = []
    
    // MARK: - Callbacks
    
    /// Called when period summaries are updated (for widget refresh, etc.)
    public var onPeriodSummariesUpdated: (() async -> Void)?
    
    // MARK: - Constants
    
    private let expectedLocalModelSizeMB: Double = 3800
    public let localModelDisplayName = "Qwen2.5-3B-Instruct 4-bit"
    
    // MARK: - Initialization
    
    public init(
        databaseManager: DatabaseManager,
        summarizationEngine: SummarizationCoordinator,
        insightsManager: InsightsManager
    ) {
        self.databaseManager = databaseManager
        self.summarizationEngine = summarizationEngine
        self.insightsManager = insightsManager
    }
    
    // MARK: - Session Summaries
    
    /// Check if all chunks in a session are transcribed and generate session summary
    public func checkAndGenerateSessionSummary(for sessionId: UUID) async {
        print("🔔 [SummaryCoordinator] === CHECK AND GENERATE SESSION SUMMARY TRIGGERED ===")
        print("📌 [SummaryCoordinator] Session ID: \(sessionId)")
        
        do {
            // Check if all chunks are transcribed
            print("1️⃣ [SummaryCoordinator] Checking if session transcription is complete...")
            let isComplete = try await databaseManager.isSessionTranscriptionComplete(sessionId: sessionId)
            print("🔍 [SummaryCoordinator] Session \(sessionId) transcription complete: \(isComplete)")
            
            guard isComplete else {
                print("⏳ [SummaryCoordinator] ⏸️  Session \(sessionId) not yet complete, skipping summary generation")
                return
            }
            
            print("✅ [SummaryCoordinator] Session transcription is complete!")
            
            // Check if summary already exists
            print("2️⃣ [SummaryCoordinator] Checking if summary already exists...")
            if let existingSummary = try await databaseManager.fetchSummaryForSession(sessionId: sessionId) {
                print("ℹ️ [SummaryCoordinator] ✋ Summary already exists for session \(sessionId)")
                print("📝 [SummaryCoordinator] Existing summary: \(existingSummary.text.prefix(50))...")
                print("🚫 [SummaryCoordinator] Skipping regeneration (summary already exists)")
                return
            }
            
            print("✅ [SummaryCoordinator] No existing summary found - will generate new one")
            
            // Generate session summary
            print("3️⃣ [SummaryCoordinator] 🚀 Triggering session summary generation...")
            try await generateSessionSummary(sessionId: sessionId)
            print("✅ [SummaryCoordinator] ✨ Session summary generated and period summaries updated")
            
            // Unload model after session is complete to free memory
            let localEngine = await summarizationEngine.getLocalEngine()
            print("🧹 [SummaryCoordinator] Unloading Local AI model after session completion...")
            await localEngine.unloadModel()
            print("✅ [SummaryCoordinator] Model memory freed, reducing thermal and battery impact")
            
        } catch {
            print("❌ [SummaryCoordinator] ⚠️ Failed to check/generate session summary: \(error)")
            print("❌ [SummaryCoordinator] Error details: \(error.localizedDescription)")
        }
    }
    
    /// Generate a summary for an entire session
    public func generateSessionSummary(sessionId: UUID, forceRegenerate: Bool = false, includeNotes: Bool = false) async throws {
        print("🚀 [SummaryCoordinator] === GENERATING SESSION SUMMARY ===")
        print("📌 [SummaryCoordinator] Session ID: \(sessionId)")
        print("🔄 [SummaryCoordinator] Force regenerate: \(forceRegenerate)")
        print("📝 [SummaryCoordinator] Include notes: \(includeNotes)")
        
        print("✅ [SummaryCoordinator] Dependencies initialized")
        
        // Get all transcript segments for the session
        print("🔍 [SummaryCoordinator] Fetching transcript segments...")
        let allSegments = try await fetchSessionTranscript(sessionId: sessionId)
        
        // Combine all text
        var fullText = allSegments.map { $0.text }.joined(separator: " ")
        
        // Optionally append user notes if requested
        if includeNotes {
            print("📝 [SummaryCoordinator] includeNotes=true, fetching metadata...")
            if let metadata = try? await databaseManager.fetchSessionMetadata(sessionId: sessionId) {
                print("📝 [SummaryCoordinator] Metadata fetched: title=\(metadata.title ?? "nil"), notes=\(metadata.notes ?? "nil"), notesLength=\(metadata.notes?.count ?? 0), category=\(metadata.category?.displayName ?? "nil")")
                if let notes = metadata.notes, !notes.isEmpty {
                    print("📝 [SummaryCoordinator] ✅ Appending user notes (\(notes.count) chars) to transcript for summary generation")
                    print("📝 [SummaryCoordinator] Notes preview: \(notes.prefix(100))...")
                    fullText += "\n\nAdditional context from user notes:\n\(notes)"
                } else {
                    print("📝 [SummaryCoordinator] ⚠️ Notes are empty or nil, not appending")
                }
                
                // Add category context to transcript if present
                if let category = metadata.category {
                    print("🏷️ [SummaryCoordinator] ✅ Adding category context: \(category.displayName)")
                    fullText = "[Recording Category: \(category.displayName.uppercased())]\n\n" + fullText
                }
            } else {
                print("❌ [SummaryCoordinator] Failed to fetch metadata for session")
            }
        } else {
            print("📝 [SummaryCoordinator] includeNotes=false, checking for category...")
            // Even if notes are not included, we still want category for AI context
            if let metadata = try? await databaseManager.fetchSessionMetadata(sessionId: sessionId),
               let category = metadata.category {
                print("🏷️ [SummaryCoordinator] ✅ Adding category context: \(category.displayName)")
                fullText = "[Recording Category: \(category.displayName.uppercased())]\n\n" + fullText
            }
        }
        
        let wordCount = fullText.split(separator: " ").count
        
        print("📊 [SummaryCoordinator] Session transcript: \(allSegments.count) segments, \(wordCount) words")
        print("📝 [SummaryCoordinator] First 100 chars: \(fullText.prefix(100))...")
        
        guard wordCount > 0 else {
            print("❌ [SummaryCoordinator] No transcript text found - cannot generate summary")
            throw NSError(domain: "SummaryCoordinator", code: -1, userInfo: [NSLocalizedDescriptionKey: "No transcript text"])
        }
        
        // Calculate hash of transcript content for cache checking
        let inputHash = calculateHash(for: fullText)
        
        // Check if we can skip regeneration (cache hit)
        if !forceRegenerate {
            if let existingSummary = try? await databaseManager.fetchSummaryForSession(sessionId: sessionId) {
                if let existingHash = existingSummary.inputHash, existingHash == inputHash {
                    print("✅ [SummaryCoordinator] Summary cache HIT - transcript unchanged, skipping regeneration")
                    print("🔑 [SummaryCoordinator] Hash match: \(inputHash.prefix(8))...")
                    return
                } else {
                    print("🔄 [SummaryCoordinator] Summary cache MISS - transcript changed, regenerating")
                    if let existingHash = existingSummary.inputHash {
                        print("🔑 [SummaryCoordinator] Old hash: \(existingHash.prefix(8))..., New hash: \(inputHash.prefix(8))...")
                    }
                }
            }
        } else {
            print("🔄 [SummaryCoordinator] Forced regeneration - skipping cache check")
        }
        
        // Get session time range
        let chunks = try await databaseManager.fetchChunksBySession(sessionId: sessionId)
        guard let firstChunk = chunks.first, let lastChunk = chunks.last else {
            print("❌ [SummaryCoordinator] No chunks found for session")
            return
        }
        
        let periodStart = firstChunk.startTime
        let periodEnd = lastChunk.endTime
        
        // If force regenerating, use smart clearing for Local AI (only clears changed chunks)
        if forceRegenerate {
            let localEngine = await summarizationEngine.getLocalEngine()
            
            // Build array of (chunkId, transcriptText) for smart cache clearing
            var chunkTexts: [(id: UUID, text: String)] = []
            for chunk in chunks {
                let segments = try await databaseManager.fetchTranscriptSegments(audioChunkID: chunk.id)
                let transcriptText = segments.map { $0.text }.joined(separator: " ")
                chunkTexts.append((id: chunk.id, text: transcriptText))
            }
            
            // Smart cache clearing: only invalidates chunks whose text hash changed
            let chunksNeedingReprocessing = await localEngine.clearChangedChunkSummaries(for: chunkTexts)
            print("🗑️ [SummaryCoordinator] Smart clear: \(chunksNeedingReprocessing.count) of \(chunks.count) chunks need reprocessing")
        }
        
        // Use the user's active engine (respects their settings choice)
        let activeEngine = await summarizationEngine.getActiveEngine()
        print("🧠 [SummaryCoordinator] Using active summarization engine: \(activeEngine.displayName)")
        
        // Generate summary using coordinator (returns Summary with structured data)
        print("🌐 [SummaryCoordinator] 🚀 CALLING LLM API - Summarizing \(wordCount) words from session...")
        var generatedSummary = try await summarizationEngine.generateSessionSummary(sessionId: sessionId, segments: allSegments)
        
        print("✅ [SummaryCoordinator] LLM API returned summary (engine: \(generatedSummary.engineTier ?? "unknown"), text length: \(generatedSummary.text.count))")
        print("📝 [SummaryCoordinator] Summary preview: \(generatedSummary.text.prefix(100))...")
        
        // Update time range and include inputHash for caching
        generatedSummary = Summary(
            id: generatedSummary.id,
            periodType: .session,
            periodStart: periodStart,
            periodEnd: periodEnd,
            text: generatedSummary.text,
            createdAt: generatedSummary.createdAt,
            sessionId: sessionId,
            topicsJSON: generatedSummary.topicsJSON,
            entitiesJSON: generatedSummary.entitiesJSON,
            engineTier: generatedSummary.engineTier,
            sourceIds: generatedSummary.sourceIds,
            inputHash: inputHash  // Store hash for future cache checks
        )
        
        // Delete old session summary if it exists (to prevent duplicates in rollups)
        if let existingSummary = try? await databaseManager.fetchSummaryForSession(sessionId: sessionId) {
            print("🗑️ [SummaryCoordinator] Deleting old session summary (ID: \(existingSummary.id))...")
            try await databaseManager.deleteSummary(id: existingSummary.id)
            print("✅ [SummaryCoordinator] Old session summary deleted")
        }
        
        // Save session summary
        print("💾 [SummaryCoordinator] Saving summary to database...")
        try await databaseManager.insertSummary(generatedSummary)
        print("✅ [SummaryCoordinator] Session summary saved successfully!")
        print("📊 [SummaryCoordinator] Summary details - topics: \(generatedSummary.topicsJSON?.prefix(50) ?? "none")")
        
        // Update period summaries (daily, weekly, monthly)
        print("📅 [SummaryCoordinator] Updating period summaries...")
        await updatePeriodSummaries(sessionId: sessionId, sessionDate: periodStart)
        
        // Notify callback
        await onPeriodSummariesUpdated?()
        
        print("🎉 [SummaryCoordinator] === SESSION SUMMARY COMPLETE ===")
        
        // Unload Local AI model from memory to free resources
        let localEngine = await summarizationEngine.getLocalEngine()
        print("🧹 [SummaryCoordinator] Unloading Local AI model to free memory...")
        await localEngine.unloadModel()
        print("✅ [SummaryCoordinator] Model unloaded, memory released")
    }
    
    /// Append user notes to existing session summary without AI regeneration
    public func appendNotesToSessionSummary(sessionId: UUID, notes: String) async throws {
        // Get existing summary
        guard let existingSummary = try await databaseManager.fetchSummaryForSession(sessionId: sessionId) else {
            throw NSError(domain: "SummaryCoordinator", code: -1, userInfo: [NSLocalizedDescriptionKey: "No summary found for session"])
        }
        
        // Append notes to summary text
        let updatedText = existingSummary.text + "\n\nAdditional Notes:\n" + notes
        
        // Create updated summary with new text
        let updatedSummary = Summary(
            id: existingSummary.id,
            periodType: existingSummary.periodType,
            periodStart: existingSummary.periodStart,
            periodEnd: existingSummary.periodEnd,
            text: updatedText,
            createdAt: existingSummary.createdAt,
            sessionId: existingSummary.sessionId,
            topicsJSON: existingSummary.topicsJSON,
            entitiesJSON: existingSummary.entitiesJSON,
            engineTier: existingSummary.engineTier,
            sourceIds: existingSummary.sourceIds,
            inputHash: existingSummary.inputHash
        )
        
        // Delete old and insert updated
        try await databaseManager.deleteSummary(id: existingSummary.id)
        try await databaseManager.insertSummary(updatedSummary)
        
        print("✅ [SummaryCoordinator] Appended notes to session summary")
    }
    
    // MARK: - Helper Methods for Sessions
    
    /// Fetch transcript segments for an entire session (all chunks combined)
    private func fetchSessionTranscript(sessionId: UUID) async throws -> [TranscriptSegment] {
        // Get all chunks for the session
        let chunks = try await databaseManager.fetchChunksBySession(sessionId: sessionId)
        
        // Fetch transcripts for all chunks and combine
        var allSegments: [TranscriptSegment] = []
        for chunk in chunks {
            let segments = try await databaseManager.fetchTranscriptSegments(audioChunkID: chunk.id)
            allSegments.append(contentsOf: segments)
        }
        
        // Sort by createdAt to maintain order (segments are already ordered within chunks)
        return allSegments.sorted { $0.createdAt < $1.createdAt }
    }
    
    // MARK: - Period Summaries
    
    /// Update period summaries after a new session summary is created
    /// Follows hierarchical rollup: Session → Day → Week → Month → Year
    public func updatePeriodSummaries(sessionId: UUID, sessionDate: Date) async {
        print("🔄 [SummaryCoordinator] Updating period summaries for session...")
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: sessionDate)
        
        // Update daily summary
        await updateDailySummary(date: startOfDay)
        
        // Update weekly summary
        await updateWeeklySummary(date: sessionDate)
        
        // Update monthly summary
        await updateMonthlySummary(date: sessionDate)
        
        // Update yearly summary
        await updateYearlySummary(date: sessionDate)
    }
    
    /// Update or create daily summary by aggregating all session summaries for that day using deterministic rollup
    public func updateDailySummary(date: Date, forceRegenerate: Bool = false) async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let periodKey = "day-\(startOfDay.timeIntervalSince1970)"

        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [SummaryCoordinator] Daily summary already being generated, skipping duplicate call...")
            return
        }

        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            let sessions = try await databaseManager.fetchSessionsByDate(date: date)
            print("📊 [SummaryCoordinator] Found \(sessions.count) sessions for \(date.formatted(date: .abbreviated, time: .omitted))")

            guard !sessions.isEmpty else {
                print("ℹ️ [SummaryCoordinator] No sessions found for this day")
                return
            }

            var sessionsWithSummaries = 0
            var sessionsNeedingSummaries = 0

            for session in sessions {
                if let _ = try? await databaseManager.fetchSummaryForSession(sessionId: session.sessionId) {
                    sessionsWithSummaries += 1
                } else {
                    let isComplete = try await databaseManager.isSessionTranscriptionComplete(sessionId: session.sessionId)
                    if isComplete {
                        print("⚠️ [SummaryCoordinator] Session \(session.sessionId) missing summary, generating...")
                        try await generateSessionSummary(sessionId: session.sessionId)
                        sessionsWithSummaries += 1
                    } else {
                        print("⏳ [SummaryCoordinator] Session \(session.sessionId) transcription incomplete, skipping")
                        sessionsNeedingSummaries += 1
                    }
                }
            }

            guard sessionsWithSummaries > 0 else {
                print("ℹ️ [SummaryCoordinator] No sessions with summaries for this day (\(sessions.count) total, \(sessionsNeedingSummaries) pending transcription)")
                return
            }

            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date

            let sessionSummaries = try await databaseManager.fetchSummaries(periodType: .session)
                .filter { $0.sessionId != nil && $0.periodStart >= startOfDay && $0.periodStart < endOfDay }
                .sorted { $0.periodStart < $1.periodStart }

            let sessionIds = sessionSummaries.compactMap { $0.sessionId }
            let sessionTexts = sessionSummaries.map { $0.text }

            let sourceIds = await databaseManager.sourceIdsToJSON(sessionIds)
            let inputHash = await databaseManager.computeInputHash(sessionTexts)

            print("🔐 [SummaryCoordinator] Computed input hash: \(inputHash.prefix(16))... from \(sessionTexts.count) session summaries")

            if let existing = try? await databaseManager.fetchPeriodSummary(type: .day, date: startOfDay) {
                print("📂 [SummaryCoordinator] Found existing daily summary (hash: \(existing.inputHash?.prefix(16) ?? "nil")...), engine: \(existing.engineTier ?? "unknown")")
                if existing.inputHash == inputHash, !forceRegenerate {
                    print("💾 [SummaryCoordinator] ✅ CACHE HIT - Daily rollup unchanged, skipping regeneration")
                    return
                }
                print(forceRegenerate ? "🔄 [SummaryCoordinator] Force regenerate enabled" : "🔄 [SummaryCoordinator] Hash mismatch - regenerating daily rollup")
            } else {
                print("📝 [SummaryCoordinator] No existing daily summary found, will generate new rollup")
            }

            // Generate rollup summary from session summaries (oldest to newest)
            // Store clean text without timestamps - metadata is in periodStart/periodEnd
            print("📝 [SummaryCoordinator] Generating rollup from \(sessionSummaries.count) session summaries (oldest to newest)")
            
            // Build lines, appending user notes if they exist for each session
            var lines: [String] = []
            for summary in sessionSummaries {
                var lineText = "• \(summary.text)"
                
                // Append user notes if they exist for this session
                if let sid = summary.sessionId,
                   let metadata = try? await databaseManager.fetchSessionMetadata(sessionId: sid),
                   let notes = metadata.notes, !notes.isEmpty {
                    lineText += "\n  (Notes: \(notes))"
                }
                
                lines.append(lineText)
            }
            
            let summaryText = lines.joined(separator: "\n")
            let topicsJSON: String? = nil
            let entitiesJSON: String? = nil
            let engineTier = "rollup"

            try await databaseManager.upsertPeriodSummary(
                type: .day,
                text: summaryText,
                start: startOfDay,
                end: endOfDay,
                topicsJSON: topicsJSON,
                entitiesJSON: entitiesJSON,
                engineTier: engineTier,
                sourceIds: sourceIds,
                inputHash: inputHash
            )

            print("✅ [SummaryCoordinator] Daily summary saved (engine: \(engineTier), \(summaryText.count) chars)")
        } catch {
            print("❌ [SummaryCoordinator] Failed to update daily summary: \(error)")
        }
    }
    
    /// Update or create weekly summary by concatenating daily rollups
    public func updateWeeklySummary(date: Date, forceRegenerate: Bool = false) async {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = 2 // Monday
        guard let startOfWeek = calendar.date(from: components) else { return }
        guard let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) else { return }

        let periodKey = "week-\(startOfWeek.timeIntervalSince1970)"

        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [SummaryCoordinator] Weekly summary already being generated, skipping duplicate call...")
            return
        }

        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            print("📊 [SummaryCoordinator] Updating weekly rollup for \(startOfWeek.formatted(date: .abbreviated, time: .omitted)) - \(endOfWeek.formatted(date: .abbreviated, time: .omitted))")

            let dailySummaries = try await databaseManager.fetchDailySummaries(from: startOfWeek, to: endOfWeek)
                .sorted { $0.periodStart < $1.periodStart }
            print("📊 [SummaryCoordinator] Found \(dailySummaries.count) daily summaries for this week")

            guard !dailySummaries.isEmpty else {
                print("ℹ️ [SummaryCoordinator] No daily summaries found for this week")
                return
            }

            let dailyIds = dailySummaries.map { $0.id }
            let dailyTexts = dailySummaries.map { $0.text }
            let sourceIds = await databaseManager.sourceIdsToJSON(dailyIds)
            let inputHash = await databaseManager.computeInputHash(dailyTexts)

            print("🔐 [SummaryCoordinator] Computed input hash: \(inputHash.prefix(16))... from \(dailyTexts.count) daily summaries")

            if let existing = try? await databaseManager.fetchPeriodSummary(type: .week, date: startOfWeek) {
                print("📂 [SummaryCoordinator] Found existing weekly summary (hash: \(existing.inputHash?.prefix(16) ?? "nil")...), engine: \(existing.engineTier ?? "unknown")")
                if existing.inputHash == inputHash, !forceRegenerate {
                    print("💾 [SummaryCoordinator] ✅ CACHE HIT - Weekly rollup unchanged, skipping regeneration")
                    return
                }
                print(forceRegenerate ? "🔄 [SummaryCoordinator] Force regenerate enabled" : "🔄 [SummaryCoordinator] Hash mismatch - regenerating weekly rollup")
            } else {
                print("📝 [SummaryCoordinator] No existing weekly summary found, will generate new rollup")
            }

            // Generate rollup summary from daily summaries (oldest to newest)
            // Store clean text without timestamps - metadata is in periodStart/periodEnd
            print("📝 [SummaryCoordinator] Generating rollup from \(dailySummaries.count) daily summaries (oldest to newest)")
            let lines = dailySummaries.map { summary in
                // Clean text only - no timestamps to prevent accumulation in nested rollups
                return "• \(summary.text)"
            }
            let summaryText = lines.joined(separator: "\n")
            let topicsJSON: String? = nil
            let entitiesJSON: String? = nil
            let engineTier = "rollup"

            try await databaseManager.upsertPeriodSummary(
                type: .week,
                text: summaryText,
                start: startOfWeek,
                end: endOfWeek,
                topicsJSON: topicsJSON,
                entitiesJSON: entitiesJSON,
                engineTier: engineTier,
                sourceIds: sourceIds,
                inputHash: inputHash
            )

            print("✅ [SummaryCoordinator] Weekly summary saved (engine: \(engineTier))")
        } catch {
            print("❌ [SummaryCoordinator] Failed to update weekly summary: \(error)")
        }
    }
    
    /// Update or create monthly summary by concatenating weekly rollups (or daily when needed)
    public func updateMonthlySummary(date: Date, forceRegenerate: Bool = false) async {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let startOfMonth = calendar.date(from: components) else { return }
        guard let endOfMonth = calendar.date(byAdding: DateComponents(month: 1), to: startOfMonth) else { return }

        let periodKey = "month-\(startOfMonth.timeIntervalSince1970)"

        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [SummaryCoordinator] Monthly summary already being generated, skipping duplicate call...")
            return
        }

        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            print("📊 [SummaryCoordinator] Updating monthly rollup for \(startOfMonth.formatted(date: .abbreviated, time: .omitted))")

            var weeklySummaries = try await databaseManager.fetchWeeklySummaries(from: startOfMonth, to: endOfMonth)
                .sorted { $0.periodStart < $1.periodStart }
            print("📊 [SummaryCoordinator] Found \(weeklySummaries.count) weekly summaries for this month")

            if weeklySummaries.isEmpty {
                print("ℹ️ [SummaryCoordinator] No weekly summaries found, checking daily summaries...")
                weeklySummaries = try await databaseManager.fetchDailySummaries(from: startOfMonth, to: endOfMonth)
                    .sorted { $0.periodStart < $1.periodStart }
            }

            guard !weeklySummaries.isEmpty else {
                print("ℹ️ [SummaryCoordinator] No rollups found for this month")
                return
            }

            let weeklyIds = weeklySummaries.map { $0.id }
            let weeklyTexts = weeklySummaries.map { $0.text }
            let sourceIds = await databaseManager.sourceIdsToJSON(weeklyIds)
            let inputHash = await databaseManager.computeInputHash(weeklyTexts)

            print("🔐 [SummaryCoordinator] Computed input hash: \(inputHash.prefix(16))... from \(weeklyTexts.count) rollups")

            if let existing = try? await databaseManager.fetchPeriodSummary(type: .month, date: startOfMonth) {
                print("📂 [SummaryCoordinator] Found existing monthly summary (hash: \(existing.inputHash?.prefix(16) ?? "nil")...), engine: \(existing.engineTier ?? "unknown")")
                if existing.inputHash == inputHash, !forceRegenerate {
                    print("💾 [SummaryCoordinator] ✅ CACHE HIT - Monthly rollup unchanged, skipping regeneration")
                    return
                }
                print(forceRegenerate ? "🔄 [SummaryCoordinator] Force regenerate enabled" : "🔄 [SummaryCoordinator] Hash mismatch - regenerating monthly rollup")
            } else {
                print("📝 [SummaryCoordinator] No existing monthly summary found, will generate new rollup")
            }

            // Generate rollup summary from weekly summaries (oldest to newest)
            // Store clean text without timestamps - metadata is in periodStart/periodEnd
            print("📝 [SummaryCoordinator] Generating rollup from \(weeklySummaries.count) weekly summaries (oldest to newest)")
            let lines = weeklySummaries.map { summary in
                // Clean text only - no timestamps to prevent accumulation in nested rollups
                return "• \(summary.text)"
            }
            let summaryText = lines.joined(separator: "\n")
            let topicsJSON: String? = nil
            let entitiesJSON: String? = nil
            let engineTier = "rollup"

            try await databaseManager.upsertPeriodSummary(
                type: .month,
                text: summaryText,
                start: startOfMonth,
                end: endOfMonth,
                topicsJSON: topicsJSON,
                entitiesJSON: entitiesJSON,
                engineTier: engineTier,
                sourceIds: sourceIds,
                inputHash: inputHash
            )

            print("✅ [SummaryCoordinator] Monthly summary saved (engine: \(engineTier))")
        } catch {
            print("❌ [SummaryCoordinator] Failed to update monthly summary: \(error)")
        }
    }
    
    /// Update or create yearly summary by concatenating monthly rollups (no external calls)
    public func updateYearlySummary(date: Date, forceRegenerate: Bool = false) async {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1
        guard let startOfYear = calendar.date(from: startComponents) else { return }
        guard let endOfYear = calendar.date(byAdding: DateComponents(year: 1), to: startOfYear) else { return }

        let periodKey = "year-\(startOfYear.timeIntervalSince1970)"

        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [SummaryCoordinator] Yearly summary already being generated, skipping duplicate call...")
            return
        }

        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            print("📊 [SummaryCoordinator] Updating yearly rollup for \(year)")

            var monthlySummaries = try await databaseManager.fetchMonthlySummaries(from: startOfYear, to: endOfYear)
                .sorted { $0.periodStart < $1.periodStart }
            print("📊 [SummaryCoordinator] Found \(monthlySummaries.count) monthly summaries for this year")

            if monthlySummaries.isEmpty {
                print("ℹ️ [SummaryCoordinator] No monthly summaries found, checking weekly summaries...")
                monthlySummaries = try await databaseManager.fetchWeeklySummaries(from: startOfYear, to: endOfYear)
                    .sorted { $0.periodStart < $1.periodStart }
            }

            guard !monthlySummaries.isEmpty else {
                print("ℹ️ [SummaryCoordinator] No rollups found for this year")
                return
            }

            let monthlyIds = monthlySummaries.map { $0.id }
            let monthlyTexts = monthlySummaries.map { $0.text }
            let sourceIds = await databaseManager.sourceIdsToJSON(monthlyIds)
            let inputHash = await databaseManager.computeInputHash(monthlyTexts)

            print("🔐 [SummaryCoordinator] Computed input hash: \(inputHash.prefix(16))... from \(monthlyTexts.count) rollups")

            if let existing = try? await databaseManager.fetchPeriodSummary(type: .year, date: startOfYear) {
                print("📂 [SummaryCoordinator] Found existing yearly summary (hash: \(existing.inputHash?.prefix(16) ?? "nil")...)")
                if existing.inputHash == inputHash, !forceRegenerate {
                    print("💾 [SummaryCoordinator] ✅ CACHE HIT - Yearly rollup unchanged, skipping regeneration")
                    return
                }
                print(forceRegenerate ? "🔄 [SummaryCoordinator] Force regenerate enabled" : "🔄 [SummaryCoordinator] Hash mismatch - regenerating yearly rollup")
            } else {
                print("📝 [SummaryCoordinator] No existing yearly summary found, will generate new rollup")
            }

            // Store clean text without timestamps - metadata is in periodStart/periodEnd
            let lines = monthlySummaries.map { summary in
                // Clean text only - no timestamps to prevent accumulation in nested rollups
                return "• \(summary.text)"
            }
            let rollupText = lines.joined(separator: "\n")

            try await databaseManager.upsertPeriodSummary(
                type: .year,
                text: rollupText,
                start: startOfYear,
                end: endOfYear,
                topicsJSON: nil,
                entitiesJSON: nil,
                engineTier: "rollup",
                sourceIds: sourceIds,
                inputHash: inputHash
            )

            print("✅ [SummaryCoordinator] Yearly rollup updated (engine: rollup)")
        } catch {
            print("❌ [SummaryCoordinator] Failed to update yearly summary: \(error)")
        }
    }

    /// Manual Year Wrap using external intelligence (keeps deterministic rollup as default)
    public func wrapUpYear(date: Date, forceRegenerate: Bool = false) async {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1
        guard let startOfYear = calendar.date(from: startComponents) else { return }
        guard let endOfYear = calendar.date(byAdding: DateComponents(year: 1), to: startOfYear) else { return }

        let periodKey = "yearwrap-\(startOfYear.timeIntervalSince1970)"

        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [SummaryCoordinator] Year Wrap already in progress, skipping duplicate call...")
            return
        }

        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            print("📊 [SummaryCoordinator] Starting Year Wrap for \(year)")

            var sourceSummaries = try await databaseManager.fetchMonthlySummaries(from: startOfYear, to: endOfYear)
                .sorted { $0.periodStart < $1.periodStart }

            if sourceSummaries.isEmpty {
                sourceSummaries = try await databaseManager.fetchWeeklySummaries(from: startOfYear, to: endOfYear)
                    .sorted { $0.periodStart < $1.periodStart }
            }

            guard !sourceSummaries.isEmpty else {
                print("ℹ️ [SummaryCoordinator] No rollups available to build a Year Wrap")
                return
            }

            let sourceIds = await databaseManager.sourceIdsToJSON(sourceSummaries.map { $0.id })
            let inputHash = await databaseManager.computeInputHash(sourceSummaries.map { $0.text })

            if let existing = try? await databaseManager.fetchPeriodSummary(type: .yearWrap, date: startOfYear) {
                print("📂 [SummaryCoordinator] Found existing Year Wrap (hash: \(existing.inputHash?.prefix(16) ?? "nil")...)")
                if existing.inputHash == inputHash, !forceRegenerate {
                    print("💾 [SummaryCoordinator] ✅ CACHE HIT - Year Wrap unchanged, skipping external call")
                    return
                }
                print(forceRegenerate ? "🔄 [SummaryCoordinator] Force regenerate enabled - will call AI" : "🔄 [SummaryCoordinator] Hash mismatch - regenerating Year Wrap")
            } else {
                print("📝 [SummaryCoordinator] No Year Wrap found, generating new one")
            }

            // Fetch category information for the year
            let categoryMap = try await fetchSessionCategoriesForYear(year: year)
            let categoryContext = buildCategoryContext(categoryMap: categoryMap)

            let wrapSummary = try await summarizationEngine.generateYearWrapSummary(
                startOfYear: startOfYear,
                endOfYear: endOfYear,
                sourceSummaries: sourceSummaries,
                categoryContext: categoryContext
            )

            try await databaseManager.upsertPeriodSummary(
                type: .yearWrap,
                text: wrapSummary.text,
                start: startOfYear,
                end: endOfYear,
                topicsJSON: wrapSummary.topicsJSON,
                entitiesJSON: wrapSummary.entitiesJSON,
                engineTier: wrapSummary.engineTier ?? EngineTier.external.rawValue,
                sourceIds: sourceIds,
                inputHash: inputHash
            )

            print("✅ [SummaryCoordinator] Year Wrap saved (engine: \(wrapSummary.engineTier ?? "external"))")
        } catch {
            print("❌ [SummaryCoordinator] Failed to generate Year Wrap: \(error)")
        }
    }
    
    /// Get count of new sessions created after Year Wrap generation
    public func getNewSessionsSinceYearWrap(yearWrap: Summary, year: Int) async throws -> Int {
        // Fetch all years with their session IDs
        let yearlyData = try await databaseManager.fetchSessionsByYear()
        
        // Find the specified year
        guard let yearData = yearlyData.first(where: { $0.year == year }) else {
            print("⚠️ [SummaryCoordinator] No sessions found for year \(year)")
            return 0
        }
        
        print("🔍 [SummaryCoordinator] Checking \(yearData.sessionIds.count) sessions against Year Wrap createdAt: \(yearWrap.createdAt)")
        
        // For each session ID, fetch its first chunk time and compare with Year Wrap's createdAt
        // This ensures we count sessions created AFTER the wrap was last generated
        var newCount = 0
        for sessionId in yearData.sessionIds {
            if let firstChunk = try? await databaseManager.fetchChunksBySession(sessionId: sessionId).first {
                if firstChunk.createdAt > yearWrap.createdAt {
                    newCount += 1
                    print("  ✅ Session \(sessionId.uuidString.prefix(8)): \(firstChunk.createdAt) > \(yearWrap.createdAt) = NEW")
                } else {
                    print("  ⏭️ Session \(sessionId.uuidString.prefix(8)): \(firstChunk.createdAt) <= \(yearWrap.createdAt) = OLD")
                }
            }
        }
        
        print("📊 [SummaryCoordinator] Year Wrap staleness check: \(newCount) new sessions since \(yearWrap.createdAt)")
        
        return newCount
    }
    
    // MARK: - Helpers
    
    /// Fetch session category distribution for a given year
    private func fetchSessionCategoriesForYear(year: Int) async throws -> [UUID: SessionCategory] {
        // Fetch all sessions for the year
        let yearlyData = try await databaseManager.fetchSessionsByYear()
        guard let yearData = yearlyData.first(where: { $0.year == year }) else {
            print("ℹ️ [SummaryCoordinator] No sessions found for year \(year)")
            return [:]
        }
        
        // Fetch metadata for all sessions in the year
        let metadata = try await databaseManager.fetchSessionMetadataBatch(sessionIds: yearData.sessionIds)
        
        // Build UUID -> SessionCategory map
        // Note: For Year Wrap, we use this to provide overall category context to the AI
        // The AI will look at which sessions were marked work/personal and classify items accordingly
        var categoryMap: [UUID: SessionCategory] = [:]
        for (sessionId, meta) in metadata {
            if let category = meta.category {
                categoryMap[sessionId] = category
            }
        }
        
        let workCount = categoryMap.values.filter { $0 == .work }.count
        let personalCount = categoryMap.values.filter { $0 == .personal }.count
        print("📊 [SummaryCoordinator] Year \(year): \(workCount) work sessions, \(personalCount) personal sessions out of \(yearData.sessionIds.count) total")
        
        return categoryMap
    }
    
    /// Build category context string for AI prompt
    private func buildCategoryContext(categoryMap: [UUID: SessionCategory]) -> String? {
        guard !categoryMap.isEmpty else { return nil }
        
        let workCount = categoryMap.values.filter { $0 == .work }.count
        let personalCount = categoryMap.values.filter { $0 == .personal }.count
        
        guard workCount > 0 || personalCount > 0 else { return nil }
        
        var parts: [String] = []
        if workCount > 0 {
            parts.append("\(workCount) work session\(workCount == 1 ? "" : "s")")
        }
        if personalCount > 0 {
            parts.append("\(personalCount) personal session\(personalCount == 1 ? "" : "s")")
        }
        
        return """
        The user has categorized their recording sessions this year as: \(parts.joined(separator: " and ")).
        
        When classifying items in the Year Wrap:
        - Items from work sessions should be marked as "work"
        - Items from personal sessions should be marked as "personal"
        - Items that appear across both types or cannot be clearly attributed should be marked as "both"
        
        The monthly/weekly summaries you're analyzing aggregate content from these categorized sessions.
        Use the session categories as context to infer which domain each insight belongs to.
        """
    }
    
    /// Calculate hash of input text for caching
    private func calculateHash(for text: String) -> String {
        return String(text.hashValue)
    }
    
    /// Build formatted rollup text with header and bullet points
    private func buildRollupText(header: String, lines: [String]) -> String {
        return "\(header)\n\n" + lines.map { "• \($0)" }.joined(separator: "\n")
    }
}
