import SwiftUI
import Summarization

struct AISettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var activeEngine: EngineTier?
    @State private var availableEngines: [EngineTier] = []
    @State private var isLoading = true
    @State private var showingSmartestConfig = false
    @State private var wiggleAPIKeyField = false
    
    // Track if coming from Year Wrap flow
    var fromYearWrap: Bool = false
    
    // Local AI model state
    @State private var localModelStatus: String = "Checking..."
    @State private var isLocalModelDownloaded: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var wiggleLocalAIButton = false
    
    // Scroll proxy for programmatic scrolling
    @State private var scrollProxy: ScrollViewProxy?
    
    // Purchase state
    @State private var showPurchaseSheet = false
    
    // External API state
    @State private var selectedProvider: String = ExternalModelSettings.provider().rawValue
    @State private var selectedModel: String = ExternalModelSettings.model(for: ExternalModelSettings.provider())
    @FocusState private var modelFieldFocused: Bool
    @State private var revealAPIKey = false
    @State private var apiKey: String = ""
    
    // API Key testing state
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess = false
    
    private var providerValue: ExternalAPIEngine.Provider {
        selectedProvider == "OpenAI" ? .openai : .anthropic
    }
    
    private var apiKeyPlaceholder: String {
        providerValue == .openai ? "sk-..." : "sk-ant-..."
    }
    
    private var apiKeyURL: URL {
        URL(string: providerValue == .openai
            ? "https://platform.openai.com/api-keys"
            : "https://console.anthropic.com/settings/keys")!
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                // MARK: - Summary Quality Picker
                Section {
                // Basic (Quick word-based)
                SummaryQualityCard(
                    emoji: "⚡️",
                    title: "Basic",
                    subtitle: "Functional, extractive only",
                    detail: "Always available • Works offline • Free",
                    tier: .basic,
                    isSelected: activeEngine == .basic,
                    isAvailable: true,
                    onSelect: { selectEngine(.basic) }
                )
                
                // Smart (Local AI - Phi-3.5)
                SummaryQualityCard(
                    emoji: "🤖",
                    title: "Smart",
                    subtitle: "Decent quality • 100% private",
                    detail: localModelStatus,
                    tier: .local,
                    isSelected: activeEngine == .local,
                    isAvailable: isLocalModelDownloaded,
                    onSelect: { selectEngine(.local) }
                )
                
                // Smarter (Apple Intelligence)
                SummaryQualityCard(
                    emoji: "🧠",
                    title: "Smarter",
                    subtitle: "Good quality • 100% private • Free",
                    detail: availableEngines.contains(.apple) ? "Apple Intelligence • On-device" : "Needs Apple Intelligence turned on (iOS 26+)",
                    tier: .apple,
                    isSelected: activeEngine == .apple,
                    isAvailable: availableEngines.contains(.apple),
                    onSelect: { selectEngine(.apple) }
                )
                
                // Smartest (External API) - Requires Purchase
                SummaryQualityCard(
                    emoji: "✨",
                    title: coordinator.storeManager.isSmartestAIUnlocked ? "Smartest" : "Smartest 🔒",
                    subtitle: coordinator.storeManager.isSmartestAIUnlocked 
                        ? (hasValidAPIKey() ? "Best quality • \(selectedProvider)" : "Best quality • Cloud")
                        : "Best quality • Cloud",
                    detail: coordinator.storeManager.isSmartestAIUnlocked 
                        ? (hasValidAPIKey() ? "\(selectedModel) • Requires internet" : "Tap to configure your API key")
                        : "Tap to unlock • \(coordinator.storeManager.smartestAIProduct?.displayPrice ?? "Purchase required")",
                    tier: .external,
                    isSelected: activeEngine == .external,
                    isAvailable: true,
                    onSelect: { selectEngine(.external) }
                )
            } header: {
                Text("Summary Quality")
            } footer: {
                Text("Higher tiers provide better understanding, nuance, and JSON formatting. Basic and Smart work fully offline. Smartest uses the OpenAI or Anthropic model you choose, with your API key.")
            }
            
            // MARK: - Smartest Configuration (only show if purchased)
            if activeEngine == .external && coordinator.storeManager.isSmartestAIUnlocked {
                Section {
                    // Provider Selection
                    Picker("Provider", selection: $selectedProvider) {
                        Text("OpenAI").tag("OpenAI")
                        Text("Anthropic").tag("Anthropic")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedProvider) { _, _ in
                        ExternalModelSettings.setProvider(providerValue)
                        // Each provider keeps its own model, so switching back restores it
                        selectedModel = ExternalModelSettings.model(for: providerValue)
                        testResult = nil
                        revealAPIKey = false
                        loadAPIKey()
                    }
                    
                    // API Key
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("API Key")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if hasValidAPIKey() {
                                Label("Saved", systemImage: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        HStack(spacing: 8) {
                            Group {
                                if revealAPIKey {
                                    TextField(apiKeyPlaceholder, text: $apiKey)
                                } else {
                                    SecureField(apiKeyPlaceholder, text: $apiKey)
                                }
                            }
                            .font(.body.monospaced())
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: apiKey) { _, newValue in
                                let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                if normalized != newValue {
                                    apiKey = normalized
                                }
                                testResult = nil
                            }
                            
                            Button {
                                revealAPIKey.toggle()
                            } label: {
                                Image(systemName: revealAPIKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(revealAPIKey ? "Hide API key" : "Show API key")
                        }
                        .modifier(WiggleModifier(wiggle: $wiggleAPIKeyField))
                    }
                    
                    // Model ID (free text so any current model can be used)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Model ID")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField(ExternalModelSettings.placeholder(for: providerValue), text: $selectedModel)
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .submitLabel(.done)
                            .focused($modelFieldFocused)
                            .onSubmit { saveModel() }
                            .onChange(of: selectedModel) { _, _ in
                                testResult = nil
                            }
                    }
                    .onChange(of: modelFieldFocused) { _, focused in
                        if !focused { saveModel() }
                    }
                    
                    // Actions: Test and Save side by side
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Button {
                                testAPIKey()
                            } label: {
                                Group {
                                    if isTesting {
                                        HStack(spacing: 6) {
                                            ProgressView()
                                            Text("Testing")
                                        }
                                    } else {
                                        CenteredButtonLabel(title: "Test", systemImage: "bolt.horizontal.circle")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isTesting || apiKey.isEmpty || ExternalModelSettings.normalize(selectedModel).isEmpty)
                            
                            Button {
                                saveAPIKey()
                            } label: {
                                CenteredButtonLabel(title: "Save", systemImage: "checkmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(apiKey.isEmpty || ExternalModelSettings.normalize(selectedModel).isEmpty)
                        }
                        .controlSize(.large)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        
                        if let result = testResult {
                            Label(result, systemImage: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(testSuccess ? .green : .red)
                        } else if !hasValidAPIKey() {
                            Label("Save your API key to activate Smartest summaries", systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    // Helper links side by side
                    HStack(spacing: 12) {
                        Link(destination: apiKeyURL) {
                            CenteredButtonLabel(title: "Get API Key", systemImage: "key")
                                .frame(maxWidth: .infinity)
                        }
                        Link(destination: ExternalModelSettings.modelListURL(for: providerValue)) {
                            CenteredButtonLabel(title: "View Models", systemImage: "list.bullet.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.footnote)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    
                    // Remove key
                    if hasValidAPIKey() {
                        Button(role: .destructive) {
                            clearAPIKey()
                        } label: {
                            Label("Remove API Key", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Smartest Configuration")
                } footer: {
                    if hasValidAPIKey() {
                        Text("Your API key connects to \(selectedProvider == "OpenAI" ? "api.openai.com" : "api.anthropic.com"). Keys are stored securely and never shared.")
                    } else {
                        Text("Add your own OpenAI or Anthropic API key to unlock the Smartest summaries. Keys are stored securely in your device's Keychain.")
                    }
                }
                .id("smartestConfig")
            }
            
            // MARK: - Smartest Purchase Prompt (show if selected but not purchased)
            if activeEngine == .external && !coordinator.storeManager.isSmartestAIUnlocked {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(AppTheme.purple)
                        
                        Text("Purchase Required")
                            .font(.headline)
                        
                        Text("Unlock Smartest AI to configure your OpenAI or Anthropic API keys.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button {
                            showPurchaseSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "lock.open.fill")
                                Text(coordinator.storeManager.smartestAIProduct?.displayPrice != nil 
                                    ? "Unlock for \(coordinator.storeManager.smartestAIProduct!.displayPrice)" 
                                    : "Unlock Smartest AI")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                LinearGradient(
                                    colors: [AppTheme.magenta, AppTheme.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } header: {
                    Text("Smartest Configuration")
                }
                .id("smartestConfig")
            }
            
            // MARK: - Local AI Model Management
            if activeEngine == .local {
                Section {
                    if coordinator.isDownloadingLocalModel {
                        downloadingModelView
                    } else if isLocalModelDownloaded {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(coordinator.localModelDisplayName)
                                .font(.subheadline)
                            Text(localModelStatus)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .modifier(WiggleModifier(wiggle: $wiggleLocalAIButton))
                    }
                } else {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(coordinator.localModelDisplayName)
                                    .font(.subheadline)
                                Text("Not Downloaded")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        
                        // Download size info
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text("Size: \(coordinator.expectedLocalModelSizeMB) • Wi-Fi recommended")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Explicit download button with size
                        Button {
                            downloadLocalModel()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Download Model (\(coordinator.expectedLocalModelSizeMB))")
                            }
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .modifier(WiggleModifier(wiggle: $wiggleLocalAIButton))
                    }
                }
            } header: {
                Text("Local AI Model")
            } footer: {
                if coordinator.isDownloadingLocalModel {
                    Text("Download continues in the background. You'll receive a notification when complete.")
                } else if !isLocalModelDownloaded {
                    Text("Download the local AI model to enable on-device summarization. It runs entirely on your device for maximum privacy.")
                } else {
                    Text("The local AI model enables on-device summarization. It runs entirely on your device for maximum privacy.")
                }
            }
            .alert("Delete Local AI Model?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteLocalModel()
                }
            } message: {
                Text("This will remove the \(coordinator.expectedLocalModelSizeMB) model from your device. You can re-download it anytime.")
            }
            .id("localAIConfig")
            } // End of if activeEngine == .local
        }
        .navigationTitle("AI & Summaries")
        .task {
            await loadEngineStatus()
            loadAPIKey()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
            Task {
                await loadEngineStatus()
            }
        }
        .onAppear {
            // If coming from Year Wrap, expand Smartest section and scroll to it
            if fromYearWrap {
                activeEngine = .external
                showingSmartestConfig = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        scrollProxy?.scrollTo("smartestConfig", anchor: .top)
                    }
                }
            }
        }
        .onChange(of: coordinator.isDownloadingLocalModel) { wasDownloading, isDownloading in
            // Refresh model status when download completes
            if wasDownloading && !isDownloading {
                Task {
                    isLocalModelDownloaded = await coordinator.isLocalModelDownloaded()
                    localModelStatus = await coordinator.localModelSizeFormatted()
                }
            }
        }
        .onAppear {
            // Store proxy for scrolling
            scrollProxy = proxy
        }
        .sheet(isPresented: $showPurchaseSheet) {
            SmartestPurchaseSheet(
                price: coordinator.storeManager.smartestAIProduct?.displayPrice,
                isPurchasing: coordinator.storeManager.purchaseState == .purchasing,
                isRestoring: coordinator.storeManager.purchaseState == .restoring,
                onPurchase: {
                    Task {
                        let success = await coordinator.storeManager.purchaseSmartestAI()
                        if success {
                            showPurchaseSheet = false
                            coordinator.showSuccess("Smartest AI unlocked!")
                            // Now show the API configuration
                            activeEngine = .external
                            showingSmartestConfig = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation {
                                    scrollProxy?.scrollTo("smartestConfig", anchor: .top)
                                }
                            }
                        }
                    }
                },
                onRestore: {
                    Task {
                        await coordinator.storeManager.restorePurchases()
                        if coordinator.storeManager.isSmartestAIUnlocked {
                            showPurchaseSheet = false
                            coordinator.showSuccess("Purchases restored!")
                        }
                    }
                },
                onRedeem: {
                    Task {
                        await coordinator.storeManager.presentRedeemCode()
                        if coordinator.storeManager.isSmartestAIUnlocked {
                            showPurchaseSheet = false
                            coordinator.showSuccess("Code redeemed!")
                        }
                    }
                },
                onCancel: {
                    showPurchaseSheet = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        }
    }
    
    // MARK: - Subviews
    
    /// View shown while model is downloading - extracted to reduce body complexity
    @ViewBuilder
    private var downloadingModelView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Downloading \(coordinator.localModelDisplayName)...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("You can leave this screen. We'll notify you when the download is complete.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                cancelDownload()
            } label: {
                Text("Cancel Download")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.red)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 24)
                    .background(
                        Capsule()
                            .strokeBorder(Color.red.opacity(0.5), lineWidth: 1)
                    )
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
    
    // MARK: - Helper Methods
    
    private func loadEngineStatus() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let summCoord = coordinator.summarizationCoordinator else { return }
        activeEngine = await summCoord.getActiveEngine()
        availableEngines = await summCoord.getAvailableEngines()
        
        // Load local model status
        isLocalModelDownloaded = await coordinator.isLocalModelDownloaded()
        localModelStatus = await coordinator.localModelSizeFormatted()
    }
    
    private func downloadLocalModel() {
        // Use coordinator's background download method
        // Download state persists in coordinator even if view navigates away
        coordinator.startLocalModelDownload()
    }
    
    private func cancelDownload() {
        coordinator.getLocalModelCoordinator()?.cancelDownload()
    }
    
    private func deleteLocalModel() {
        Task {
            do {
                try await coordinator.deleteLocalModel()
                await MainActor.run {
                    isLocalModelDownloaded = false
                    localModelStatus = "Not Downloaded"
                }
                // Refresh status
                await loadEngineStatus()
            } catch {
                coordinator.showError("Delete failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func selectEngine(_ tier: EngineTier) {
        // For Local AI without model, show download section with wiggle animation
        if tier == .local {
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            
            // Update activeEngine immediately so section appears right away
            activeEngine = .local
            
            // Persist engine preference in background (without triggering refresh)
            Task {
                guard let summCoord = coordinator.summarizationCoordinator else { return }
                await summCoord.setPreferredEngine(tier)
            }
            
            // Scroll to the section after a brief delay to ensure it's rendered
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    scrollProxy?.scrollTo("localAIConfig", anchor: .top)
                }
            }
            
            // If model not downloaded, trigger wiggle animation on button
            if !isLocalModelDownloaded {
                withAnimation(.default) {
                    wiggleLocalAIButton = true
                }
                
                // Reset wiggle after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    wiggleLocalAIButton = false
                }
            }
            
            return
        }
        
        if tier == .apple && !availableEngines.contains(.apple) {
            coordinator.showError("Apple Intelligence isn't available. It needs iOS 26 or later on a supported device, with Apple Intelligence turned on in Settings.")
            return
        }
        
        // If selecting Smartest, check if purchase is required
        if tier == .external && !coordinator.storeManager.isSmartestAIUnlocked {
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            
            // Set activeEngine so the purchase prompt section appears
            activeEngine = .external
            
            // Show purchase sheet
            showPurchaseSheet = true
            
            // Scroll to the section
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    scrollProxy?.scrollTo("smartestConfig", anchor: .top)
                }
            }
            return
        }
        
        // If selecting Smartest without API key, show config section with feedback
        if tier == .external && !hasValidAPIKey() {
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            
            // Update activeEngine immediately so section appears right away
            activeEngine = .external
            
            // Show config and trigger wiggle animation
            showingSmartestConfig = true
            
            // Scroll to the section after a brief delay to ensure it's rendered
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    scrollProxy?.scrollTo("smartestConfig", anchor: .top)
                }
            }
            
            // Trigger wiggle animation
            withAnimation(.default) {
                wiggleAPIKeyField = true
            }
            
            // Reset wiggle after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                wiggleAPIKeyField = false
            }
            
            return
        }
        
        Task {
            guard let summCoord = coordinator.summarizationCoordinator else { return }
            await summCoord.setPreferredEngine(tier)
            await loadEngineStatus()
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            coordinator.showSuccess("Switched to \(tierDisplayName(tier))")
        }
    }
    
    private func tierDisplayName(_ tier: EngineTier) -> String {
        switch tier {
        case .basic: return "Basic"
        case .local: return "Smart"
        case .apple: return "Smarter"
        case .external: return "Smartest"
        }
    }
    
    private func hasValidAPIKey() -> Bool {
        let key = selectedProvider == "OpenAI" 
            ? KeychainHelper.load(key: "openai_api_key")
            : KeychainHelper.load(key: "anthropic_api_key")
        return key != nil && !key!.isEmpty
    }
    
    private func loadAPIKey() {
        let keychainKey = selectedProvider == "OpenAI" ? "openai_api_key" : "anthropic_api_key"
        apiKey = KeychainHelper.load(key: keychainKey) ?? ""
    }
    
    private func saveAPIKey() {
        let keychainKey = selectedProvider == "OpenAI" ? "openai_api_key" : "anthropic_api_key"
        
        if KeychainHelper.save(key: keychainKey, value: apiKey) {
            ExternalModelSettings.setProvider(providerValue)
            saveModel()
            showingSmartestConfig = false
            
            // Now that we have a valid key, switch to Smartest engine
            Task {
                guard let summCoord = coordinator.summarizationCoordinator else { return }
                await summCoord.setPreferredEngine(.external)
                await loadEngineStatus()
                NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
                coordinator.showSuccess("API key saved - Switched to Smartest")
            }
        } else {
            coordinator.showError("Failed to save API key")
        }
    }
    
    /// Saves the typed model ID. A blank field falls back to the provider default.
    private func saveModel() {
        ExternalModelSettings.setModel(selectedModel, for: providerValue)
        selectedModel = ExternalModelSettings.model(for: providerValue)
    }
    
    private func testAPIKey() {
        saveModel()
        isTesting = true
        testResult = nil
        let keychainKey = selectedProvider == "OpenAI" ? "openai_api_key" : "anthropic_api_key"
        let keyToTest = apiKey.isEmpty ? (KeychainHelper.load(key: keychainKey) ?? "") : apiKey
        let modelToTest = selectedModel
        
        Task {
            guard !keyToTest.isEmpty else {
                await MainActor.run {
                    testSuccess = false
                    testResult = "Please enter an API key"
                    isTesting = false
                }
                return
            }
            
            guard let summCoord = coordinator.summarizationCoordinator else {
                await MainActor.run {
                    testSuccess = false
                    testResult = "Summarization not initialized"
                    isTesting = false
                }
                return
            }
            
            let result = await summCoord.validateExternalAPIKey(keyToTest, for: providerValue, model: modelToTest)
            
            await MainActor.run {
                testSuccess = result.isValid
                testResult = result.message
                isTesting = false
            }
        }
    }
    
    private func clearAPIKey() {
        let keychainKey = selectedProvider == "OpenAI" ? "openai_api_key" : "anthropic_api_key"
        KeychainHelper.delete(key: keychainKey)
        apiKey = ""
        showingSmartestConfig = false
        
        if activeEngine == .external {
            selectEngine(.basic)
        }
        
        coordinator.showSuccess("API key removed")
        
        Task {
            await loadEngineStatus()
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
        }
    }
}

// MARK: - Smartest Purchase Sheet

struct SmartestPurchaseSheet: View {
    let price: String?
    let isPurchasing: Bool
    let isRestoring: Bool
    let onPurchase: () -> Void
    let onRestore: () -> Void
    let onRedeem: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.magenta, AppTheme.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Unlock Smartest AI")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Get the highest quality summaries with OpenAI or Anthropic")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            
            Divider()
            
            // Features
            VStack(alignment: .leading, spacing: 10) {
                FeatureRow(icon: "sparkles", text: "Best quality AI summaries")
                FeatureRow(icon: "key.fill", text: "Use your own API keys (BYOK)")
                FeatureRow(icon: "arrow.clockwise", text: "One-time purchase, forever access")
                FeatureRow(icon: "key.fill", text: "Your API keys stay private")
            }
            .padding(.horizontal)
            
            // Purchase disclaimer
            Text("All sales are final. Refund requests are handled by Apple per their App Store policies.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Purchase button
            Button(action: onPurchase) {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "lock.open.fill")
                        Text(price != nil ? "Unlock for \(price!)" : "Unlock Smartest AI")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [AppTheme.magenta, AppTheme.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isPurchasing)
            .padding(.horizontal)
            
            // Cancel button
            Button("Not Now", action: onCancel)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            
            // Restore Purchases button (App Store Guideline 3.1.1)
            Button(action: onRestore) {
                HStack(spacing: 4) {
                    if isRestoring {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text("Restore Purchases")
                }
            }
            .foregroundStyle(.secondary)
            .font(.footnote)
            
            // Redeem Code button
            Button(action: onRedeem) {
                Text("Redeem Code")
            }
            .foregroundStyle(.secondary)
            .font(.footnote)
            .padding(.bottom, 16)
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.purple)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Centered Button Label

/// Icon and text centered together. `Label` inside a List aligns its icon to a
/// column, which pushes the title off center in full-width buttons.
private struct CenteredButtonLabel: View {
    let title: String
    let systemImage: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .lineLimit(1)
    }
}
