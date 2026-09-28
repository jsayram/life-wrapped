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

    /// Sessions whose summary is being written right now. The end of a recording and its last
    /// chunk's transcription can both ask for the summary; only the first request runs.
    private var summarizingSessions: Set<UUID> = []

    public func isSummarizing(_ sessionId: UUID) -> Bool {
        summarizingSessions.contains(sessionId)
    }
    
    // MARK: - Callbacks
    
    /// Called when period summaries are updated (for widget refresh, etc.)
    public var onPeriodSummariesUpdated: (() async -> Void)?
    
    /// Called as Year Wrap generation moves through its steps
    public var onYearWrapProgressUpdate: ((YearWrapProgress) -> Void)?
    /// Called when a recording was summarized by a different engine than the one chosen in
    /// Settings, because that one wasn't available. (chosen, used)
    public var onEngineFallback: ((EngineTier, EngineTier) -> Void)?
    
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

        guard summarizingSessions.insert(sessionId).inserted else {
            print("ℹ️ [SummaryCoordinator] Summary for session \(sessionId) already in progress")
            return
        }
        defer { summarizingSessions.remove(sessionId) }

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
            NotificationCenter.default.post(name: .sessionSummaryFailed, object: sessionId,
                                            userInfo: ["message": error.localizedDescription])
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
                    // Not on its own with a weaker engine: the recording keeps its better summary and
                    // shows "Transcript changed since this summary", where updating is the person's call
                    let current = await summarizationEngine.getActiveEngine()
                    if current.isWeaker(than: existingSummary.engineTier) {
                        print("🛡️ [SummaryCoordinator] Keeping the \(existingSummary.engineTier ?? "") summary; \(current.displayName) would write a weaker one")
                        return
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
        if let used = generatedSummary.engineTier.flatMap(EngineTier.init(rawValue:)), used != activeEngine {
            onEngineFallback?(activeEngine, used)
        }
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
        
        // Save session summary. The one it replaces is kept as a version, so this can be undone.
        print("💾 [SummaryCoordinator] Saving summary to database...")
        try await databaseManager.replaceSessionSummary(generatedSummary)
        try? await databaseManager.markSessionChanged(sessionId: sessionId, content: true)
        NotificationCenter.default.post(name: .sessionSummaryUpdated, object: sessionId)
        print("✅ [SummaryCoordinator] Session summary saved successfully!")
        print("📊 [SummaryCoordinator] Summary details - topics: \(generatedSummary.topicsJSON?.prefix(50) ?? "none")")
        
        // Give the recording a title if it doesn't have one yet (never replaces the user's own)
        let keyPoints = (try? [String].fromTopicsJSON(generatedSummary.topicsJSON)) ?? []
        await applyTitleIfMissing(sessionId: sessionId, suggested: generated.title, summary: generatedSummary.text, keyPoints: keyPoints)
        
        // Notify callback (widgets)
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
        try? await databaseManager.markSessionChanged(sessionId: sessionId, content: true)
        
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
    /// must not show up in digests or Year Wrap.
    private func liveSessionSummaries(from start: Date, to end: Date) async throws -> [Summary] {
        let summaries = try await databaseManager.fetchSummaries(periodType: .session, from: start, to: end)
            .filter { $0.sessionId != nil }
        let existing = try await databaseManager.existingSessionIds(among: summaries.compactMap { $0.sessionId })
        return summaries.filter { $0.sessionId.map(existing.contains) ?? false }
    }
    
    // MARK: - Month Digests
    //
    // Work and Personal are two journals. Each has its own digest per month, built only from its
    // own recordings, so nothing from one journal ends up in the other. The All view is the two
    // put together in code (MonthDigest.combining). A recording without a category belongs to
    // Personal, the recorder's default. Digests from before the split (stored without a category)
    // stay readable, split per journal, until the month is rebuilt.

    /// Bump when the digest format or extraction changes, so existing digests are rebuilt
    private static let digestVersion = "digest-v6"

    /// One journal's session summaries and metadata for a month, plus a hash of everything that shapes its digest
    private struct DigestInputs {
        let monthStart: Date
        let monthEnd: Date
        let journal: SessionCategory
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

    /// The journal a recording belongs to
    private static func journal(of metadata: DatabaseManager.SessionMetadata?) -> SessionCategory {
        metadata?.category ?? .personal
    }

    /// The month's recordings grouped by journal. Journals with no recordings that month are left out.
    private func loadDigestInputs(for date: Date) async throws -> [SessionCategory: DigestInputs] {
        guard let bounds = monthBounds(for: date) else { return [:] }
        let summaries = try await liveSessionSummaries(from: bounds.start, to: bounds.end)
        guard !summaries.isEmpty else { return [:] }

        let metadata = try await databaseManager.fetchSessionMetadataBatch(sessionIds: summaries.compactMap { $0.sessionId })
        var result: [SessionCategory: DigestInputs] = [:]
        for journal in SessionCategory.allCases {
            let own = summaries.filter { Self.journal(of: $0.sessionId.flatMap { metadata[$0] }) == journal }
            guard !own.isEmpty else { continue }
            let hashLines = own.map { summary -> String in
                let meta = summary.sessionId.flatMap { metadata[$0] }
                return [summary.sessionId?.uuidString ?? "", summary.text, summary.topicsJSON ?? "", meta?.notes ?? ""].joined(separator: "|")
            }
            let inputHash = await databaseManager.computeInputHash([Self.digestVersion, journal.rawValue] + hashLines)
            result[journal] = DigestInputs(monthStart: bounds.start, monthEnd: bounds.end, journal: journal,
                                           summaries: own, metadata: metadata, inputHash: inputHash)
        }
        return result
    }

    /// First day of every month that has recordings, newest first
    public func monthsWithRecordings() async -> [Date] {
        guard let summaries = try? await liveSessionSummaries(from: .distantPast, to: .distantFuture) else { return [] }
        return Set(summaries.compactMap { monthBounds(for: $0.periodStart)?.start }).sorted(by: >)
    }
    
    /// What is saved for a month: each journal's row and digest, and whether an older mixed digest remains
    private struct StoredMonth {
        var journals: [SessionCategory: (row: Summary, digest: MonthDigest?)] = [:]
        var hasLegacy = false

        var plannerView: [SessionCategory: JournalDigests.Stored] {
            journals.mapValues { JournalDigests.Stored(inputHash: $0.row.inputHash, isFinal: $0.digest?.isFinal ?? false) }
        }
    }

    private func storedMonth(_ monthStart: Date) async -> StoredMonth {
        var stored = StoredMonth()
        for journal in SessionCategory.allCases {
            if let row = try? await databaseManager.fetchPeriodSummary(type: .monthDigest, date: monthStart, category: journal) {
                stored.journals[journal] = (row, MonthDigest.fromJSON(row.text))
            }
        }
        stored.hasLegacy = (try? await databaseManager.fetchPeriodSummary(type: .monthDigest, date: monthStart)) != nil
        return stored
    }

    /// The month's plan: what to reuse, rebuild or delete (see JournalDigests.plan)
    private func planMonth(_ monthStart: Date, inputs: [SessionCategory: DigestInputs], stored: StoredMonth, force: Bool = false) -> JournalDigests.Plan {
        let monthEnded = (Calendar.current.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart) <= Date()
        return JournalDigests.plan(currentHashes: inputs.mapValues(\.inputHash), stored: stored.plannerView,
                                   hasLegacy: stored.hasLegacy, monthEnded: monthEnded, force: force)
    }

    /// Delete the month's older mixed digest. There is normally one; a restored backup can leave more.
    private func removeLegacyDigests(_ monthStart: Date) async {
        for _ in 0..<5 {
            guard let row = try? await databaseManager.fetchPeriodSummary(type: .monthDigest, date: monthStart) else { return }
            try? await databaseManager.deleteSummary(id: row.id)
        }
    }

    /// The stored digests for the month containing `date`, both journals combined.
    public func fetchMonthDigest(date: Date) async -> MonthDigest? {
        await fetchMonthDigestStatus(date: date)?.digest
    }

    /// Like `fetchMonthDigest`, plus whether part of it still comes from an older mixed digest
    /// (the month hasn't been split into work and personal yet)
    public func fetchMonthDigestStatus(date: Date) async -> (digest: MonthDigest, usesLegacy: Bool)? {
        guard let bounds = monthBounds(for: date) else { return nil }
        let stored = await storedMonth(bounds.start)
        let legacy = stored.hasLegacy
            ? (try? await databaseManager.fetchPeriodSummary(type: .monthDigest, date: bounds.start)).flatMap { MonthDigest.fromJSON($0.text) }
            : nil
        return JournalDigests.combined(stored: stored.journals.compactMapValues(\.digest), legacy: legacy)
    }

    /// Build or refresh both journals' digests for the month containing `date`, and return them combined.
    /// Returns quickly with the stored digests when nothing changed. A month that has ended is marked final.
    /// Once every journal is current, the month's older mixed digest is deleted.
    @discardableResult
    public func updateMonthDigest(date: Date, forceRegenerate: Bool = false, generator override: (any TextGenerating)? = nil) async -> MonthDigest? {
        guard let bounds = monthBounds(for: date) else { return nil }
        let periodKey = "digest-\(bounds.start.timeIntervalSince1970)"
        guard !generatingPeriodSummaries.contains(periodKey) else {
            print("⏭️ [SummaryCoordinator] Month digest already being built, skipping duplicate call")
            return await fetchMonthDigest(date: date)
        }
        generatingPeriodSummaries.insert(periodKey)
        defer { generatingPeriodSummaries.remove(periodKey) }

        do {
            let inputs = try await loadDigestInputs(for: date)
            let stored = await storedMonth(bounds.start)
            let plan = planMonth(bounds.start, inputs: inputs, stored: stored, force: forceRegenerate)
            let isFinal = bounds.end <= Date()

            var digests: [MonthDigest] = []
            for journal in plan.reuse {
                if let digest = stored.journals[journal]?.digest {
                    print("💾 [SummaryCoordinator] ✅ CACHE HIT - \(journal.displayName) digest unchanged")
                    digests.append(digest)
                }
            }
            for journal in plan.markFinal {
                guard let digest = stored.journals[journal]?.digest, let journalInputs = inputs[journal] else { continue }
                // Same content, the month just ended: mark it final without running the model again
                let finalized = digest.withFinal(isFinal)
                try await saveMonthDigest(finalized, inputs: journalInputs)
                digests.append(finalized)
            }
            if !plan.rebuild.isEmpty {
                let generator: (any TextGenerating)?
                if let override {
                    generator = override
                } else {
                    generator = await summarizationEngine.digestGenerator()
                }
                for journal in plan.rebuild {
                    guard let journalInputs = inputs[journal] else { continue }
                    let sources = await digestSources(from: journalInputs)
                    print("🧩 [SummaryCoordinator] Building \(isFinal ? "final" : "draft") \(journal.displayName) digest for \(bounds.start.formatted(.dateTime.month().year())) from \(sources.count) recordings with \(generator?.tier.displayName ?? "Basic")")
                    // A story written by a better engine is kept; only the items and numbers are
                    // rebuilt. Rebuild (force) is the person's explicit choice to rewrite it.
                    let previous = stored.journals[journal]?.digest
                    let keep = (!forceRegenerate && previous.map { $0.hasWrittenStory && (generator?.tier ?? .basic).isWeaker(than: $0.displayedEngineTier) } == true) ? previous : nil
                    if let keep {
                        print("🛡️ [SummaryCoordinator] Keeping the \(EngineTier(rawValue: keep.displayedEngineTier)?.displayName ?? keep.displayedEngineTier) story for \(journal.displayName); \(generator?.tier.displayName ?? "Key Sentences") would write a plainer one")
                    }
                    let digest = await MonthDigestBuilder.build(
                        monthStart: bounds.start,
                        sources: sources,
                        isFinal: isFinal,
                        generator: generator,
                        journal: journal,
                        keepingStoryFrom: keep
                    )
                    try await saveMonthDigest(digest, inputs: journalInputs)
                    digests.append(digest)
                    print("✅ [SummaryCoordinator] \(journal.displayName) digest saved: \(digest.items.count) items")
                }
                if generator?.tier == .local {
                    await summarizationEngine.getLocalEngine().unloadModel()
                }
            }
            // Recordings moved to the other journal, or deleted: their old digest no longer applies
            for journal in plan.remove {
                if let row = stored.journals[journal]?.row {
                    try? await databaseManager.deleteSummary(id: row.id)
                }
            }
            // Only reached when every step above succeeded, so each journal now has its own digest
            if plan.removeLegacy {
                await removeLegacyDigests(bounds.start)
                print("🧹 [SummaryCoordinator] Replaced the mixed digest for \(bounds.start.formatted(.dateTime.month().year())) with journal digests")
            }

            if inputs.isEmpty {
                print("ℹ️ [SummaryCoordinator] No session summaries for \(bounds.start.formatted(.dateTime.month().year())), no digest to build")
                return nil
            }
            return MonthDigest.combining(digests.sorted { ($0.journal == .work ? 0 : 1) < ($1.journal == .work ? 0 : 1) })
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
                category: inputs.journal,
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
            inputHash: inputs.inputHash,
            category: inputs.journal
        )
    }

    /// Bring at most one ended month up to date: both its journal digests are built if missing,
    /// out of date or still drafts. Called when the app comes to the foreground; one month at a
    /// time keeps each launch light, and older mixed digests get replaced this way over time.
    /// Looks back to the start of last year; Year Wrap builds anything older it needs.
    @discardableResult
    public func finalizeNextClosedMonthDigest() async -> Bool {
        let calendar = Calendar.current
        guard let currentMonth = monthBounds(for: Date())?.start,
              let lastYear = calendar.date(byAdding: .year, value: -1, to: currentMonth),
              let lookbackStart = calendar.date(from: DateComponents(year: calendar.component(.year, from: lastYear), month: 1, day: 1)) else { return false }

        do {
            let summaries = try await liveSessionSummaries(from: lookbackStart, to: currentMonth)
            let months = Set(summaries.compactMap { monthBounds(for: $0.periodStart)?.start }).sorted(by: >)

            for month in months {
                let inputs = try await loadDigestInputs(for: month)
                guard planMonth(month, inputs: inputs, stored: await storedMonth(month)).needsWork else { continue }

                print("🗓️ [SummaryCoordinator] Finalizing digests for \(month.formatted(.dateTime.month().year()))")
                await updateMonthDigest(date: month)
                return true
            }
        } catch {
            print("❌ [SummaryCoordinator] Failed to check month digests: \(error)")
        }
        return false
    }

    /// Bump when Year Wrap generation changes, so a cached wrap is rebuilt
    private static let yearWrapVersion = "yearwrap-v4"
    
    /// Year Wrap, built from the year's month digests with Cloud AI, Apple Intelligence, the
    /// offline model, or with no model at all for Key Sentences (numbers, people, places and
    /// the most-mentioned items, no written story).
    /// Brings every month's journal digests up to date, then writes one wrap per journal from that
    /// journal's months only (one model request each with Smartest). All is the two put together
    /// in code, with each journal's own title and summary. A journal with no recordings this year
    /// gets no wrap. Throws when the engine isn't available or nothing could be built.
    public func wrapUpYear(date: Date, engine: EngineTier, forceRegenerate: Bool = false) async throws {
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

        let generator = try await summarizationEngine.yearWrapGenerator(tier: engine)
        let sessionSummaries = try await liveSessionSummaries(from: startOfYear, to: endOfYear)
        let months = Set(sessionSummaries.compactMap { monthBounds(for: $0.periodStart)?.start }).sorted()
        guard !months.isEmpty else {
            throw SummarizationError.summarizationFailed("There are no summarized recordings from \(year) yet.")
        }

        // Only months whose digest is missing or out of date take real work; count just those as steps.
        // Regenerating rewrites the wraps but keeps up-to-date digests.
        var staleMonths: Set<Date> = []
        var splittingOldMonths = false
        for month in months {
            let plan = planMonth(month, inputs: try await loadDigestInputs(for: month), stored: await storedMonth(month))
            if !plan.rebuild.isEmpty {
                staleMonths.insert(month)
                if plan.removeLegacy { splittingOldMonths = true }
            }
        }
        // The first wrap after journals arrived rereads months saved the old way; say why it's slower
        let firstRunNote = splittingOldMonths && staleMonths.count > 1
            ? "This first wrap separates each month into work and personal, so it takes longer than usual."
            : nil
        let journals = SessionCategory.allCases
        let totalSteps = staleMonths.count + journals.count
        var step = 0

        // 1. Month digests, rebuilt with the same engine so a slow local model never runs here.
        //    Each journal's own digests feed its wrap; the combined months give All its numbers.
        var journalDigests: [SessionCategory: [MonthDigest]] = [:]
        var combinedMonths: [MonthDigest] = []
        for month in months {
            if staleMonths.contains(month) {
                step += 1
                onYearWrapProgressUpdate?(YearWrapProgress(step: step, total: totalSteps,
                    label: "Reading \(month.formatted(.dateTime.month(.wide)))", note: firstRunNote))
            }
            guard let combined = await updateMonthDigest(date: month, generator: generator) else { continue }
            combinedMonths.append(combined)
            for (journal, entry) in await storedMonth(month).journals {
                if let digest = entry.digest { journalDigests[journal, default: []].append(digest) }
            }
        }
        guard !journalDigests.isEmpty else {
            throw SummarizationError.summarizationFailed("Couldn't read your months. Try again in a moment.")
        }

        // 2. One wrap per journal, each from that journal's months only
        var wraps: [SessionCategory: YearWrapData] = [:]
        for journal in journals {
            step += 1
            onYearWrapProgressUpdate?(YearWrapProgress(step: step, total: totalSteps,
                label: journal == .work ? "Writing your work year" : "Writing your personal year"))

            guard let digests = journalDigests[journal], !digests.isEmpty else {
                // No recordings in this journal this year: remove a wrap left from an earlier run
                if let old = try? await databaseManager.fetchPeriodSummary(type: .yearWrap, date: startOfYear, category: journal) {
                    try? await databaseManager.deleteSummary(id: old.id)
                }
                continue
            }

            // The wrap only changes when its months or the engine change
            let digestTexts = digests.compactMap { try? $0.jsonString() }
            let inputHash = await databaseManager.computeInputHash([Self.yearWrapVersion, engine.rawValue, journal.rawValue] + digestTexts)
            if !forceRegenerate,
               let existing = try? await databaseManager.fetchPeriodSummary(type: .yearWrap, date: startOfYear, category: journal),
               existing.inputHash == inputHash,
               let cached = YearWrapData.parse(existing.text) {
                print("💾 [SummaryCoordinator] ✅ CACHE HIT - \(journal.displayName) Year Wrap unchanged")
                wraps[journal] = cached
                continue
            }

            print("🎁 [SummaryCoordinator] Building \(journal.displayName) Year Wrap for \(year) from \(digests.count) months with \(engine.displayName)")
            let wrap = await YearWrapBuilder.build(year: year, digests: digests, generator: generator, scope: journal.itemFilter)
            let sessionIds = Set(digests.flatMap { $0.items.flatMap(\.sessionIds) })
            try await saveYearWrap(wrap, start: startOfYear, end: endOfYear, engineTier: engine.rawValue,
                                   sources: sessionSummaries.compactMap { $0.sessionId }.filter { sessionIds.contains($0) },
                                   inputHash: inputHash, category: journal)
            wraps[journal] = wrap
        }

        // 3. All: the two journals put together in code, no model request
        guard let all = YearWrapData.combining(wraps, year: year, stats: YearWrapBuilder.stats(for: combinedMonths)) else {
            throw SummarizationError.summarizationFailed("Year Wrap couldn't be built. Try again in a moment.")
        }
        try await saveYearWrap(all, start: startOfYear, end: endOfYear, engineTier: engine.rawValue,
                               sources: sessionSummaries.compactMap { $0.sessionId }, inputHash: nil, category: nil)

        // Wraps from before journals, stored as their own types, are replaced by the ones above
        for legacyType in [PeriodType.yearWrapWork, .yearWrapPersonal] {
            if let old = try? await databaseManager.fetchPeriodSummary(type: legacyType, date: startOfYear) {
                try? await databaseManager.deleteSummary(id: old.id)
            }
        }
        if engine == .local {
            await summarizationEngine.getLocalEngine().unloadModel()
        }
        print("✅ [SummaryCoordinator] Year Wraps saved: \(wraps.keys.map(\.displayName).sorted().joined(separator: ", ")) and All")
    }

    private func saveYearWrap(_ wrap: YearWrapData, start: Date, end: Date, engineTier: String, sources: [UUID],
                              inputHash: String?, category: SessionCategory?) async throws {
        let topicsJSON = (try? JSONEncoder().encode(wrap.topWorkedOnTopics.map { $0.text })).map { String(decoding: $0, as: UTF8.self) }
        try await databaseManager.upsertPeriodSummary(
            type: .yearWrap,
            text: try YearWrapBuilder.jsonString(wrap),
            start: start,
            end: end,
            topicsJSON: topicsJSON,
            entitiesJSON: nil,
            engineTier: engineTier,
            sourceIds: await databaseManager.sourceIdsToJSON(sources),
            inputHash: inputHash,
            category: category
        )
    }
    
    /// How many of the year's recordings are new or changed since the Year Wrap was built.
    /// Changed means its journal, notes or summary changed, all of which feed the wrap.
    public func getNewSessionsSinceYearWrap(yearWrap: Summary, year: Int, journal: SessionCategory? = nil) async throws -> Int {
        let yearlyData = try await databaseManager.fetchSessionsByYear()
        guard let yearData = yearlyData.first(where: { $0.year == year }) else {
            print("⚠️ [SummaryCoordinator] No sessions found for year \(year)")
            return 0
        }
        let yearSessions = Set(yearData.sessionIds)

        // Recorded after the wrap was built
        var outdated: Set<UUID> = []
        for sessionId in yearSessions {
            if let firstChunk = try? await databaseManager.fetchChunksBySession(sessionId: sessionId).first,
               firstChunk.createdAt > yearWrap.createdAt {
                outdated.insert(sessionId)
            }
        }
        // Changed after the wrap was built
        let changed = try await databaseManager.fetchSessionIdsContentChanged(since: yearWrap.createdAt)
        outdated.formUnion(changed.intersection(yearSessions))

        // Only this journal's recordings count toward its wrap
        if let journal, !outdated.isEmpty {
            let metadata = try await databaseManager.fetchSessionMetadataBatch(sessionIds: Array(outdated))
            outdated = outdated.filter { Self.journal(of: metadata[$0]) == journal }
        }

        print("📊 [SummaryCoordinator] Year Wrap staleness check: \(outdated.count) recordings new or changed since \(yearWrap.createdAt)")
        return outdated.count
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

/// Where a Year Wrap run is: step `step` of `total` is in progress
public struct YearWrapProgress: Equatable, Sendable {
    public let step: Int
    public let total: Int
    public let label: String
    /// Extra context for a slower-than-usual run, shown under the progress bar
    public var note: String? = nil

    /// Share of the work done before this step, for a progress bar
    public var fractionDone: Double {
        total > 0 ? Double(step - 1) / Double(total) : 0
    }
}
