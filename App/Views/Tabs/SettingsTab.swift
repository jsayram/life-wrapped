import SwiftUI
import SharedModels
import Security
import Summarization

struct SettingsTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var activeEngineName: String = "Loading..."
    @State private var debugTapCount: Int = 0
    @State private var showDebugSection: Bool = false
    @State private var databasePath: String?
    @State private var navigateToAISettings: Bool = false
    @State private var fromYearWrap: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                // Main settings
                Section {
                    NavigationLink(destination: RecordingSettingsView()) {
                        SettingsRowLabel(icon: "mic", title: "Recording", value: chunkLabel)
                    }
                    NavigationLink(destination: AISettingsView()) {
                        SettingsRowLabel(icon: "sparkle", title: "AI & Summaries", value: activeEngineName)
                    }
                    NavigationLink(destination: StatisticsView()) {
                        SettingsRowLabel(icon: "chart.bar", title: "Statistics")
                    }
                    NavigationLink(destination: DataSettingsView()) {
                        SettingsRowLabel(icon: "cylinder", title: "Data", value: "Export, import")
                    }
                }

                // Purchases Section
                Section {
                    SettingsRowLabel(
                        icon: "cloud",
                        title: "Smartest",
                        value: coordinator.storeManager.isSmartestAIUnlocked
                            ? "Unlocked"
                            : (coordinator.storeManager.smartestAIProduct?.displayPrice ?? "Locked")
                    )

                    Button {
                        Task {
                            await coordinator.storeManager.restorePurchases()
                        }
                    } label: {
                        HStack {
                            SettingsRowLabel(icon: "arrow.clockwise", title: "Restore purchases")
                            if coordinator.storeManager.purchaseState == .restoring {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(coordinator.storeManager.purchaseState == .restoring)
                } header: {
                    Text("Purchases")
                }

                // About Section
                Section {
                    NavigationLink(destination: PrivacySettingsView()) {
                        SettingsRowLabel(icon: "shield", title: "Privacy policy")
                    }

                    SettingsRowLabel(icon: "info.circle", title: "Version", value: appVersion, monospacedValue: true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            debugTapCount += 1
                            if debugTapCount >= 5 {
                                showDebugSection = true
                                coordinator.showSuccess("Debug mode enabled")
                                debugTapCount = 0
                            }
                        }
                } header: {
                    Text("About")
                }
                
                // Debug Section (hidden by default)
                if showDebugSection {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Database Location")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let path = databasePath {
                                Text(path)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            } else {
                                Text("Loading...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        Button {
                            Task {
                                await coordinator.testSessionQueries()
                            }
                        } label: {
                            Label("Test Session Queries", systemImage: "testtube.2")
                        }
                        
                        Button(role: .destructive) {
                            showDebugSection = false
                        } label: {
                            Label("Hide Debug Section", systemImage: "eye.slash")
                        }
                    } header: {
                        Text("Debug")
                    }
                }
            }
            .themedScreen()
            .navigationTitle("Settings")
            .task {
                await loadActiveEngine()
                databasePath = await coordinator.getDatabasePath()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
                Task {
                    await loadActiveEngine()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToSmartestConfig"))) { _ in
                fromYearWrap = true
                navigateToAISettings = true
            }
            .navigationDestination(isPresented: $navigateToAISettings) {
                AISettingsView(fromYearWrap: fromYearWrap)
                    .onDisappear {
                        fromYearWrap = false
                    }
            }
        }
    }
    
    private var chunkLabel: String {
        let seconds = Int(UserDefaults.standard.autoChunkDuration)
        if seconds % 60 == 0 { return "\(seconds / 60) min parts" }
        return "\(seconds)s parts"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func loadActiveEngine() async {
        guard let summCoord = coordinator.summarizationCoordinator else {
            activeEngineName = "Not configured"
            return
        }
        
        let engine = await summCoord.getActiveEngine()
        activeEngineName = engine.displayName
    }
}

// MARK: - Settings Row

/// Settings row matching the graphite mockup: outline icon, title, optional trailing value.
struct SettingsRowLabel: View {
    let icon: String
    let title: String
    var value: String? = nil
    var monospacedValue: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(monospacedValue ? .system(.subheadline, design: .monospaced) : .subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}
