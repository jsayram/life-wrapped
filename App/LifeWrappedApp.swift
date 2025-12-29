import SwiftUI

// MARK: - Deep Link Destination

enum DeepLinkDestination: String {
    case home = "home"
    case history = "history"
    case overview = "overview"
    case settings = "settings"
    case record = "record"
    
    var tabIndex: Int {
        switch self {
        case .home, .record: return 0
        case .history: return 1
        case .overview: return 2
        case .settings: return 3
        }
    }
}

@main
struct LifeWrappedApp: App {
    @StateObject private var coordinator = AppCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        print("🚀 [LifeWrappedApp] App starting...")
        print("📱 [LifeWrappedApp] iOS Version: \(UIDevice.current.systemVersion)")
        print("📱 [LifeWrappedApp] Device: \(UIDevice.current.model)")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .task {
                    print("⏳ [LifeWrappedApp] Triggering coordinator initialization...")
                    await coordinator.initialize()
                    print("✅ [LifeWrappedApp] Coordinator initialization task complete")
                }
                .onAppear {
                    print("👀 [LifeWrappedApp] ContentView appeared")
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }
    
    // MARK: - Deep Link Handling
    
    private func handleDeepLink(_ url: URL) {
        print("🔗 [LifeWrappedApp] Deep link received: \(url)")
        
        guard url.scheme == "lifewrapped" else {
            print("⚠️ [LifeWrappedApp] Unknown URL scheme: \(url.scheme ?? "nil")")
            return
        }
        
        guard let host = url.host else {
            print("⚠️ [LifeWrappedApp] No host in URL")
            return
        }
        
        // Parse query parameters
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let categoryString = queryItems.first(where: { $0.name == "category" })?.value
        
        if let categoryString = categoryString {
            print("📂 [LifeWrappedApp] Category from deep link: \(categoryString)")
        }
        
        if let destination = DeepLinkDestination(rawValue: host) {
            print("📍 [LifeWrappedApp] Navigating to: \(destination)")
            
            // Post notification for tab navigation
            let tabIndex = destination.tabIndex
            NotificationCenter.default.post(
                name: NSNotification.Name("SwitchToTab"),
                object: nil,
                userInfo: ["tabIndex": tabIndex]
            )
            
            // Handle special case for recording
            if destination == .record && coordinator.isInitialized && !coordinator.needsPermissions {
                Task { @MainActor in
                    // Small delay to ensure UI is ready
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    
                    // Set category if provided in deep link
                    if let categoryString = categoryString {
                        coordinator.setRecordingCategory(from: categoryString)
                    }
                    
                    if coordinator.recordingState.isRecording {
                        try? await coordinator.stopRecording()
                    } else {
                        try? await coordinator.startRecording()
                    }
                }
            }
        } else {
            print("⚠️ [LifeWrappedApp] Unknown destination: \(host)")
        }
    }
    
    // MARK: - Lifecycle Management
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        print("🔄 [LifeWrappedApp] Scene phase: \(oldPhase) → \(newPhase)")
        
        switch newPhase {
        case .active:
            print("🟢 [LifeWrappedApp] App became active")
            // App is in foreground and interactive
            Task {
                await coordinator.handleAppBecameActive()
            }
            
        case .inactive:
            print("🟡 [LifeWrappedApp] App became inactive")
            // App is in foreground but not receiving events (e.g., during transition)
            Task {
                await coordinator.handleAppBecameInactive()
            }
            
        case .background:
            print("🔴 [LifeWrappedApp] App entered background")
            // App is in background - continue recording if active
            Task {
                await coordinator.handleAppEnteredBackground()
            }
            
        @unknown default:
            print("⚠️ [LifeWrappedApp] Unknown scene phase")
        }
    }
}
