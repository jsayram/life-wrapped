// =============================================================================
// Transcription — Transcription Manager
// =============================================================================

import Foundation
import Speech
import SharedModels
import Storage

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
        print("🎯 [TranscriptionManager] transcribe() called for chunk: \(chunk.id)")
        print("🎯 [TranscriptionManager] File URL: \(chunk.fileURL)")
        print("🎯 [TranscriptionManager] Locale: \(locale.identifier)")
        
        var lastError: Error?
        let startTime = Date()
        
        // Retry loop
        for attempt in 0...maxRetries {
            print("🔄 [TranscriptionManager] Attempt \(attempt + 1)/\(maxRetries + 1)")
            do {
                let segments = try await performTranscription(chunk: chunk, locale: locale)
                print("✅ [TranscriptionManager] Transcription successful! Got \(segments.count) segments")
                
                // Record success
                let duration = Date().timeIntervalSince(startTime)
                await statistics.recordSuccess(segmentCount: segments.count, duration: duration)
                
                return segments
            } catch {
                print("❌ [TranscriptionManager] Transcription attempt \(attempt + 1) failed: \(error)")
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
        print("🎤 [TranscriptionManager] performTranscription() starting")
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: chunk.fileURL.path) else {
            print("❌ [TranscriptionManager] Audio file not found: \(chunk.fileURL.path)")
            throw TranscriptionError.audioFileNotFound(chunk.fileURL)
        }
        print("✅ [TranscriptionManager] Audio file exists")
        
        // Create recognizer
        print("🗣️ [TranscriptionManager] Creating SFSpeechRecognizer for locale: \(locale.identifier)")
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            print("❌ [TranscriptionManager] SFSpeechRecognizer not available for locale")
            throw TranscriptionError.notAvailable
        }
        print("✅ [TranscriptionManager] SFSpeechRecognizer created")
        
        guard recognizer.isAvailable else {
            print("❌ [TranscriptionManager] SFSpeechRecognizer not available on this device")
            throw TranscriptionError.notAvailable
        }
        print("✅ [TranscriptionManager] SFSpeechRecognizer is available")
        
        // Create recognition request
        print("📄 [TranscriptionManager] Creating recognition request")
        let request = SFSpeechURLRecognitionRequest(url: chunk.fileURL)
        request.shouldReportPartialResults = true // Enable partial results to get more complete transcription
        request.requiresOnDeviceRecognition = true // Privacy: on-device only
        
        // Add context to improve recognition accuracy
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        print("✅ [TranscriptionManager] Recognition request created (on-device only)")
        
        // Capture values needed by the callback (to avoid actor isolation issues)
        let chunkID = chunk.id
        let localeIdentifier = locale.identifier
        
        // Perform recognition - extract just the text from result inside callback
        // to avoid sending non-Sendable SFSpeechRecognitionResult across isolation boundaries
        let transcribedText: String = try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var lastText = ""
            
            recognizer.recognitionTask(with: request) { result, error in
                // Don't resume multiple times
                guard !hasResumed else { return }
                
                if let error = error {
                    hasResumed = true
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }
                
                guard let result = result else { return }
                
                // Update the latest transcription
                let text = result.bestTranscription.formattedString
                lastText = text
                
                if result.isFinal {
                    // Final result received
                    print("✅ [TranscriptionManager] Final result received: '\(text.prefix(50))...'")
                    hasResumed = true
                    continuation.resume(returning: text)
                } else {
                    // Partial result - just update lastText
                    print("⏳ [TranscriptionManager] Partial result: '\(text.prefix(30))...' (words: \(text.split(separator: " ").count))")
                }
            }
        }
        print("🔄 [TranscriptionManager] Recognition complete, converting to segments...")
        
        // Convert to segments after continuation completes (back on actor)
        let duration = chunk.endTime.timeIntervalSince(chunk.startTime)
        let segments = convertToSegmentsFromText(transcribedText, audioChunkID: chunkID, locale: Locale(identifier: localeIdentifier), duration: duration)
        print("✅ [TranscriptionManager] Converted to \(segments.count) segments")
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
