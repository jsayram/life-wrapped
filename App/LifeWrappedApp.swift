import SwiftUI

@main
struct LifeWrappedApp: App {
    @StateObject private var coordinator = AppCoordinator()
    
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
    }
}
