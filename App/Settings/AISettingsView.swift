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
    @State private var selectedProvider: String = UserDefaults.standard.string(forKey: "externalAPIProvider") ?? "OpenAI"
    @State private var selectedModel: String = UserDefaults.standard.string(forKey: "externalAPIModel") ?? "gpt-4.1"
    @State private var apiKey: String = ""
    @State private var showAPIKeyField = false
    
    // API Key testing state
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess = false
    
    // Available models per provider
    private let openaiModels = [
        ("gpt-4.1", "GPT-4.1 (Recommended)"),
        ("gpt-4.1-mini", "GPT-4.1 Mini (Faster)"),
        ("gpt-4o", "GPT-4o"),
        ("gpt-4o-mini", "GPT-4o Mini"),
        ("gpt-3.5-turbo", "GPT-3.5 Turbo (Cheapest)")
    ]
    
    private let anthropicModels = [
        ("claude-sonnet-4-5", "Claude Sonnet 4.5 (Recommended)"),
        ("claude-haiku-4-5", "Claude Haiku 4.5 (Fastest)"),
        ("claude-opus-4-5", "Claude Opus 4.5 (Most Capable)"),
        ("claude-sonnet-4-20250514", "Claude Sonnet 4 (Legacy)"),
        ("claude-3-5-sonnet-20241022", "Claude 3.5 Sonnet (Legacy)")
    ]
    
    private var currentModels: [(String, String)] {
        selectedProvider == "OpenAI" ? openaiModels : anthropicModels
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
                    subtitle: "Quick word-based summaries",
                    detail: "Always available, works offline",
                    tier: .basic,
                    isSelected: activeEngine == .basic,
                    isAvailable: true,
                    onSelect: { selectEngine(.basic) }
                )
                
                // Smart (Local AI - Phi-3.5)
                SummaryQualityCard(
                    emoji: "🤖",
                    title: "Smart",
                    subtitle: coordinator.localModelDisplayName,
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
                    subtitle: "Apple Intelligence",
                    detail: availableEngines.contains(.apple) ? "On-device AI, works offline" : "Requires iOS 18.1+ and compatible device",
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
                        ? (hasValidAPIKey() ? "\(selectedProvider) • \(selectedModel)" : "OpenAI or Anthropic")
                        : "OpenAI or Anthropic",
                    detail: coordinator.storeManager.isSmartestAIUnlocked 
                        ? (hasValidAPIKey() ? "Best quality, requires internet" : "Tap to configure your API key")
                        : "Tap to unlock • \(coordinator.storeManager.smartestAIProduct?.displayPrice ?? "Purchase required")",
                    tier: .external,
                    isSelected: activeEngine == .external,
                    isAvailable: true,
                    onSelect: { selectEngine(.external) }
                )
            } header: {
                Text("Summary Quality")
            } footer: {
                Text("Choose how you want your audio summaries generated. Smartest requires purchase and your own API key.")
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
                    .onChange(of: selectedProvider) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "externalAPIProvider")
                        let defaultModel = newValue == "OpenAI" ? "gpt-4.1" : "claude-sonnet-4-5"
                        selectedModel = defaultModel
                        UserDefaults.standard.set(defaultModel, forKey: "externalAPIModel")
                        loadAPIKey()
                    }
                    
                    // Model Selection
                    Picker("Model", selection: $selectedModel) {
                        ForEach(currentModels, id: \.0) { model in
                            Text(model.1).tag(model.0)
                        }
                    }
                    .onChange(of: selectedModel) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "externalAPIModel")
                    }
                    
                    // API Key Input
                    if showAPIKeyField {
                        VStack(spacing: 8) {
                            HStack {
                                SecureField("API Key", text: $apiKey)
                                    .textContentType(.password)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .onChange(of: apiKey) { _, newValue in
                                        let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if normalized != newValue {
                                            apiKey = normalized
                                        }
                                        testResult = nil
                                    }
                                
                                Button("Test") {
                                    testAPIKey()
                                }
                                .buttonStyle(.bordered)
                                .disabled(apiKey.isEmpty || isTesting)
                                
                                Button("Save") {
                                    saveAPIKey()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(apiKey.isEmpty)
                            }
                            .modifier(WiggleModifier(wiggle: $wiggleAPIKeyField))
                            
                            // Instructional text
                            if !hasValidAPIKey() {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(.orange)
                                    Text("Save your API key to activate Smartest summaries")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            
                            if let result = testResult {
                                Label(result, systemImage: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(testSuccess ? .green : .red)
                            }
                        }
                    } else {
                        Button {
                            showAPIKeyField = true
                        } label: {
                            Label(hasValidAPIKey() ? "Change API Key" : "Add API Key", 
                                  systemImage: hasValidAPIKey() ? "pencil" : "key.fill")
                        }
                    }
                    
                    // Help link
                    Link(destination: URL(string: selectedProvider == "OpenAI" 
                        ? "https://platform.openai.com/api-keys" 
                        : "https://console.anthropic.com/settings/keys")!) {
                        Label("Get \(selectedProvider) API Key", systemImage: "arrow.up.right.square")
                            .font(.footnote)
                    }
                    
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
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
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
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(coordinator.localModelDisplayName)
                                .font(.subheadline)
                            Text("Not Downloaded • \(coordinator.expectedLocalModelSizeMB)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            downloadLocalModel()
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                                .font(.caption)
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
                Text("This will remove the \\(coordinator.expectedLocalModelSizeMB) model from your device. You can re-download it anytime.")
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
                showAPIKeyField = true
                
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
                onPurchase: {
                    Task {
                        let success = await coordinator.storeManager.purchaseSmartestAI()
                        if success {
                            showPurchaseSheet = false
                            coordinator.showSuccess("Smartest AI unlocked!")
                            // Now show the API configuration
                            activeEngine = .external
                            showingSmartestConfig = true
                            showAPIKeyField = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation {
                                    scrollProxy?.scrollTo("smartestConfig", anchor: .top)
                                }
                            }
                        }
                    }
                },
                onCancel: {
                    showPurchaseSheet = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        }
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
            coordinator.showError("Apple Intelligence requires iOS 18.1+ and compatible hardware")
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
            showAPIKeyField = true
            
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
        showAPIKeyField = false
    }
    
    private func saveAPIKey() {
        let keychainKey = selectedProvider == "OpenAI" ? "openai_api_key" : "anthropic_api_key"
        
        if KeychainHelper.save(key: keychainKey, value: apiKey) {
            UserDefaults.standard.set(selectedProvider, forKey: "externalAPIProvider")
            UserDefaults.standard.set(selectedModel, forKey: "externalAPIModel")
            showAPIKeyField = false
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
    
    private func testAPIKey() {
        isTesting = true
        testResult = nil
        
        Task {
            guard !apiKey.isEmpty else {
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
            
            let provider: ExternalAPIEngine.Provider = selectedProvider == "OpenAI" ? .openai : .anthropic
            let result = await summCoord.validateExternalAPIKey(apiKey, for: provider)
            
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
        showAPIKeyField = false
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
    let onPurchase: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
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
            .padding(.top, 16)
            
            Divider()
            
            // Features
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "sparkles", text: "Best quality AI summaries")
                FeatureRow(icon: "key.fill", text: "Use your own API keys (BYOK)")
                FeatureRow(icon: "arrow.clockwise", text: "One-time purchase, forever access")
                FeatureRow(icon: "key.fill", text: "Your API keys stay private")
            }
            .padding(.horizontal)
            
            Spacer()
            
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
                .padding(.bottom, 8)
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
