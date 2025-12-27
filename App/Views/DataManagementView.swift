// =============================================================================
// DataManagementView — Export and storage management
// =============================================================================

import SwiftUI
import Storage

struct DataManagementView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportFormat: ExportFormat = .json
    @State private var showShareSheet = false
    @State private var showFilePicker = false
    @State private var exportURL: URL?
    @State private var showDeleteConfirmation = false
    @State private var deleteStats: (chunks: Int, transcripts: Int, summaries: Int, modelSize: String)?
    @State private var importProgress: (current: Int, total: Int)?
    @State private var importErrors: [(id: String, message: String)] = []
    @State private var showImportErrorSheet = false
    @State private var yearlyData: [(year: Int, sessionCount: Int, wordCount: Int, duration: TimeInterval)] = []
    
    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case markdown = "Markdown"
        case pdf = "PDF"
        
        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .markdown: return "md"
            case .pdf: return "pdf"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                // Yearly Data Section
                if !yearlyData.isEmpty {
                    Section {
                        ForEach(yearlyData, id: \.year) { yearData in
                            VStack(alignment: .leading, spacing: 12) {
                                // Year header with stats
                                HStack {
                                    Text(String(yearData.year))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(yearData.sessionCount) sessions")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(yearData.wordCount.formatted()) words")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                // Export buttons row
                                HStack(spacing: 8) {
                                    Button {
                                        exportData(year: yearData.year, format: .json)
                                    } label: {
                                        Label("JSON", systemImage: "doc.text")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isExporting)
                                    
                                    Button {
                                        exportData(year: yearData.year, format: .markdown)
                                    } label: {
                                        Label("Markdown", systemImage: "doc.plaintext")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isExporting)
                                    
                                    Button {
                                        exportData(year: yearData.year, format: .pdf)
                                    } label: {
                                        Label("PDF", systemImage: "doc.richtext")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isExporting)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    } header: {
                        Text("Export by Year")
                    } footer: {
                        Text("Export data for specific years. Choose your preferred format.")
                    }
                }
                
                // Export All All Section
                Section {
                    Picker("Export Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .onChange(of: exportFormat) { _, newValue in
                        UserDefaults.standard.lastExportFormat = newValue.rawValue
                    }
                    
                    if exportFormat == .pdf {
                        Text("PDF exports include summaries only, not full transcripts.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        exportData(year: nil, format: exportFormat)
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export All Data")
                            
                            if isExporting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isExporting)
                } header: {
                    Text("Export All")
                } footer: {
                    Text("Export all your journal entries and summaries across all years.")
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
                    
                    if let progress = importProgress {
                        HStack {
                            ProgressView(value: Double(progress.current), total: Double(progress.total))
                            Text("Processing item \(progress.current) of \(progress.total)...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Import")
                } footer: {
                    Text("Import data from a JSON export file. Use this to restore backups or load test data.")
                }
                
                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        Task {
                            // Load delete stats before showing confirmation
                            if let stats = await coordinator.getDataCoordinator()?.getDeleteStats() {
                                let modelSize = await coordinator.getLocalModelCoordinator()?.localModelSizeFormatted() ?? "Not Downloaded"
                                deleteStats = (
                                    chunks: stats.chunks,
                                    transcripts: stats.transcripts,
                                    summaries: stats.summaries,
                                    modelSize: modelSize
                                )
                            }
                            showDeleteConfirmation = true
                        }
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
                await loadYearlyData()
            }
            .onAppear {
                // Load saved export format
                if let savedFormat = UserDefaults.standard.lastExportFormat,
                   let format = ExportFormat(rawValue: savedFormat) {
                    exportFormat = format
                }
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
            .sheet(isPresented: $showImportErrorSheet) {
                NavigationView {
                    List {
                        if !importErrors.filter({ $0.message.contains("Already exists") }).isEmpty {
                            Section("Skipped (Duplicates)") {
                                ForEach(importErrors.filter { $0.message.contains("Already exists") }, id: \.id) { error in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(String(error.id.prefix(8)) + "...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(error.message)
                                            .font(.body)
                                    }
                                }
                            }
                        }
                        
                        if !importErrors.filter({ !$0.message.contains("Already exists") }).isEmpty {
                            Section("Errors") {
                                ForEach(importErrors.filter { !$0.message.contains("Already exists") }, id: \.id) { error in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(String(error.id.prefix(8)) + "...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(error.message)
                                            .font(.body)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Import Details")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Copy All") {
                                let allErrors = importErrors.map { "\($0.id): \($0.message)" }.joined(separator: "\n")
                                UIPasteboard.general.string = allErrors
                            }
                        }
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Done") {
                                showImportErrorSheet = false
                            }
                        }
                    }
                }
            }
            .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteAllData()
                }
            } message: {
                if let stats = deleteStats {
                    Text("This will permanently delete:\n\n• \(stats.chunks) recordings\n• \(stats.transcripts) transcripts\n• \(stats.summaries) summaries\n• API keys (OpenAI/Anthropic)\n• Local AI model (\(stats.modelSize))\n\nThis action cannot be undone.")
                } else {
                    Text("This action cannot be undone. All your recordings, transcriptions, and summaries will be permanently deleted.")
                }
            }
        }
    }
    
    private func loadYearlyData() async {
        do {
            if let dataCoordinator = coordinator.getDataCoordinator() {
                let data = try await dataCoordinator.fetchYearlyData()
                await MainActor.run {
                    yearlyData = data
                }
            }
        } catch {
            print("❌ Failed to load yearly data: \(error)")
        }
    }
    
    private func exportData(year: Int?, format: ExportFormat) {
        isExporting = true
        
        Task {
            do {
                if let dbManager = coordinator.getDatabaseManager() {
                    let exporter = DataExporter(databaseManager: dbManager)
                    
                    let yearSuffix = year.map { "_\($0)" } ?? "_All"
                    let filename = "LifeWrapped_Export\(yearSuffix).\(format.fileExtension)"
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                    
                    switch format {
                    case .json:
                        let data = try await exporter.exportToJSON(year: year)
                        try data.write(to: tempURL)
                    case .markdown:
                        let markdown = try await exporter.exportToMarkdown(year: year)
                        try markdown.write(to: tempURL, atomically: true, encoding: .utf8)
                    case .pdf:
                        let pdfData = try await exporter.exportToPDF(year: year)
                        try pdfData.write(to: tempURL)
                    }
                    
                    await MainActor.run {
                        exportURL = tempURL
                        showShareSheet = true
                        isExporting = false
                        let yearText = year.map { String($0) } ?? "all years"
                        coordinator.showSuccess("Data exported for \(yearText)!")
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
            coordinator.showSuccess("All data deleted")
        }
    }
    
    private func handleFileImport(result: Result<[URL], Error>) async {
        isImporting = true
        importProgress = nil
        importErrors = []
        
        defer {
            Task { @MainActor in
                isImporting = false
                importProgress = nil
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
                
                // Set up progress callback before Task
                await importer.setProgressCallback { @MainActor current, total in
                    importProgress = (current, total)
                }
                
                let result = try await importer.importFromJSON(data: data)
                
                await MainActor.run {
                    // Collect all errors and skipped items
                    let skipped = result.skippedItems.map { (id: $0.id, message: $0.reason) }
                    let failed = result.errors.map { (id: $0.id, message: $0.error) }
                    importErrors = skipped + failed
                    
                    // Show error sheet if there are any issues
                    if !importErrors.isEmpty {
                        showImportErrorSheet = true
                    }
                    
                    if result.isSuccessful {
                        coordinator.showSuccess("✅ \(result.summary)")
                    } else if result.hasPartialSuccess {
                        coordinator.showError("⚠️ Partial import: \(result.summary)")
                    } else {
                        coordinator.showError("❌ Import failed: \(result.errors.first?.error ?? "Unknown error")")
                    }
                }
            }
        } catch {
            await MainActor.run {
                coordinator.showError("Import failed: \(error.localizedDescription)")
            }
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

