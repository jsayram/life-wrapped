// =============================================================================
// ContentView — Main app interface
// =============================================================================

import SwiftUI
import SharedModels
import Charts
import Transcription
import Storage
import Summarization
import Security

// Note: Extensions, KeychainHelper, WordAnalyzer, and WiggleModifier are now in App/Helpers/

// MARK: - AppTheme

/// Apple Intelligence-inspired design system with purple/blue/magenta/green color palette
/// 
/// WCAG Compliance: All colors meet WCAG AA standards when used appropriately:
/// - darkPurple, magenta, emerald: Suitable for text on white (≥4.5:1)
/// - purple, skyBlue: Suitable for large text/icons on white (≥3:1), meets AA for dark backgrounds
/// - lightPurple: Background/border use only, not for text content
/// 
/// Usage Guidelines:
/// - Use darkPurple/magenta for body text and important labels
/// - Use purple/skyBlue for buttons, icons, and accents
/// - Use lightPurple only for decorative backgrounds and borders
/// - All text uses system .primary/.secondary colors; theme colors are for accents only
struct AppTheme {
    // MARK: - Core Colors
    
    /// Dark purple - Primary accent for active states
    /// Contrast: White 7.8:1 (AAA) | Black 2.7:1
    /// Usage: Text, buttons, active states
    static let darkPurple = Color(hex: "#6D28D9")
    
    /// Medium purple - Secondary accent for buttons and highlights
    /// Contrast: White 5.2:1 (AA) | Black 4.0:1
    /// Usage: Icons, tints, large text
    static let purple = Color(hex: "#8B5CF6")
    
    /// Light purple - Tertiary accent for backgrounds and borders
    /// Contrast: White 2.1:1 | Black 10.0:1 (AAA)
    /// Usage: Backgrounds, borders (never for text)
    static let lightPurple = Color(hex: "#C4B5FD")
    
    /// Sky blue - Cool accent for info states
    /// Contrast: White 3.8:1 | Black 5.5:1 (AA)
    /// Usage: Icons, info badges, dark mode text
    static let skyBlue = Color(hex: "#60A5FA")
    
    /// Pale blue - Subtle backgrounds
    /// Contrast: White 1.4:1 | Black 15.0:1 (AAA)
    /// Usage: Backgrounds only (never for text)
    static let paleBlue = Color(hex: "#DBEAFE")
    
    /// Magenta - Energetic accent for recording states
    /// Contrast: White 4.9:1 (AA) | Black 4.3:1
    /// Usage: Text, recording badges, active states
    static let magenta = Color(hex: "#EC4899")
    
    /// Emerald - Success states
    /// Contrast: White 4.5:1 (AA) | Black 4.7:1 (AA)
    /// Usage: Success text, checkmarks, status badges
    static let emerald = Color(hex: "#10B981")
    
    // MARK: - Card Overlays (Environment-Aware)
    
    /// Subtle purple overlay for cards
    /// Light mode: 0.03 opacity | Dark mode: 0.05 opacity
    static func cardGradient(for colorScheme: ColorScheme) -> some ShapeStyle {
        let opacity = colorScheme == .light ? 0.03 : 0.05
        return RadialGradient(
            colors: [
                purple.opacity(opacity),
                darkPurple.opacity(opacity * 0.5),
                Color.clear
            ],
            center: .center,
            startRadius: 50,
            endRadius: 200
        )
    }
    
    // MARK: - Icon Backgrounds
    
    /// Light purple background for icon-only buttons
    static let purpleIconBackground = purple.opacity(0.1)
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var selectedTab = 0
    
    init() {
        print("🖼️ [ContentView] Initializing ContentView")
    }
    
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
            } else {
                // Show loading state while not initialized
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
        .overlay {
            if !coordinator.isInitialized && coordinator.initializationError == nil && !coordinator.needsPermissions {
                LoadingOverlay()
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

// MARK: - Home Tab

// MARK: - Summary Quality Card

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppCoordinator.previewInstance())
    }
}
