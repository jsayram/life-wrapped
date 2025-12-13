import SwiftUI

@main
struct LifeWrappedApp: App {
    @StateObject private var coordinator = AppCoordinator()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .task {
                    await coordinator.initialize()
                }
        }
    }
}
