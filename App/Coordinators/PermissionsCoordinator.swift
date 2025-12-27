// =============================================================================
// PermissionsCoordinator — Manages permission checks and authorization flows
// =============================================================================

import Foundation
import AVFoundation
import Speech

/// Manages microphone and speech recognition permission checks
public final class PermissionsCoordinator: Sendable {
    
    // MARK: - Permission Checks
    
    /// Check if all required permissions are granted
    public func checkPermissions() async -> Bool {
        let micPermission = await checkMicrophonePermission()
        let speechPermission = await checkSpeechRecognitionPermission()
        
        let hasAll = micPermission && speechPermission
        print("🔐 [PermissionsCoordinator] Permissions - Mic: \(micPermission), Speech: \(speechPermission)")
        
        return hasAll
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
