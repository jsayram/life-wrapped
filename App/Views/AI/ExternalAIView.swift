import SwiftUI
import Summarization


struct ExternalAIView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var activeEngine: EngineTier?
    @State private var availableEngines: [EngineTier] = []
    @State private var isLoading = true
    @State private var showConfigSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                EngineRow(
                    tier: .external,
                    isActive: activeEngine == .external,
                    isAvailable: availableEngines.contains(.external)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectEngine(.external)
                }
                
                Divider()
                    .padding(.leading, 48)
                
                // Configuration button
                Button {
                    showConfigSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.body)
                            .foregroundStyle(.orange)
                            .frame(width: 32, height: 32)
                        
                        Text("Configure API Keys")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .task {
            await loadEngineStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
            // Refresh when engine changes from any view
            Task {
                await loadEngineStatus()
            }
        }
        .sheet(isPresented: $showConfigSheet, onDismiss: {
            // Refresh engine status after config sheet dismisses
            Task {
                await loadEngineStatus()
            }
        }) {
            ExternalAPIConfigView()
                .environmentObject(coordinator)
        }
    }
    
    private func loadEngineStatus() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let summCoord = coordinator.summarizationCoordinator else { return }
        
        activeEngine = await summCoord.getActiveEngine()
        availableEngines = await summCoord.getAvailableEngines()
    }
    
    private func selectEngine(_ tier: EngineTier) {
        // Check if available
        guard availableEngines.contains(tier) else {
            showConfigSheet = true  // Open config if not available
            return
        }
        
        // Set preferred engine
        Task {
            guard let summCoord = coordinator.summarizationCoordinator else { return }
            
            await summCoord.setPreferredEngine(tier)
            await loadEngineStatus()
            
            // Notify other views to refresh
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            
            coordinator.showSuccess("Switched to \(tier.displayName)")
        }
    }
}

// MARK: - External API Configuration View

