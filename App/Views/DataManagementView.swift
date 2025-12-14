// =============================================================================
// DataManagementView — Export and storage management
// =============================================================================

import SwiftUI
import Storage

struct DataManagementView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    
    @State private var storageInfo: StorageInfo?
    @State private var isExporting = false
    @State private var exportFormat: ExportFormat = .json
    @State private var showShareSheet = false
    @State private var exportURL: URL?
    @State private var showDeleteConfirmation = false
    
    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case markdown = "Markdown"
        
        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .markdown: return "md"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                // Storage Usage Section
                Section {
                    if let info = storageInfo {
                        StorageUsageRow(
                            title: "Audio Recordings",
                            value: info.formattedAudioSize,
                            detail: "\(info.audioChunkCount) files"
                        )
                        
                        StorageUsageRow(
                            title: "Database",
                            value: info.formattedDatabaseSize,
                            detail: "\(info.summaryCount) summaries"
                        )
                        
                        StorageUsageRow(
                            title: "Total",
                            value: info.formattedTotalSize,
                            detail: nil,
                            isBold: true
                        )
                    } else {
                        HStack {
                            ProgressView()
                            Text("Loading storage info...")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Storage Usage")
                }
                
                // Export Section
                Section {
                    Picker("Export Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    
                    Button {
                        exportData()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Data")
                            
                            if isExporting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isExporting)
                } header: {
                    Text("Export")
                } footer: {
                    Text("Export your journal entries and summaries to share or back up.")
                }
                
                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Delete All Data")
                        }
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("This will permanently delete all recordings, transcriptions, and summaries.")
                }
            }
            .navigationTitle("Data Management")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadStorageInfo()
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteAllData()
                }
            } message: {
                Text("This action cannot be undone. All your recordings, transcriptions, and summaries will be permanently deleted.")
            }
        }
    }
    
    private func loadStorageInfo() async {
        do {
            if let dbManager = await coordinator.getDatabaseManager() {
                let exporter = DataExporter(databaseManager: dbManager)
                let info = try await exporter.getStorageInfo()
                await MainActor.run {
                    storageInfo = info
                }
            }
        } catch {
            print("❌ Failed to load storage info: \(error)")
        }
    }
    
    private func exportData() {
        isExporting = true
        
        Task {
            do {
                if let dbManager = await coordinator.getDatabaseManager() {
                    let exporter = DataExporter(databaseManager: dbManager)
                    
                    let filename = "lifewrapped-export-\(Date().timeIntervalSince1970).\(exportFormat.fileExtension)"
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                    
                    switch exportFormat {
                    case .json:
                        let data = try await exporter.exportToJSON()
                        try data.write(to: tempURL)
                    case .markdown:
                        let markdown = try await exporter.exportToMarkdown()
                        try markdown.write(to: tempURL, atomically: true, encoding: .utf8)
                    }
                    
                    await MainActor.run {
                        exportURL = tempURL
                        showShareSheet = true
                        isExporting = false
                        coordinator.showSuccess("Data exported successfully!")
                    }
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    coordinator.showError("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func deleteAllData() {
        Task {
            await coordinator.deleteAllData()
            await loadStorageInfo()
            coordinator.showSuccess("All data deleted")
        }
    }
}

// MARK: - Storage Usage Row

struct StorageUsageRow: View {
    let title: String
    let value: String
    let detail: String?
    var isBold: Bool = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(isBold ? .headline : .body)
                
                if let detail = detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(value)
                .font(isBold ? .headline : .body)
                .foregroundColor(isBold ? .primary : .secondary)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    DataManagementView()
        .environmentObject(AppCoordinator())
}
