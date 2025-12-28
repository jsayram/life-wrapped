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
    @State private var navigateToExternalAPI: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                // Recording Section
                Section {
                    NavigationLink(destination: RecordingSettingsView()) {
                        Label {
                            Text("Recording Chunks")
                        } icon: {
                            Image(systemName: "mic.fill")
                                .foregroundStyle(AppTheme.magenta)
                        }
                    }
                }
                
                // AI & Summaries Section
                Section {
                    NavigationLink(destination: AISettingsView()) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI & Summaries")
                                Text(activeEngineName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "brain")
                                .foregroundStyle(AppTheme.purple)
                        }
                    }
                } footer: {
                    Text("Configure how your recordings are summarized.")
                }
                
                // Statistics Section
                Section {
                    NavigationLink(destination: StatisticsView()) {
                        Label {
                            Text("Statistics")
                        } icon: {
                            Image(systemName: "chart.xyaxis.line")
                                .foregroundStyle(AppTheme.skyBlue)
                        }
                    }
                } footer: {
                    Text("View word clouds, charts, and statistical analysis.")
                }
                
                // Data Section
                Section {
                    NavigationLink(destination: DataSettingsView()) {
                        Label {
                            Text("Data")
                        } icon: {
                            Image(systemName: "externaldrive.fill")
                                .foregroundStyle(AppTheme.magenta)
                        }
                    }
                }
                
                // Privacy Policy Section
                Section {
                    NavigationLink(destination: PrivacySettingsView()) {
                        Label {
                            Text("Privacy Policy")
                        } icon: {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(AppTheme.darkPurple)
                        }
                    }
                }
                
                // About Section
                Section {
                    HStack {
                        Label {
                            Text("Version")
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(AppTheme.lightPurple)
                        }
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToExternalAPISettings"))) { _ in
                navigateToExternalAPI = true
            }
            .navigationDestination(isPresented: $navigateToExternalAPI) {
                ExternalAPISettingsView()
            }
        }
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
