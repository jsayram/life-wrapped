import SwiftUI
import SharedModels
import Charts
import Transcription
import Storage
import Summarization
import Security

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        Group {
            if coordinator.isInitialized {
                TabView(selection: $selectedTab) {
                    HomeTab()
                        .tabItem {
                            Label("Home", systemImage: "house.fill")
                        }
                        .tag(0)

                    HistoryTab()
                        .tabItem {
                            Label("History", systemImage: "list.bullet")
                        }
                        .tag(1)

            OverviewTab()
                .tabItem {
                    Label("Overview", systemImage: "doc.text.fill")
                }
                .tag(2)

            SettingsTab()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
                }
                .tint(AppTheme.purple)
                .disabled(coordinator.isGeneratingYearWrap)
            } else {
                Color.clear
            }
        }
        .sheet(isPresented: $coordinator.needsPermissions) {
            PermissionsView()
                .environmentObject(coordinator)
                .interactiveDismissDisabled()
        }
        .toast($coordinator.currentToast)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToSettingsTab"))) { _ in
            selectedTab = 3
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToSmartestConfig"))) { _ in
            selectedTab = 3
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToOverviewTab"))) { _ in
            selectedTab = 2
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToTab"))) { notification in
            if let tabIndex = notification.userInfo?["tabIndex"] as? Int {
                selectedTab = tabIndex
            }
        }
        .overlay {
            if !coordinator.isInitialized && coordinator.initializationError == nil && !coordinator.needsPermissions {
                LoadingOverlay()
            }
            
            // Show banner when Year Wrap is generating and tabs are locked
            if coordinator.isGeneratingYearWrap {
                VStack {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Generating Year Wrap...")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 4) {
                            Text("⚠️ Keep app open and screen unlocked")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.yellow)
                            Text("Navigation locked • Don't minimize • 2-3 minutes")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.black.opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .padding(.top, 8)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Monitor scene phase changes - warn if backgrounding during generation
            if newPhase == .background && coordinator.isGeneratingYearWrap {
                print("⚠️ [ContentView] CRITICAL: App backgrounded during Year Wrap generation!")
                print("⚠️ [ContentView] Metal GPU work will fail in background - generation may crash")
                // Note: Cannot prevent the crash, Metal restricts GPU work in background
            } else if newPhase == .active && coordinator.isGeneratingYearWrap {
                print("✅ [ContentView] App foregrounded during Year Wrap generation")
            }
        }
        .alert("Initialization Error", isPresented: .constant(coordinator.initializationError != nil)) {
            Button("Retry") {
                Task {
                    await coordinator.initialize()
                }
            }
        } message: {
            if let error = coordinator.initializationError {
                Text(error.localizedDescription)
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppCoordinator.previewInstance())
    }
}
