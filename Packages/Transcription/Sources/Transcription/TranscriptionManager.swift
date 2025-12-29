// =============================================================================
// Transcription — Transcription Manager
// =============================================================================

import Foundation
import Speech
import SharedModels
import Storage

/// Helper class to track transcription state across callbacks
@MainActor
private class TranscriptionState {
    var hasResumed = false
    var allUtterances: [String] = []  // All completed utterances
    var currentUtterance = ""         // Current in-progress utterance
    var finalCount = 0
    
    var fullText: String {
        var parts = allUtterances
        if !currentUtterance.isEmpty {
            parts.append(currentUtterance)
        }
        return parts.joined(separator: " ")
    }
}

/// Actor that manages speech-to-text transcription using Apple's Speech framework
/// Handles batch processing of audio chunks with progress tracking
public actor TranscriptionManager {
    
    // MARK: - Properties
    
    private let storage: DatabaseManager
    private var activeRecognitionTasks: [UUID: SFSpeechRecognitionTask] = [:]
    
    /// Statistics tracker for transcription operations
    public let statistics = TranscriptionStatistics()
    
    // MARK: - Initialization
    
    public init(storage: DatabaseManager) {
        self.storage = storage
    }
    
    // MARK: - Permission Management
    
    /// Request speech recognition authorization
    public func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    /// Check if speech recognition is available
    public func isAvailable(for locale: Locale = .current) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            return false
        }
        return recognizer.isAvailable
    }
    
    // MARK: - Single Chunk Transcription
    
    /// Transcribe a single audio chunk with retry support
    /// - Parameters:
    ///   - chunk: Audio chunk to transcribe
    ///   - locale: Locale for recognition (default: current locale)
    ///   - maxRetries: Maximum retry attempts (default: 2)
    ///   - retryDelay: Delay between retries in seconds (default: 1.0)
    /// - Returns: Array of transcript segments
    public func transcribe(
        chunk: AudioChunk,
        locale: Locale = .current,
        maxRetries: Int = 2,
        retryDelay: TimeInterval = 1.0
    ) async throws -> [TranscriptSegment] {
        #if DEBUG
        print("🎯 [TranscriptionManager] transcribe() called for chunk: \(chunk.id)")
        #endif
        #if DEBUG
        print("🎯 [TranscriptionManager] File URL: \(chunk.fileURL)")
        #endif
        #if DEBUG
        print("🎯 [TranscriptionManager] Locale: \(locale.identifier)")
        #endif
        
        var lastError: Error?
        let startTime = Date()
        
        // Retry loop
        for attempt in 0...maxRetries {
            #if DEBUG
            print("🔄 [TranscriptionManager] Attempt \(attempt + 1)/\(maxRetries + 1)")
            #endif
            do {
                let segments = try await performTranscription(chunk: chunk, locale: locale)
                #if DEBUG
                print("✅ [TranscriptionManager] Transcription successful! Got \(segments.count) segments")
                #endif
                
                // Record success
                let duration = Date().timeIntervalSince(startTime)
                await statistics.recordSuccess(segmentCount: segments.count, duration: duration)
                
                return segments
            } catch {
                #if DEBUG
                print("❌ [TranscriptionManager] Transcription attempt \(attempt + 1) failed: \(error)")
                #endif
                lastError = error
                
                // Don't retry for certain errors
                if let transcriptionError = error as? TranscriptionError {
                    switch transcriptionError {
                    case .notAuthorized, .notAvailable, .cancelled:
                        await statistics.recordFailure()
                        throw transcriptionError
                    default:
                        break
                    }
                }
                
                // Wait before retry (except on last attempt)
                if attempt < maxRetries {
                    try await Task.sleep(for: .seconds(retryDelay))
                }
            }
        }
        
        // All retries exhausted
        await statistics.recordFailure()
        throw lastError ?? TranscriptionError.recognitionFailed("Unknown error after \(maxRetries + 1) attempts")
    }
    
    /// Perform transcription without retry logic (internal method)
    private func performTranscription(
        chunk: AudioChunk,
        locale: Locale
    ) async throws -> [TranscriptSegment] {
        #if DEBUG
        print("🎤 [TranscriptionManager] performTranscription() starting")
        #endif
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: chunk.fileURL.path) else {
            #if DEBUG
            print("❌ [TranscriptionManager] Audio file not found: \(chunk.fileURL.path)")
            #endif
            throw TranscriptionError.audioFileNotFound(chunk.fileURL)
        }
        #if DEBUG
        print("✅ [TranscriptionManager] Audio file exists")
        #endif
        
        // Create recognizer
        #if DEBUG
        print("🗣️ [TranscriptionManager] Creating SFSpeechRecognizer for locale: \(locale.identifier)")
        #endif
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            #if DEBUG
            print("❌ [TranscriptionManager] SFSpeechRecognizer not available for locale")
            #endif
            throw TranscriptionError.notAvailable
        }
        #if DEBUG
        print("✅ [TranscriptionManager] SFSpeechRecognizer created")
        #endif
        
        guard recognizer.isAvailable else {
            #if DEBUG
            print("❌ [TranscriptionManager] SFSpeechRecognizer not available on this device")
            #endif
            throw TranscriptionError.notAvailable
        }
        #if DEBUG
        print("✅ [TranscriptionManager] SFSpeechRecognizer is available")
        #endif
        
        // Create recognition request
        #if DEBUG
        print("📄 [TranscriptionManager] Creating recognition request")
        #endif
        let request = SFSpeechURLRecognitionRequest(url: chunk.fileURL)
        request.shouldReportPartialResults = true // Enable partial results to get more complete transcription
        request.requiresOnDeviceRecognition = true // Privacy: on-device only
        
        // Add context to improve recognition accuracy
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        #if DEBUG
        print("✅ [TranscriptionManager] Recognition request created (on-device only)")
        #endif
        
        // Capture values needed by the callback (to avoid actor isolation issues)
        let chunkID = chunk.id
        let localeIdentifier = locale.identifier
        let duration = chunk.endTime.timeIntervalSince(chunk.startTime)
        
        // Perform recognition - wait for entire audio file to be processed
        // Do NOT return early on "final" results (pauses) - keep accumulating all text
        let transcribedText: String = try await withCheckedThrowingContinuation { continuation in
            let state = TranscriptionState()
            
            _ = recognizer.recognitionTask(with: request) { result, error in
                // Extract text immediately to avoid sending non-Sendable result
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                
                Task { @MainActor in
                    guard !state.hasResumed else { return }
                    
                    if let error = error {
                        // Recognition ended with error - use what we have
                        #if DEBUG
                        print("⚠️ [TranscriptionManager] Recognition ended: \(error.localizedDescription)")
                        #endif
                        let finalText = state.fullText
                        if !finalText.isEmpty {
                            #if DEBUG
                            print("✅ [TranscriptionManager] Using accumulated: \(finalText.split(separator: " ").count) words total")
                            #endif
                            state.hasResumed = true
                            continuation.resume(returning: finalText)
                        } else {
                            state.hasResumed = true
                            continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                        }
                        return
                    }
                    
                    guard let text = text else { return }
                    
                    let newWordCount = text.split(separator: " ").count
                    let currentWordCount = state.currentUtterance.split(separator: " ").count
                    
                    // Detect abandoned utterance: if new text is shorter than current,
                    // Speech Recognition has abandoned the previous utterance without marking it final
                    if !state.currentUtterance.isEmpty && newWordCount < currentWordCount {
                        #if DEBUG
                        print("🔄 [TranscriptionManager] Abandoned utterance detected (was \(currentWordCount) words, now \(newWordCount) words)")
                        #endif
                        state.allUtterances.append(state.currentUtterance)
                        #if DEBUG
                        print("💾 [TranscriptionManager] Saved abandoned utterance #\(state.allUtterances.count): '\(state.currentUtterance.prefix(50))...' (\(currentWordCount) words)")
                        #endif
                        state.currentUtterance = ""
                    }
                    
                    if isFinal {
                        // This utterance is complete - save it and reset for next
                        state.finalCount += 1
                        if !text.isEmpty && !state.allUtterances.contains(text) {
                            state.allUtterances.append(text)
                            #if DEBUG
                            print("✅ [TranscriptionManager] Final #\(state.finalCount): '\(text.prefix(50))...' (\(text.split(separator: " ").count) words) - Total: \(state.fullText.split(separator: " ").count) words")
                            #endif
                        }
                        state.currentUtterance = ""
                        // Continue listening for more utterances after the pause
                    } else {
                        // Partial result - update current utterance
                        state.currentUtterance = text
                        #if DEBUG
                        print("⏳ [TranscriptionManager] Partial: '\(text.prefix(30))...' (\(newWordCount) words) - Total: \(state.fullText.split(separator: " ").count) words")
                        #endif
                    }
                }
            }
            
            // Set up timeout as safety net, but allow early completion
            Task { @MainActor in
                // Use shorter timeout - just 3 seconds past audio duration or 5 seconds minimum
                let timeoutDuration = max(duration + 3.0, 5.0)
                
                // Check every 0.5 seconds if we have stable transcription
                let checkInterval = 0.5
                var lastWordCount = 0
                var stableCount = 0
                let stableThreshold = 3 // 1.5 seconds of no changes
                
                for _ in 0..<Int(timeoutDuration / checkInterval) {
                    try? await Task.sleep(for: .seconds(checkInterval))
                    guard !state.hasResumed else { return }
                    
                    let currentWordCount = state.fullText.split(separator: " ").count
                    
                    // If word count hasn't changed and we have content, increment stable counter
                    if currentWordCount > 0 && currentWordCount == lastWordCount {
                        stableCount += 1
                        
                        // If stable for threshold checks and we have at least one final result, we're done
                        if stableCount >= stableThreshold && state.finalCount > 0 {
                            let finalText = state.fullText
                            #if DEBUG
                            print("✅ [TranscriptionManager] Early completion - stable at \(currentWordCount) words, \(state.finalCount) utterances")
                            #endif
                            state.hasResumed = true
                            continuation.resume(returning: finalText)
                            return
                        }
                    } else {
                        stableCount = 0
                        lastWordCount = currentWordCount
                    }
                }
                
                // Timeout reached - use what we have
                guard !state.hasResumed else { return }
                let finalText = state.fullText
                #if DEBUG
                print("⏱️ [TranscriptionManager] Timeout reached - \(state.finalCount) utterances, \(finalText.split(separator: " ").count) total words")
                #endif
                state.hasResumed = true
                continuation.resume(returning: finalText)
            }
        }
        #if DEBUG
        print("🔄 [TranscriptionManager] Recognition complete, converting to segments...")
        #endif
        
        // Convert to segments after continuation completes (back on actor)
        let segments = convertToSegmentsFromText(transcribedText, audioChunkID: chunkID, locale: Locale(identifier: localeIdentifier), duration: duration)
        #if DEBUG
        print("✅ [TranscriptionManager] Converted to \(segments.count) segments")
        #endif
        return segments
    }
    
    // MARK: - Batch Processing
    
    /// Transcribe multiple audio chunks in sequence with retry support
    /// - Parameters:
    ///   - chunks: Array of audio chunks to transcribe
    ///   - locale: Locale for recognition
    ///   - maxRetries: Maximum retry attempts per chunk (default: 2)
    ///   - retryDelay: Delay between retries in seconds (default: 1.0)
    ///   - onProgress: Callback for progress updates (completed, total)
    /// - Returns: Total number of segments created
    public func transcribeBatch(
        chunks: [AudioChunk],
        locale: Locale = .current,
        maxRetries: Int = 2,
        retryDelay: TimeInterval = 1.0,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> Int {
        var totalSegments = 0
        
        for (index, chunk) in chunks.enumerated() {
            let segments = try await transcribe(
                chunk: chunk,
                locale: locale,
                maxRetries: maxRetries,
                retryDelay: retryDelay
            )
            
            // Save segments to storage
            for segment in segments {
                try await storage.insertTranscriptSegment(segment)
            }
            
            totalSegments += segments.count
            
            // Report progress
            onProgress?(index + 1, chunks.count)
        }
        
        return totalSegments
    }
    
    // MARK: - Cancellation
    
    /// Cancel transcription for a specific chunk
    public func cancelTranscription(for chunkID: UUID) {
        activeRecognitionTasks[chunkID]?.cancel()
        activeRecognitionTasks.removeValue(forKey: chunkID)
    }
    
    /// Cancel all active transcriptions
    public func cancelAllTranscriptions() {
        for task in activeRecognitionTasks.values {
            task.cancel()
        }
        activeRecognitionTasks.removeAll()
    }
    
    // MARK: - Private Helpers
    
    private func storeTask(_ task: SFSpeechRecognitionTask, for chunkID: UUID) {
        activeRecognitionTasks[chunkID] = task
    }
    
    private func convertToSegments(
        from result: SFSpeechRecognitionResult,
        audioChunkID: UUID,
        locale: Locale
    ) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        
        // Process each transcription segment
        for segment in result.bestTranscription.segments {
            let transcriptSegment = TranscriptSegment(
                audioChunkID: audioChunkID,
                startTime: segment.timestamp,
                endTime: segment.timestamp + segment.duration,
                text: segment.substring,
                confidence: segment.confidence,
                languageCode: locale.identifier
            )
            
            segments.append(transcriptSegment)
        }
        
        // If no segments, create one with full text
        if segments.isEmpty && !result.bestTranscription.formattedString.isEmpty {
            let fullSegment = TranscriptSegment(
                audioChunkID: audioChunkID,
                startTime: 0.0,
                endTime: 0.0, // Unknown duration
                text: result.bestTranscription.formattedString,
                confidence: 0.0, // Unknown confidence
                languageCode: locale.identifier
            )
            segments.append(fullSegment)
        }
        
        return segments
    }
    
    /// Convert transcribed text to segments (simplified version when we only have the text)
    private func convertToSegmentsFromText(
        _ text: String,
        audioChunkID: UUID,
        locale: Locale,
        duration: TimeInterval
    ) -> [TranscriptSegment] {
        guard !text.isEmpty else {
            return []
        }
        
        // Create a single segment with the full transcribed text
        // Use the audio chunk's actual duration for accurate time tracking
        let segment = TranscriptSegment(
            audioChunkID: audioChunkID,
            startTime: 0.0,
            endTime: duration,
            text: text,
            confidence: 0.0, // Unknown confidence when using text-only
            languageCode: locale.identifier
        )
        
        return [segment]
    }
}
