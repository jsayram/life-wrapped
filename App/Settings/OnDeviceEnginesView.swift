import SwiftUI
import Summarization

struct OnDeviceEnginesView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var activeEngine: EngineTier?
    @State private var availableEngines: [EngineTier] = []
    @State private var isLoading = true
    @State private var showUnavailableAlert = false
    @State private var selectedUnavailableTier: EngineTier?
    
    var body: some View {
        List {
            Section {
                ForEach(EngineTier.privateTiers, id: \.self) { tier in
                    EngineSelectionRow(
                        tier: tier,
                        isActive: tier == activeEngine,
                        isAvailable: availableEngines.contains(tier)
                    ) {
                        selectEngine(tier)
                    }
                }
            } header: {
                Text("Select Engine")
            } footer: {
                Text("Tap an engine to activate it. All on-device engines process data locally for privacy.")
            }
        }
        .navigationTitle("On-Device Engines")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadEngineStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
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
        
        guard let summCoord = coordinator.summarizationCoordinator else { return }
        activeEngine = await summCoord.getActiveEngine()
        availableEngines = await summCoord.getAvailableEngines()
    }
    
    private func selectEngine(_ tier: EngineTier) {
        if tier == activeEngine { return }
        
        guard availableEngines.contains(tier) else {
            selectedUnavailableTier = tier
            showUnavailableAlert = true
            return
        }
        
        Task {
            guard let summCoord = coordinator.summarizationCoordinator else { return }
            await summCoord.setPreferredEngine(tier)
            await loadEngineStatus()
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            coordinator.showSuccess("Switched to \(tier.displayName)")
        }
    }
    
    private func unavailableMessage(for tier: EngineTier) -> String {
        switch tier {
        case .basic:
            return "Basic engine should always be available. Please restart the app."
        case .local:
            return "Download the local AI model to use on-device intelligence."
        case .apple:
            return "Apple Intelligence requires iOS 26+ and compatible hardware (A17 Pro / M1+)."
        case .external:
            return "Configure your API key to use external AI services."
        }
    }
}
