import SwiftUI

struct DataSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showDataManagement = false
    @State private var storageUsed: String = "Calculating..."
    
    var body: some View {
        List {
            Section {
                NavigationLink(destination: HistoricalDataView()) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Historical Data")
                            Text("View and manage data by year")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.blue)
                    }
                }
            } header: {
                Text("Browse Data")
            } footer: {
                Text("The Overview tab always shows the current year. Use Historical Data to browse previous years.")
            }
            
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
                HStack {
                    Label("Storage Used", systemImage: "internaldrive")
                    Spacer()
                    Text(storageUsed)
                        .foregroundStyle(.secondary)
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
            await calculateStorage()
        }
    }
    
    private func calculateStorage() async {
        // Calculate total storage used by app
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        
        if let url = documentsURL {
            let size = directorySize(url: url)
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            storageUsed = formatter.string(fromByteCount: Int64(size))
        }
    }
    
    private func directorySize(url: URL) -> Int {
        let fileManager = FileManager.default
        var totalSize = 0
        
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += fileSize
                }
            }
        }
        
        return totalSize
    }
}

