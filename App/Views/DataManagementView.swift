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
    @State private var isImporting = false
    @State private var exportFormat: ExportFormat = .json
    @State private var showShareSheet = false
    @State private var showFilePicker = false
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
                            title: "Local AI Model",
                            value: info.formattedLocalModelSize,
                            detail: nil
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
                
                // Import Section
                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import JSON Data")
                            
                            if isImporting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isImporting)
                } header: {
                    Text("Import")
                } footer: {
                    Text("Import data from a JSON export file. Use this to restore backups or load test data.")
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
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    await handleFileImport(result: result)
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
    
    private func exportData() {
        isExporting = true
        
        Task {
            do {
                if let dbManager = coordinator.getDatabaseManager() {
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
    
    private func handleFileImport(result: Result<[URL], Error>) async {
        isImporting = true
        
        defer {
            Task { @MainActor in
                isImporting = false
            }
        }
        
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                await MainActor.run {
                    coordinator.showError("Unable to access file")
                }
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let data = try Data(contentsOf: url)
            
            if let dbManager = coordinator.getDatabaseManager() {
                let importer = DataImporter(databaseManager: dbManager)
                let result = try await importer.importFromJSON(data: data)
                
                await MainActor.run {
                    if result.isSuccessful {
                        coordinator.showSuccess("✅ \(result.summary)")
                    } else if result.hasPartialSuccess {
                        coordinator.showError("⚠️ Partial import: \(result.summary)")
                    } else {
                        coordinator.showError("❌ Import failed: \(result.errors.first ?? "Unknown error")")
                    }
                }
                
                await loadStorageInfo()
            }
        } catch {
            await MainActor.run {
                coordinator.showError("Import failed: \(error.localizedDescription)")
            }
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

struct DataManagementView_Previews: PreviewProvider {
    static var previews: some View {
        DataManagementView()
            .environmentObject(AppCoordinator())
    }
}

