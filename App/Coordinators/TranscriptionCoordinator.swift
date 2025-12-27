import Foundation
import SharedModels
import Storage
import Transcription

/// Manages transcription queue, parallel processing, and status tracking
@MainActor
public final class TranscriptionCoordinator {
    
    // MARK: - Dependencies
    
    private let databaseManager: DatabaseManager
    private let transcriptionManager: TranscriptionManager
    
    // MARK: - Transcription Queue
    
    private var pendingTranscriptionIds: [UUID] = []
    private var activeTranscriptionCount: Int = 0
    private let maxConcurrentTranscriptions: Int = 3
    
    // MARK: - Status Callbacks
    
    public var onStatusUpdate: ((Set<UUID>, Set<UUID>, Set<UUID>) async -> Void)?  // transcribing, transcribed, failed
    public var onSessionComplete: ((UUID) async -> Void)?  // Called when all chunks in a session are transcribed
    
    // MARK: - Initialization
    
    public init(databaseManager: DatabaseManager, transcriptionManager: TranscriptionManager) {
        self.databaseManager = databaseManager
        self.transcriptionManager = transcriptionManager
    }
    
    // MARK: - Queue Management
    
    public func enqueueChunk(_ chunkId: UUID) {
        pendingTranscriptionIds.append(chunkId)
        Task {
            await processTranscriptionQueue()
        }
    }
    
    public func retryTranscription(chunkId: UUID, failedChunkIds: inout Set<UUID>) {
        failedChunkIds.remove(chunkId)
        pendingTranscriptionIds.append(chunkId)
        Task {
            await processTranscriptionQueue()
        }
    }
    
    private func processTranscriptionQueue() async {
        // Launch transcriptions up to max concurrent limit
        while activeTranscriptionCount < maxConcurrentTranscriptions && !pendingTranscriptionIds.isEmpty {
            let chunkId = pendingTranscriptionIds.removeFirst()
            activeTranscriptionCount += 1
            
            Task {
                await transcribeChunk(chunkId: chunkId)
                activeTranscriptionCount -= 1
                // Continue processing queue
                await processTranscriptionQueue()
            }
        }
    }
    
    // MARK: - Transcription
    
    private func transcribeChunk(chunkId: UUID) async {
        do {
            // Fetch chunk from database
            guard let chunk = try await databaseManager.fetchAudioChunk(id: chunkId) else {
                print("❌ [TranscriptionCoordinator] Chunk not found: \(chunkId)")
                await updateStatus(transcribing: [], transcribed: [], failed: [chunkId])
                return
            }
            
            print("🎯 [TranscriptionCoordinator] Starting transcription for chunk \(chunk.chunkIndex)")
            await updateStatus(transcribing: [chunkId], transcribed: [], failed: [])
            
            let segments = try await transcribeAudio(chunk: chunk)
            
            print("✅ [TranscriptionCoordinator] Transcription complete for chunk \(chunk.chunkIndex): \(segments.count) segments")
            await updateStatus(transcribing: [], transcribed: [chunkId], failed: [])
            
            // Check if session is complete
            try await checkSessionCompletion(sessionId: chunk.sessionId)
            
        } catch {
            print("❌ [TranscriptionCoordinator] Transcription failed for chunk \(chunkId): \(error)")
            await updateStatus(transcribing: [], transcribed: [], failed: [chunkId])
        }
    }
    
    private func transcribeAudio(chunk: AudioChunk) async throws -> [TranscriptSegment] {
        print("🎤 [TranscriptionCoordinator] Transcribing audio chunk \(chunk.id)")
        
        // Use TranscriptionManager's transcribe method which returns segments
        let segments = try await transcriptionManager.transcribe(chunk: chunk)
        
        print("📝 [TranscriptionCoordinator] Transcribed \(segments.count) segments")
        
        // Save segments to database
        for segment in segments {
            try await databaseManager.insertTranscriptSegment(segment)
        }
        
        print("💾 [TranscriptionCoordinator] Saved \(segments.count) transcript segments")
        
        return segments
    }
    
    private func checkSessionCompletion(sessionId: UUID) async throws {
        let chunks = try await databaseManager.fetchChunksBySession(sessionId: sessionId)
        
        var allChunksTranscribed = true
        for chunk in chunks {
            let segments = try await databaseManager.fetchTranscriptSegments(audioChunkID: chunk.id)
            if segments.isEmpty {
                allChunksTranscribed = false
                break
            }
        }
        
        if allChunksTranscribed {
            print("✅ [TranscriptionCoordinator] All chunks transcribed for session \(sessionId)")
            await onSessionComplete?(sessionId)
        }
    }
    
    private func updateStatus(transcribing: [UUID], transcribed: [UUID], failed: [UUID]) async {
        // This will be called back to AppCoordinator to update @Published sets
        var transcribingSet = Set<UUID>()
        var transcribedSet = Set<UUID>()
        var failedSet = Set<UUID>()
        
        for id in transcribing {
            transcribingSet.insert(id)
        }
        for id in transcribed {
            transcribingSet.remove(id)
            transcribedSet.insert(id)
        }
        for id in failed {
            transcribingSet.remove(id)
            failedSet.insert(id)
        }
        
        await onStatusUpdate?(transcribingSet, transcribedSet, failedSet)
    }
}
