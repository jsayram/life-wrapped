// =============================================================================
// PermissionsCoordinator — Manages permission checks and authorization flows
// =============================================================================

import Foundation
import AVFoundation
import Speech

/// Manages microphone and speech recognition permission checks
public final class PermissionsCoordinator: Sendable {
    
    // MARK: - Permission Checks
    
    /// Check if required permissions for app launch are granted
    /// NOTE: Only checks microphone - speech recognition is requested when user starts recording
    public func checkPermissions() async -> Bool {
        let micPermission = await checkMicrophonePermission()
        let speechPermission = await checkSpeechRecognitionPermission()
        
        // Only microphone is required for initial setup
        // Speech recognition will be requested just-in-time when recording starts
        print("🔐 [PermissionsCoordinator] Permissions - Mic: \(micPermission), Speech: \(speechPermission)")
        print("ℹ️ [PermissionsCoordinator] Only microphone required for setup (speech requested when recording)")
        
        return micPermission
    }
    
    /// Check microphone permission status
    public func checkMicrophonePermission() async -> Bool {
        #if os(iOS)
        let status = AVAudioApplication.shared.recordPermission
        return status == .granted
        #else
        return true
        #endif
    }
    
    /// Check speech recognition permission status
    public func checkSpeechRecognitionPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        return status == .authorized
    }
}
