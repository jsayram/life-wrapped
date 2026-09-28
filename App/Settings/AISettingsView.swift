import SwiftUI
import StoreKit
import Summarization

struct AISettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var activeEngine: EngineTier?
    /// Recordings summarized by an engine weaker than the selected one
    @State private var upgradeableSessionIds: [UUID] = []
    @State private var showUpgradeConfirmation = false
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
                // Key Sentences (extractive, internal tier .basic)
                SummaryQualityCard(
                    systemImage: "bolt",
                    title: "Key Sentences",
                    subtitle: "Picks out your most important sentences",
                    detail: "Free • Offline • Always available",
                    tier: .basic,
                    isSelected: activeEngine == .basic,
                    isAvailable: true,
                    onSelect: { selectEngine(.basic) }
                )
                
                // Offline AI (downloaded model, internal tier .local)
                SummaryQualityCard(
                    systemImage: "cpu",
                    title: "Offline AI",
                    subtitle: "A model you download • Free • Private",
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
                
                // Apple Intelligence (internal tier .apple)
                SummaryQualityCard(
                    systemImage: "sparkle",
                    title: "Apple Intelligence",
                    subtitle: "Built into your \(DeviceName.current) • Free • Private",
                    detail: availableEngines.contains(.apple) ? "Good quality • On-device" : "Needs Apple Intelligence turned on (iOS 26+)",
                    tier: .apple,
                    isSelected: activeEngine == .apple,
                    isAvailable: availableEngines.contains(.apple),
                    onSelect: { selectEngine(.apple) }
                )
                
                // Cloud AI (external API, internal tier .external) - requires purchase
                SummaryQualityCard(
                    systemImage: "cloud",
                    title: "Cloud AI",
                    subtitle: coordinator.storeManager.isSmartestAIUnlocked 
                        ? (hasValidAPIKey() ? "Best quality • \(selectedProvider)" : "Best quality • OpenAI or Anthropic")
                        : "Best quality • OpenAI or Anthropic",
                    detail: coordinator.storeManager.isSmartestAIUnlocked 
                        ? (hasValidAPIKey() ? "\(selectedModel) • Requires internet" : "Tap to configure your API key")
                        : "One-time \(coordinator.storeManager.smartestAIProduct?.displayPrice ?? "purchase") • Tap to unlock",
                    tier: .external,
                    isSelected: activeEngine == .external,
                    isAvailable: true,
                    showsLock: !coordinator.storeManager.isSmartestAIUnlocked,
                    onSelect: { selectEngine(.external) }
                )
            } header: {
                Text("Summary quality")
            } footer: {
                Text("Key Sentences, Offline AI and Apple Intelligence never leave your \(DeviceName.current). Cloud AI sends transcripts to the OpenAI or Anthropic model you choose, with your API key.")
            }

            // MARK: - Upgrade earlier summaries
            if let tier = activeEngine, tier != .basic, isEngineReady(tier),
               !upgradeableSessionIds.isEmpty || coordinator.summaryUpgradeProgress != nil {
                upgradeSection(tier: tier)
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
                            Label("Save your API key to activate Cloud AI summaries", systemImage: "exclamationmark.circle")
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
                    Text("Cloud AI")
                } footer: {
                    if hasValidAPIKey() {
                        Text("Your API key connects to \(selectedProvider == "OpenAI" ? "api.openai.com" : "api.anthropic.com"). Keys are stored securely and never shared.")
                    } else {
                        Text("Add your own OpenAI or Anthropic API key to unlock Cloud AI summaries. Keys are stored securely in your device's Keychain.")
                    }
                }
                .id("smartestConfig")
            }
            
            // MARK: - Smartest Purchase Prompt (show if selected but not purchased)
            if activeEngine == .external && !coordinator.storeManager.isSmartestAIUnlocked {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Pay once. Your data, your key.")
                                .font(.headline)
                            Text("A one-time purchase, not a subscription. Cloud AI then runs on your own OpenAI or Anthropic account, so you stay in control of where your transcripts go.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SmartestPoint(icon: "checkmark.seal", text: "One-time purchase. No subscription, nothing to renew.")
                            SmartestPoint(icon: "key", text: "Your own API key. You pick the provider and model, see what you use, and can revoke the key anytime.")
                            SmartestPoint(icon: "arrow.up.right", text: "Transcripts go straight from your \(DeviceName.current) to that provider, never through our servers.")
                            SmartestPoint(icon: "lock", text: "Your key is stored only in this \(DeviceName.current)'s Keychain.")
                        }

                        Button {
                            showPurchaseSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "lock.open")
                                Text(coordinator.storeManager.smartestAIProduct?.displayPrice != nil
                                    ? "Unlock for \(coordinator.storeManager.smartestAIProduct!.displayPrice), once"
                                    : "Unlock Cloud AI")
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                } header: {
                    Text("Cloud AI")
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
                Text("Offline AI model")
            } footer: {
                if !coordinator.isLocalModelSupported {
                    Text("This device doesn't have enough memory to run Offline AI. Delete the model to free up space.")
                } else if coordinator.isDownloadingLocalModel {
                    Text("You can use the rest of the app while it downloads. Keep Life Wrapped open until it finishes.")
                } else if !isLocalModelDownloaded && coordinator.showsLocalModelReplacedNotice {
                    Text("Offline AI now uses \(coordinator.localModelDisplayName). The old model was removed to free up space. Download the new one to keep using Offline AI.")
                } else if !isLocalModelDownloaded {
                    Text("Download the Offline AI model to make summaries on your \(DeviceName.current). It runs entirely on your device, and nothing is sent anywhere.")
                } else {
                    Text("The Offline AI model makes summaries on your \(DeviceName.current). It runs entirely on your device, and nothing is sent anywhere.")
                }
            }
            .alert("Delete the Offline AI model?", isPresented: $showDeleteConfirmation) {
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
        .readableMargins()
        .navigationTitle("AI & Summaries")
        .columnScreenTitleDisplayMode()
        .task {
            await loadEngineStatus()
            loadAPIKey()
            // Sent here to set up Cloud AI (from Year Wrap or right after unlocking). This runs after
            // the saved engine loads, which would otherwise replace the selection.
            if fromYearWrap && coordinator.storeManager.isSmartestAIUnlocked {
                selectEngine(.external)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
            Task {
                await loadEngineStatus()
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
        .sheet(isPresented: $showPurchaseSheet, onDismiss: {
            // Closed without buying: go back to the engine summaries really use, so a locked
            // Cloud AI never looks selected
            guard !coordinator.storeManager.isSmartestAIUnlocked else { return }
            Task {
                if let summCoord = coordinator.summarizationCoordinator {
                    activeEngine = await summCoord.getActiveEngine()
                }
            }
        }) {
            SmartestPurchaseSheet(
                store: coordinator.storeManager,
                onUnlocked: {
                    showPurchaseSheet = false
                    coordinator.showSuccess("Cloud AI unlocked")
                    // Opens the API key setup, or switches to Cloud AI when a key is already saved
                    selectEngine(.external)
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
            
            Text("You can leave this screen. Keep Life Wrapped open until the download finishes.")
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
        upgradeableSessionIds = await coordinator.upgradeableSessionIds(for: activeEngine ?? .basic)
        
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
        
        let previous = activeEngine
        Task {
            guard let summCoord = coordinator.summarizationCoordinator else { return }
            await summCoord.setPreferredEngine(tier)
            await loadEngineStatus()
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            if let previous, tier.isWeaker(than: previous.rawValue) {
                // Nothing already written gets rewritten by a weaker engine
                coordinator.showToast(Toast(style: .info, message: "Switched to \(tierDisplayName(tier)). Summaries written by \(tierDisplayName(previous)) stay as they are; new recordings use \(tierDisplayName(tier)).", duration: 5))
            } else {
                coordinator.showSuccess("Switched to \(tierDisplayName(tier))")
            }
        }
    }
    
    private func tierDisplayName(_ tier: EngineTier) -> String {
        switch tier {
        case .basic: return "Key Sentences"
        case .local: return "Offline AI"
        case .apple: return "Apple Intelligence"
        case .external: return "Cloud AI"
        }
    }
    
    /// Whether the engine can run right now, so an upgrade with it makes sense
    private func isEngineReady(_ tier: EngineTier) -> Bool {
        switch tier {
        case .basic: return true
        case .local: return isLocalModelDownloaded
        case .apple: return availableEngines.contains(.apple)
        case .external: return coordinator.storeManager.isSmartestAIUnlocked && hasValidAPIKey()
        }
    }

    /// Rewrite recordings summarized by a weaker engine with the selected one, on request
    @ViewBuilder
    private func upgradeSection(tier: EngineTier) -> some View {
        let count = upgradeableSessionIds.count
        let name = tierDisplayName(tier)
        Section {
            if let progress = coordinator.summaryUpgradeProgress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                    Text("Upgrading \(progress.done) of \(progress.total)")
                }
            } else {
                Button {
                    showUpgradeConfirmation = true
                } label: {
                    Label("Upgrade \(count) \(count == 1 ? "recording" : "recordings") with \(name)", systemImage: "arrow.up.circle")
                }
            }
        } header: {
            Text("Earlier summaries")
        } footer: {
            Text("\(count) \(count == 1 ? "recording was" : "recordings were") summarized by a weaker engine than \(name). Upgrading rewrites them with \(name). The earlier text is kept and can be restored from each recording.")
        }
        .alert("Upgrade \(count) \(count == 1 ? "recording" : "recordings")?", isPresented: $showUpgradeConfirmation) {
            Button("Upgrade with \(name)") {
                coordinator.upgradeSummaries(sessionIds: upgradeableSessionIds, with: tier)
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(upgradeWarning(tier))
        }
        .onChange(of: coordinator.summaryUpgradeProgress) { _, progress in
            if progress == nil {
                Task { upgradeableSessionIds = await coordinator.upgradeableSessionIds(for: tier) }
            }
        }
    }

    private func upgradeWarning(_ tier: EngineTier) -> String {
        switch tier {
        case .external:
            return "Sends the transcript of each recording to \(selectedProvider) with your API key. What it costs depends on your plan and the length of the recordings. Keep the app open."
        case .local:
            return "Runs the offline model once per recording. It can take a while; keep the app open and plugged in."
        case .apple:
            return "Runs Apple Intelligence once per recording on this \(DeviceName.current). Keep the app open."
        case .basic:
            return ""
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
                coordinator.showSuccess("API key saved - Switched to Cloud AI")
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

/// Buy, restore or redeem Cloud AI. The sheet runs all three itself and calls `onUnlocked` once
/// Cloud AI is unlocked by any of them, including an Ask to Buy approval that lands while it's open.
struct SmartestPurchaseSheet: View {
    @ObservedObject var store: StoreManager
    let onUnlocked: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.purchase) private var purchase
    @State private var showRedeemSheet = false
    
    private var price: String? { store.smartestAIProduct?.displayPrice }
    private var isPurchasing: Bool { store.purchaseState == .purchasing }
    private var isRestoring: Bool { store.purchaseState == .restoring }
    
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

                    Text("Unlock Cloud AI")
                        .scaledFont(size: 30, design: .serif)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Pay once for the most detailed summaries, using your own OpenAI or Anthropic API key. You stay in control of your data.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                // Features
                VStack(spacing: 0) {
                    FeatureRow(icon: "checkmark.seal", text: "One-time purchase, no subscription")
                    Divider().overlay(AppTheme.hairline)
                    FeatureRow(icon: "sparkle", text: "Best quality summaries and Year Wrap")
                    Divider().overlay(AppTheme.hairline)
                    FeatureRow(icon: "key", text: "Your own key: you choose the provider and can revoke it anytime")
                    Divider().overlay(AppTheme.hairline)
                    FeatureRow(icon: "arrow.up.right", text: "Transcripts go straight to your provider, never through our servers")
                    Divider().overlay(AppTheme.hairline)
                    FeatureRow(icon: "lock", text: "Your key stays in this \(DeviceName.current)'s Keychain")
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.card)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                )

                // Purchase button
                Button {
                    Task { await store.purchaseSmartestAI { try await purchase($0) } }
                } label: {
                    Group {
                        if isPurchasing {
                            ProgressView()
                                .tint(AppTheme.onAccent)
                        } else {
                            Text(price != nil ? "Unlock for \(price!), once" : "Unlock Cloud AI")
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
                .disabled(store.isBusy)

                // Why the last attempt didn't unlock, or that it's waiting for approval
                if let notice = store.notice {
                    Text(notice.text)
                        .font(.footnote)
                        .foregroundStyle(notice.isError ? AppTheme.destructive : AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                // Cancel button
                Button("Not now", action: onCancel)
                    .foregroundStyle(AppTheme.textPrimary)

                // Restore (App Store Guideline 3.1.1) and redeem
                HStack(spacing: 32) {
                    Button {
                        Task { await store.restorePurchases() }
                    } label: {
                        HStack(spacing: 4) {
                            if isRestoring {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text("Restore purchases")
                        }
                    }
                    Button("Redeem code") {
                        store.clearNotice()
                        showRedeemSheet = true
                    }
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .disabled(store.isBusy)

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
        // Apple's code sheet, presented from this sheet so it shows on top of it
        .offerCodeRedemption(isPresented: $showRedeemSheet) { result in
            Task { await store.codeRedemptionFinished(result) }
        }
        .onChange(of: store.isSmartestAIUnlocked) { _, unlocked in
            if unlocked { onUnlocked() }
        }
        .task {
            store.clearNotice()
            if store.isSmartestAIUnlocked {
                onUnlocked()
                return
            }
            // Try again if the price didn't load at launch
            if store.smartestAIProduct == nil {
                await store.loadProducts()
            }
        }
    }
}

/// One reason to unlock Smartest, in the purchase card
private struct SmartestPoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
