import SwiftUI
import Summarization


struct IntelligenceEngineView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var activeEngine: EngineTier?
    @State private var availableEngines: [EngineTier] = []
    @State private var isLoading = true
    @State private var showUnavailableAlert = false
    @State private var selectedUnavailableTier: EngineTier?
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading engines...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(EngineTier.privateTiers, id: \.self) { tier in
                    EngineRow(
                        tier: tier,
                        isActive: tier == activeEngine,
                        isAvailable: availableEngines.contains(tier)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectEngine(tier)
                    }
                    
                    if tier != EngineTier.privateTiers.last {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .task {
            await loadEngineStatus()
        }
        .onAppear {
            // Refresh engine status when view appears to catch changes
            Task {
                await loadEngineStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
            // Refresh when engine changes from any view
            Task {
                await loadEngineStatus()
            }
        }
        .alert("Engine Unavailable", isPresented: $showUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let tier = selectedUnavailableTier {
                Text(unavailableMessage(for: tier))
            }
        }
    }
    
    private func loadEngineStatus() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let summCoord = coordinator.summarizationCoordinator else {
            print("⚠️ [IntelligenceEngineView] No summarization coordinator available")
            return
        }
        
        // Get active engine
        activeEngine = await summCoord.getActiveEngine()
        
        // Get available engines
        availableEngines = await summCoord.getAvailableEngines()
    }
    
    private func selectEngine(_ tier: EngineTier) {
        // Check if already active
        if tier == activeEngine {
            return
        }
        
        // Check if available
        guard availableEngines.contains(tier) else {
            selectedUnavailableTier = tier
            showUnavailableAlert = true
            return
        }
        
        // Set preferred engine
        Task {
            guard let summCoord = coordinator.summarizationCoordinator else { return }
            
            await summCoord.setPreferredEngine(tier)
            await loadEngineStatus()  // Refresh UI
            
            // Notify other views to refresh
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            
            // Show success toast
            coordinator.showSuccess("Switched to \(tier.displayName)")
        }
    }
    
    private func unavailableMessage(for tier: EngineTier) -> String {
        switch tier {
        case .basic:
            return "Basic engine should always be available. Please restart the app."
        case .local:
            return "Local AI model needs to be downloaded. Go to Settings to download Phi-3.5."
        case .apple:
            return "Apple Intelligence requires iOS 18.1+ and compatible hardware. Your device or OS version doesn't support it yet."
        case .external:
            return "External API engine is not yet configured. You'll need to provide your own API key in a future update."
        }
    }
}

