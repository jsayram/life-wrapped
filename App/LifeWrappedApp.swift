import SwiftUI

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
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
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
