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
                    systemImage: "bolt",
                    title: "Basic",
                    subtitle: "Functional, extractive only",
                    detail: "Always available • Works offline • Free",
                    tier: .basic,
                    isSelected: activeEngine == .basic,
                    isAvailable: true,
                    onSelect: { selectEngine(.basic) }
                )
                
                // Smart (on-device model, downloaded once)
                SummaryQualityCard(
                    systemImage: "cpu",
                    title: "Smart",
                    subtitle: "Decent quality • 100% private",
                    detail: coordinator.isLocalModelSupported ? localModelStatus : "Not available on this device",
                    tier: .local,
                    isSelected: activeEngine == .local,
                    isAvailable: coordinator.isLocalModelSupported && isLocalModelDownloaded,
                    onSelect: {
                        if coordinator.isLocalModelSupported {
                            selectEngine(.local)
                        }
                    }
                )
                
                // Smarter (Apple Intelligence)
                SummaryQualityCard(
                    systemImage: "sparkle",
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
                    systemImage: "cloud",
                    title: "Smartest",
                    subtitle: coordinator.storeManager.isSmartestAIUnlocked 
                        ? (hasValidAPIKey() ? "Best quality • \(selectedProvider)" : "Best quality • Cloud")
                        : "Best quality • Cloud",
                    detail: coordinator.storeManager.isSmartestAIUnlocked 
                        ? (hasValidAPIKey() ? "\(selectedModel) • Requires internet" : "Tap to configure your API key")
                        : "Tap to unlock • \(coordinator.storeManager.smartestAIProduct?.displayPrice ?? "Purchase required")",
                    tier: .external,
                    isSelected: activeEngine == .external,
                    isAvailable: true,
                    showsLock: !coordinator.storeManager.isSmartestAIUnlocked,
                    onSelect: { selectEngine(.external) }
                )
            } header: {
                Text("Summary quality")
            } footer: {
                Text("Basic, Smart and Smarter never leave your \(DeviceName.current). Smartest sends transcripts to the OpenAI or Anthropic model you choose, with your API key.")
            }
            
            // MARK: - Smartest Configuration (only show if purchased)
            if activeEngine == .external && coordinator.storeManager.isSmartestAIUnlocked {
                Section {
                    // Provider Selection
                    GraphiteSegmentedControl(
                        options: [
                            .init(value: "OpenAI", title: "OpenAI"),
                            .init(value: "Anthropic", title: "Anthropic")
                        ],
                        selection: $selectedProvider
                    )
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
                                Label("Saved", systemImage: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.accent)
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
                                        CenteredButtonLabel(title: "Test", systemImage: "bolt")
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
                            .foregroundStyle(AppTheme.onAccent)  // light fill in dark mode needs dark text
                            .disabled(apiKey.isEmpty || ExternalModelSettings.normalize(selectedModel).isEmpty)
                        }
                        .controlSize(.large)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        
                        if let result = testResult {
                            Label(result, systemImage: testSuccess ? "checkmark.circle" : "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(testSuccess ? AppTheme.accent : AppTheme.destructive)
                        } else if !hasValidAPIKey() {
                            Label("Save your API key to activate Smartest summaries", systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    
                    // Helper links side by side
                    HStack(spacing: 12) {
                        Link(destination: apiKeyURL) {
                            CenteredButtonLabel(title: "Get API key", systemImage: "key")
                                .frame(maxWidth: .infinity)
                        }
                        Link(destination: ExternalModelSettings.modelListURL(for: providerValue)) {
                            CenteredButtonLabel(title: "View models", systemImage: "list.bullet.rectangle")
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
                    Text("Smartest")
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
                        Image(systemName: "lock")
                            .scaledFont(size: 32)
                            .foregroundStyle(AppTheme.purple)
                        
                        Text("Purchase required")
                            .font(.headline)
                        
                        Text("Unlock Smartest AI to configure your OpenAI or Anthropic API keys.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button {
                            showPurchaseSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "lock.open")
                                Text(coordinator.storeManager.smartestAIProduct?.displayPrice != nil 
                                    ? "Unlock for \(coordinator.storeManager.smartestAIProduct!.displayPrice)" 
                                    : "Unlock Smartest AI")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(AppTheme.onAccent)
                            .background(
                                AppTheme.magenta
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } header: {
                    Text("Smartest")
                }
                .id("smartestConfig")
            }
            
            // MARK: - Local AI Model Management
            // Also shown when an earlier version downloaded the model on a device that can't run it,
            // so the space can be freed
            if activeEngine == .local || (!coordinator.isLocalModelSupported && isLocalModelDownloaded) {
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
                                .foregroundStyle(AppTheme.accent)
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
                                Text(coordinator.showsLocalModelReplacedNotice ? "New model, not downloaded yet" : "Not downloaded")
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
                                Image(systemName: "arrow.down.circle")
                                Text("Download model (\(coordinator.expectedLocalModelSizeMB))")
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(AppTheme.onAccent)  // light fill in dark mode needs dark text
                        .tint(AppTheme.accent)
                        .modifier(WiggleModifier(wiggle: $wiggleLocalAIButton))
                    }
                }
            } header: {
                Text("Local AI model")
            } footer: {
                if !coordinator.isLocalModelSupported {
                    Text("This device doesn't have enough memory to run Smart. Delete the model to free up space.")
                } else if coordinator.isDownloadingLocalModel {
                    Text("Download continues in the background. You'll receive a notification when complete.")
                } else if !isLocalModelDownloaded && coordinator.showsLocalModelReplacedNotice {
                    Text("Smart now uses \(coordinator.localModelDisplayName). The old model was removed to free up space. Download the new one to keep using Smart.")
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
        .themedScreen()
        .navigationTitle("AI & Summaries")
        .navigationBarTitleDisplayMode(.large)
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
                    localModelStatus = isLocalModelDownloaded
            ? await coordinator.localModelSizeFormatted()
            : notDownloadedStatus
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
            ProgressView(value: coordinator.localModelDownloadProgress)
                .progressViewStyle(.linear)
                .tint(AppTheme.accent)
            
            Text("Downloading \(coordinator.localModelDisplayName)... \(Int(coordinator.localModelDownloadProgress * 100))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            
            Text("You can leave this screen. We'll notify you when the download is complete.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                cancelDownload()
            } label: {
                Text("Cancel download")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppTheme.destructive)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 24)
                    .background(
                        Capsule()
                            .strokeBorder(AppTheme.destructive.opacity(0.5), lineWidth: 1)
                    )
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
    
    // MARK: - Helper Methods
    
    /// Smart row detail when the model isn't on the device
    private var notDownloadedStatus: String {
        coordinator.showsLocalModelReplacedNotice
            ? "New model available · \(coordinator.expectedLocalModelSizeMB)"
            : "Not downloaded · \(coordinator.expectedLocalModelSizeMB)"
    }
    
    private func loadEngineStatus() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let summCoord = coordinator.summarizationCoordinator else { return }
        activeEngine = await summCoord.getActiveEngine()
        availableEngines = await summCoord.getAvailableEngines()
        
        // Load local model status
        isLocalModelDownloaded = await coordinator.isLocalModelDownloaded()
        localModelStatus = isLocalModelDownloaded
            ? await coordinator.localModelSizeFormatted()
            : notDownloadedStatus
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
                    localModelStatus = notDownloadedStatus
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
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "cloud")
                        .scaledFont(size: 24, weight: .regular)
                        .foregroundStyle(AppTheme.onAccent)
                        .frame(width: 56, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.accent)
                        )
                        .accessibilityHidden(true)

                    Text("Unlock Smartest")
                        .scaledFont(size: 30, design: .serif)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("The most detailed summaries, using OpenAI or Anthropic with your own API key.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                // Features
                VStack(spacing: 0) {
                    FeatureRow(icon: "sparkle", text: "Best quality summaries and Year Wrap")
                    Divider().overlay(AppTheme.hairline)
                    FeatureRow(icon: "key", text: "Bring your own key, any current model")
                    Divider().overlay(AppTheme.hairline)
                    FeatureRow(icon: "arrow.clockwise", text: "One-time purchase")
                    Divider().overlay(AppTheme.hairline)
                    FeatureRow(icon: "lock", text: "Keys stay in your Keychain")
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.card)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                )

                // Purchase button
                Button(action: onPurchase) {
                    Group {
                        if isPurchasing {
                            ProgressView()
                                .tint(AppTheme.onAccent)
                        } else {
                            Text(price != nil ? "Unlock for \(price!)" : "Unlock Smartest")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(AppTheme.onAccent)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous)
                            .fill(AppTheme.accent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing)

                // Cancel button
                Button("Not now", action: onCancel)
                    .foregroundStyle(AppTheme.textPrimary)

                // Restore (App Store Guideline 3.1.1) and redeem
                HStack(spacing: 32) {
                    Button(action: onRestore) {
                        HStack(spacing: 4) {
                            if isRestoring {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text("Restore purchases")
                        }
                    }
                    Button("Redeem code", action: onRedeem)
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)

                // Purchase disclaimer
                Text("All sales are final. Refunds are handled by Apple under App Store policies.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
        .background(AppTheme.background.ignoresSafeArea())
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .scaledFont(size: 16, weight: .regular)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
