import SwiftUI
import Storage

struct DataSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showDataManagement = false
    @State private var storageInfo: StorageInfo?
    
    var body: some View {
        List {
            Section {
                Button {
                    showDataManagement = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Export & Backup")
                            Text("Export your data or create backups")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.green)
                    }
                }
                .foregroundStyle(.primary)
            } header: {
                Text("Data Management")
            }
            
            Section {
                if let info = storageInfo {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Audio Recordings")
                                .font(.body)
                            Text("\(info.audioChunkCount) files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(info.formattedAudioSize)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Database")
                                .font(.body)
                            Text("\(info.summaryCount) summaries")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(info.formattedDatabaseSize)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Local AI Model")
                                .font(.body)
                        }
                        Spacer()
                        Text(info.formattedLocalModelSize)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Total")
                            .font(.headline)
                        Spacer()
                        Text(info.formattedTotalSize)
                            .font(.headline)
                    }
                } else {
                    HStack {
                        ProgressView()
                        Text("Loading storage info...")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Includes recordings, transcripts, and AI models.")
            }
        }
        .navigationTitle("Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDataManagement) {
            DataManagementView()
                .environmentObject(coordinator)
        }
        .task {
            await loadStorageInfo()
        }
    }
    
    private func loadStorageInfo() async {
        do {
            if let dbManager = coordinator.getDatabaseManager() {
                let exporter = DataExporter(databaseManager: dbManager)
                // Get local model size from coordinator
                let modelSize = await coordinator.getLocalModelCoordinator()?.modelSizeBytes()
                let info = try await exporter.getStorageInfo(localModelSize: modelSize)
                await MainActor.run {
                    storageInfo = info
                }
            }
        } catch {
            print("❌ Failed to load storage info: \(error)")
        }
    }
}

