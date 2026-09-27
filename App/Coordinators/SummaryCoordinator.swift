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
    
    /// Called to update Year Wrap generation progress
    public var onYearWrapProgressUpdate: ((String) -> Void)?
    
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
        let inputHash = await calculateHash(for: fullText)
        
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
        let generated = try await summarizationEngine.generateSessionSummary(sessionId: sessionId, segments: allSegments)
        var generatedSummary = generated.summary
        
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
        
        // Give the recording a title if it doesn't have one yet (never replaces the user's own)
        let keyPoints = (try? [String].fromTopicsJSON(generatedSummary.topicsJSON)) ?? []
        await applyTitleIfMissing(sessionId: sessionId, suggested: generated.title, summary: generatedSummary.text, keyPoints: keyPoints)
        
        // Update period summaries (daily, monthly, yearly)
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
    
    // MARK: - Recording Titles
    
    /// Set a recording's title when it has none. Uses the model's suggestion, then a short
    /// request to the user's engine, then the summary's own first words.
    private func applyTitleIfMissing(sessionId: UUID, suggested: String?, summary: String, keyPoints: [String]) async {
        if let existing = try? await databaseManager.fetchSessionMetadata(sessionId: sessionId),
           let title = existing.title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
            return
        }
        var title = SessionTitler.clean(suggested)
        if title == nil, let generator = await summarizationEngine.digestGenerator() {
            title = await SessionTitler.titles(for: [summary], generator: generator).first ?? nil
        }
        if title == nil {
            title = SessionTitler.fallback(summary: summary, keyPoints: keyPoints)
        }
        guard let title else { return }
        try? await databaseManager.updateSessionTitle(sessionId: sessionId, title: title)
        print("🏷️ [SummaryCoordinator] Titled recording: \(title)")
    }
    
    /// Title recordings that were summarized before titles were generated, newest first,
    /// ten per request. Stops after `limit` so one app launch stays light.
    /// Returns how many recordings were titled.
    @discardableResult
    public func titleUntitledRecordings(limit: Int = 50) async -> Int {
        guard let summaries = try? await liveSessionSummaries(from: .distantPast, to: .distantFuture) else { return 0 }
        let ids = summaries.compactMap { $0.sessionId }
        guard let metadata = try? await databaseManager.fetchSessionMetadataBatch(sessionIds: ids) else { return 0 }
        let untitled = summaries.reversed().filter { summary in
            guard let id = summary.sessionId else { return false }
            let title = metadata[id]?.title?.trimmingCharacters(in: .whitespaces) ?? ""
            return title.isEmpty
        }.prefix(limit)
        guard !untitled.isEmpty else { return 0 }
        
        let generator = await summarizationEngine.digestGenerator()
        let batches = stride(from: 0, to: untitled.count, by: 10).map { Array(untitled.dropFirst($0).prefix(10)) }
        var titled = 0
        for batch in batches {
            let suggested: [String?]
            if let generator {
                suggested = await SessionTitler.titles(for: batch.map(\.text), generator: generator)
            } else {
                suggested = Array(repeating: nil, count: batch.count)
            }
            for (summary, suggestion) in zip(batch, suggested) {
                guard let id = summary.sessionId else { continue }
                // The user may have named it while this ran
                if let current = try? await databaseManager.fetchSessionMetadata(sessionId: id),
                   let title = current.title, !title.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                let keyPoints = (try? [String].fromTopicsJSON(summary.topicsJSON)) ?? []
                guard let title = suggestion ?? SessionTitler.fallback(summary: summary.text, keyPoints: keyPoints) else { continue }
                try? await databaseManager.updateSessionTitle(sessionId: id, title: title)
                titled += 1
            }
        }
        if generator?.tier == .local {
            await summarizationEngine.getLocalEngine().unloadModel()
        }
        print("🏷️ [SummaryCoordinator] Titled \(titled) older recordings")
        return titled
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
    
    /// Session summaries in [start, end), oldest first, for recordings that still exist.
    /// Deleting a recording removes its audio but not its summary, so a deleted recording
    /// must not show up in rollups, digests or Year Wrap.
    private func liveSessionSummaries(from start: Date, to end: Date) async throws -> [Summary] {
        let summaries = try await databaseManager.fetchSummaries(periodType: .session, from: start, to: end)
            .filter { $0.sessionId != nil }
        let existing = try await databaseManager.existingSessionIds(among: summaries.compactMap { $0.sessionId })
        return summaries.filter { $0.sessionId.map(existing.contains) ?? false }
    }
    
    /// Update period summaries after a new session summary is created
    /// Follows hierarchical rollup: Session → Day → Month → Year
    public func updatePeriodSummaries(sessionId: UUID, sessionDate: Date) async {
        print("🔄 [SummaryCoordinator] Updating period summaries for session...")
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: sessionDate)
        
        // Update daily summary
        await updateDailySummary(date: startOfDay)
        
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

            let sessionSummaries = try await liveSessionSummaries(from: startOfDay, to: endOfDay)

            // Never replace an existing day rollup with an empty one
            guard !sessionSummaries.isEmpty else {
                print("ℹ️ [SummaryCoordinator] No session summaries found in range for this day, keeping existing rollup")
                return
            }

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
            
            // Build lines, appending category and user notes if they exist for each session
            var lines: [String] = []
            for summary in sessionSummaries {
                var lineText = "• "
                
                // Prepend category tag if available
                if let sid = summary.sessionId,
                   let metadata = try? await databaseManager.fetchSessionMetadata(sessionId: sid) {
                    if let category = metadata.category {
                        lineText += "[\(category.displayName.uppercased())] "
                    }
                    lineText += summary.text
                    
                    // Append user notes if they exist for this session
                    if let notes = metadata.notes, !notes.isEmpty {
                        lineText += "\n  (Notes: \(notes))"
                    }
                } else {
                    lineText += summary.text
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
    
    /// Update or create monthly summary by concatenating daily rollups
    public func updateMonthlySummary(date: Date, forceRegenerate: Bool = false) async {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let startOfMonth = calendar.date(from: components) else { 
            print("❌ [SummaryCoordinator] Failed to calculate start of month")
            return 
        }
        guard let endOfMonth = calendar.date(byAdding: DateComponents(month: 1), to: startOfMonth) else { 
            print("❌ [SummaryCoordinator] Failed to calculate end of month")
            return 
        }

        let periodKey = "month-\(startOfMonth.timeIntervalSince1970)"

        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [SummaryCoordinator] Monthly summary already being generated, skipping duplicate call...")
            return
        }

        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            print("📊 [SummaryCoordinator] Updating monthly rollup for \(startOfMonth.formatted(date: .abbreviated, time: .omitted))")

            // First try to get daily summaries directly (more reliable for partial weeks)
            let dailySummaries = try await databaseManager.fetchDailySummaries(from: startOfMonth, to: endOfMonth)
                .sorted { $0.periodStart < $1.periodStart }
            print("📊 [SummaryCoordinator] Found \(dailySummaries.count) daily summaries for this month")

            guard !dailySummaries.isEmpty else {
                print("ℹ️ [SummaryCoordinator] No daily summaries found for this month")
                return
            }

            let dailyIds = dailySummaries.map { $0.id }
            let dailyTexts = dailySummaries.map { $0.text }
            let sourceIds = await databaseManager.sourceIdsToJSON(dailyIds)
            let inputHash = await databaseManager.computeInputHash(dailyTexts)

            print("🔐 [SummaryCoordinator] Computed input hash: \(inputHash.prefix(16))... from \(dailyTexts.count) daily summaries")

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

            let monthlySummaries = try await databaseManager.fetchMonthlySummaries(from: startOfYear, to: endOfYear)
                .sorted { $0.periodStart < $1.periodStart }
            print("📊 [SummaryCoordinator] Found \(monthlySummaries.count) monthly summaries for this year")

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

    // MARK: - Month Digests

    /// Bump when the digest format or extraction changes, so existing digests are rebuilt
    private static let digestVersion = "digest-v5"

    /// Session summaries and metadata for one month, plus a hash of everything that shapes the digest
    private struct DigestInputs {
        let monthStart: Date
        let monthEnd: Date
        let summaries: [Summary]
        let metadata: [UUID: DatabaseManager.SessionMetadata]
        let inputHash: String
    }

    private func monthBounds(for date: Date) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
        return (start, end)
    }

    private func loadDigestInputs(for date: Date) async throws -> DigestInputs? {
        guard let bounds = monthBounds(for: date) else { return nil }
        let summaries = try await liveSessionSummaries(from: bounds.start, to: bounds.end)
        guard !summaries.isEmpty else { return nil }

        let metadata = try await databaseManager.fetchSessionMetadataBatch(sessionIds: summaries.compactMap { $0.sessionId })
        let hashLines = summaries.map { summary -> String in
            let meta = summary.sessionId.flatMap { metadata[$0] }
            return [summary.sessionId?.uuidString ?? "", meta?.category?.rawValue ?? "", summary.text,
                    summary.topicsJSON ?? "", meta?.notes ?? ""].joined(separator: "|")
        }
        let inputHash = await databaseManager.computeInputHash([Self.digestVersion] + hashLines)
        return DigestInputs(monthStart: bounds.start, monthEnd: bounds.end, summaries: summaries, metadata: metadata, inputHash: inputHash)
    }

    /// First day of every month that has recordings, newest first
    public func monthsWithRecordings() async -> [Date] {
        guard let summaries = try? await liveSessionSummaries(from: .distantPast, to: .distantFuture) else { return [] }
        return Set(summaries.compactMap { monthBounds(for: $0.periodStart)?.start }).sorted(by: >)
    }
    
    /// The stored digest for the month containing `date`, if any
    public func fetchMonthDigest(date: Date) async -> MonthDigest? {
        guard let row = try? await databaseManager.fetchPeriodSummary(type: .monthDigest, date: date) else { return nil }
        return MonthDigest.fromJSON(row.text)
    }

    /// Build or refresh the digest for the month containing `date`.
    /// Returns quickly with the stored digest when nothing changed. A month that has ended is marked final.
    @discardableResult
    public func updateMonthDigest(date: Date, forceRegenerate: Bool = false) async -> MonthDigest? {
        guard let bounds = monthBounds(for: date) else { return nil }
        let periodKey = "digest-\(bounds.start.timeIntervalSince1970)"
        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [SummaryCoordinator] Month digest already being built, skipping duplicate call")
            return await fetchMonthDigest(date: date)
        }
        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            guard let inputs = try await loadDigestInputs(for: date) else {
                print("ℹ️ [SummaryCoordinator] No session summaries for \(bounds.start.formatted(.dateTime.month().year())), no digest to build")
                return nil
            }
            let isFinal = inputs.monthEnd <= Date()

            if !forceRegenerate,
               let existingRow = try? await databaseManager.fetchPeriodSummary(type: .monthDigest, date: inputs.monthStart),
               existingRow.inputHash == inputs.inputHash,
               let existing = MonthDigest.fromJSON(existingRow.text) {
                if existing.isFinal == isFinal {
                    print("💾 [SummaryCoordinator] ✅ CACHE HIT - Month digest unchanged")
                    return existing
                }
                // Same content, the month just ended: mark it final without running the model again
                let finalized = existing.withFinal(isFinal)
                try await saveMonthDigest(finalized, inputs: inputs)
                return finalized
            }

            let sources = await digestSources(from: inputs)
            let generator = await summarizationEngine.digestGenerator()
            print("🧩 [SummaryCoordinator] Building \(isFinal ? "final" : "draft") digest for \(inputs.monthStart.formatted(.dateTime.month().year())) from \(sources.count) recordings with \(generator?.tier.displayName ?? "Basic")")

            let digest = await MonthDigestBuilder.build(
                monthStart: inputs.monthStart,
                sources: sources,
                isFinal: isFinal,
                generator: generator
            )
            try await saveMonthDigest(digest, inputs: inputs)

            if generator?.tier == .local {
                await summarizationEngine.getLocalEngine().unloadModel()
            }
            print("✅ [SummaryCoordinator] Month digest saved: \(digest.items.count) items")
            return digest
        } catch {
            print("❌ [SummaryCoordinator] Failed to build month digest: \(error)")
            return nil
        }
    }

    private func digestSources(from inputs: DigestInputs) async -> [DigestSource] {
        var sources: [DigestSource] = []
        for summary in inputs.summaries {
            guard let sessionId = summary.sessionId else { continue }
            let meta = inputs.metadata[sessionId]
            let wordCount = (try? await databaseManager.fetchSessionWordCount(sessionId: sessionId)) ?? summary.text.split(separator: " ").count
            sources.append(DigestSource(
                sessionId: sessionId,
                start: summary.periodStart,
                duration: max(summary.periodEnd.timeIntervalSince(summary.periodStart), 0),
                wordCount: wordCount,
                summary: summary.text,
                keyPoints: (try? [String].fromTopicsJSON(summary.topicsJSON)) ?? [],
                entities: (try? [Entity].fromEntitiesJSON(summary.entitiesJSON)) ?? [],
                category: meta?.category,
                notes: meta?.notes
            ))
        }
        return sources
    }

    private func saveMonthDigest(_ digest: MonthDigest, inputs: DigestInputs) async throws {
        let topics = digest.items(of: .topic).map { $0.text }
        let topicsJSON = (try? JSONEncoder().encode(topics)).map { String(decoding: $0, as: UTF8.self) }
        try await databaseManager.upsertPeriodSummary(
            type: .monthDigest,
            text: try digest.jsonString(),
            start: inputs.monthStart,
            end: inputs.monthEnd,
            topicsJSON: topicsJSON,
            entitiesJSON: nil,
            engineTier: digest.engineTier,
            sourceIds: await databaseManager.sourceIdsToJSON(inputs.summaries.compactMap { $0.sessionId }),
            inputHash: inputs.inputHash
        )
    }

    /// Finalize at most one ended month whose digest is missing, still a draft, or out of date.
    /// Called when the app comes to the foreground; doing one month at a time keeps each launch light.
    /// Looks back to the start of last year; Year Wrap builds anything older it needs.
    public func finalizeNextClosedMonthDigest() async {
        let calendar = Calendar.current
        guard let currentMonth = monthBounds(for: Date())?.start,
              let lastYear = calendar.date(byAdding: .year, value: -1, to: currentMonth),
              let lookbackStart = calendar.date(from: DateComponents(year: calendar.component(.year, from: lastYear), month: 1, day: 1)) else { return }

        do {
            let summaries = try await liveSessionSummaries(from: lookbackStart, to: currentMonth)
            let months = Set(summaries.compactMap { monthBounds(for: $0.periodStart)?.start }).sorted(by: >)

            for month in months {
                guard let inputs = try await loadDigestInputs(for: month) else { continue }
                let existingRow = try? await databaseManager.fetchPeriodSummary(type: .monthDigest, date: month)
                let existing = existingRow.flatMap { MonthDigest.fromJSON($0.text) }
                if existingRow?.inputHash == inputs.inputHash, existing?.isFinal == true { continue }

                print("🗓️ [SummaryCoordinator] Finalizing digest for \(month.formatted(.dateTime.month().year()))")
                await updateMonthDigest(date: month)
                return
            }
        } catch {
            print("❌ [SummaryCoordinator] Failed to check month digests: \(error)")
        }
    }

    /// Bump when Year Wrap generation changes, so a cached wrap is rebuilt
    private static let yearWrapVersion = "yearwrap-v2"
    
    /// Year Wrap, built from the year's month digests.
    /// Makes sure every month with recordings has an up-to-date digest, then builds one wrap whose
    /// items carry their recordings and work/personal category (Work and Personal are filters on it).
    public func wrapUpYear(date: Date, forceRegenerate: Bool = false, useLocalAI: Bool = false) async {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        guard let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let endOfYear = calendar.date(byAdding: DateComponents(year: 1), to: startOfYear) else { return }

        let periodKey = "yearwrap-\(startOfYear.timeIntervalSince1970)"
        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [SummaryCoordinator] Year Wrap already in progress, skipping duplicate call...")
            return
        }
        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            // 1. Month digests
            let sessionSummaries = try await liveSessionSummaries(from: startOfYear, to: endOfYear)
            let months = Set(sessionSummaries.compactMap { monthBounds(for: $0.periodStart)?.start }).sorted()
            guard !months.isEmpty else {
                print("ℹ️ [SummaryCoordinator] No recordings in \(year), nothing to wrap")
                return
            }
            let totalSteps = months.count + 1
            var digests: [MonthDigest] = []
            for (index, month) in months.enumerated() {
                let name = month.formatted(.dateTime.month(.wide))
                onYearWrapProgressUpdate?("Step \(index + 1) of \(totalSteps): \(name) digest\nGathering what you said this month...")
                if let digest = await updateMonthDigest(date: month) {
                    digests.append(digest)
                }
            }
            guard !digests.isEmpty else {
                print("⚠️ [SummaryCoordinator] No month digests could be built for \(year)")
                return
            }

            // 2. Cache check: the wrap only changes when a digest or the chosen engine changes
            let digestTexts = digests.compactMap { try? $0.jsonString() }
            let inputHash = await databaseManager.computeInputHash([Self.yearWrapVersion, useLocalAI ? "local" : "external"] + digestTexts)
            if !forceRegenerate,
               let existing = try? await databaseManager.fetchPeriodSummary(type: .yearWrap, date: startOfYear),
               existing.inputHash == inputHash {
                print("💾 [SummaryCoordinator] ✅ CACHE HIT - Year Wrap unchanged")
                return
            }

            // 3. Year Wrap
            onYearWrapProgressUpdate?("Step \(totalSteps) of \(totalSteps): Year Wrap\nPutting your year together...")
            let generator = try await summarizationEngine.yearWrapGenerator(useLocalAI: useLocalAI)
            print("🎁 [SummaryCoordinator] Building Year Wrap for \(year) from \(digests.count) month digests with \(generator.tier.displayName)")
            let wrap = await YearWrapBuilder.build(year: year, digests: digests, generator: generator)

            let topics = wrap.topWorkedOnTopics.map { $0.text }
            let topicsJSON = (try? JSONEncoder().encode(topics)).map { String(decoding: $0, as: UTF8.self) }
            try await databaseManager.upsertPeriodSummary(
                type: .yearWrap,
                text: try YearWrapBuilder.jsonString(wrap),
                start: startOfYear,
                end: endOfYear,
                topicsJSON: topicsJSON,
                entitiesJSON: nil,
                engineTier: generator.tier.rawValue,
                sourceIds: await databaseManager.sourceIdsToJSON(sessionSummaries.compactMap { $0.sessionId }),
                inputHash: inputHash
            )

            if generator.tier == .local {
                await summarizationEngine.getLocalEngine().unloadModel()
            }
            print("✅ [SummaryCoordinator] Year Wrap saved")
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
    
    /// Calculate a stable hash of input text for caching.
    /// String.hashValue is seeded per launch, so it can't be stored and compared later.
    private func calculateHash(for text: String) async -> String {
        return await databaseManager.computeInputHash([text])
    }
    
    /// Build formatted rollup text with header and bullet points
    private func buildRollupText(header: String, lines: [String]) -> String {
        return "\(header)\n\n" + lines.map { "• \($0)" }.joined(separator: "\n")
    }
}
