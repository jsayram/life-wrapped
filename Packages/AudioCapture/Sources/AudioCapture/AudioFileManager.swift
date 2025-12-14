// =============================================================================
// AudioCapture — Audio File Manager
// =============================================================================

import Foundation
import SharedModels

/// Utility for managing audio file storage and cleanup
public actor AudioFileManager {
    
    private let containerIdentifier: String
    private let fileManager = FileManager.default
    
    public init(containerIdentifier: String = AppConstants.appGroupIdentifier) {
        self.containerIdentifier = containerIdentifier
    }
    
    // MARK: - File Operations
    
    /// Get the audio directory URL
    public func getAudioDirectory() throws -> URL {
        // Prefer app group container when available, but fall back to temporary directory
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: containerIdentifier) {
            let audioDirectory = containerURL.appendingPathComponent("Audio", isDirectory: true)

            // Create directory if needed
            if !fileManager.fileExists(atPath: audioDirectory.path) {
                try fileManager.createDirectory(
                    at: audioDirectory,
                    withIntermediateDirectories: true
                )
            }

            return audioDirectory
        } else {
            print("⚠️ [AudioFileManager] App Group container not found; falling back to temporary directory")
            let audioDirectory = fileManager.temporaryDirectory.appendingPathComponent("Audio", isDirectory: true)
            if !fileManager.fileExists(atPath: audioDirectory.path) {
                try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
            }
            return audioDirectory
        }
    }
    
    /// Delete a specific audio file
    public func deleteAudioFile(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
    
    /// Delete audio files older than a specified date
    public func deleteOldAudioFiles(olderThan date: Date) throws -> Int {
        let audioDirectory = try getAudioDirectory()
        
        let contents = try fileManager.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        var deletedCount = 0
        
        for fileURL in contents {
            guard fileURL.pathExtension == "m4a" else { continue }
            
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let creationDate = attributes[.creationDate] as? Date,
               creationDate < date {
                try fileManager.removeItem(at: fileURL)
                deletedCount += 1
            }
        }
        
        return deletedCount
    }
    
    /// Get total size of audio files in bytes
    public func getTotalAudioSize() throws -> Int64 {
        let audioDirectory = try getAudioDirectory()
        
        let contents = try fileManager.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        
        var totalSize: Int64 = 0
        
        for fileURL in contents {
            guard fileURL.pathExtension == "m4a" else { continue }
            
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                totalSize += fileSize
            }
        }
        
        return totalSize
    }
    
    /// Get count of audio files
    public func getAudioFileCount() throws -> Int {
        let audioDirectory = try getAudioDirectory()
        
        let contents = try fileManager.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        return contents.filter { $0.pathExtension == "m4a" }.count
    }
}
