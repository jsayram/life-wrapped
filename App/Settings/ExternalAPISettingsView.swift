import SwiftUI
import Summarization

struct ExternalAPISettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var activeEngine: EngineTier?
    @State private var availableEngines: [EngineTier] = []
    @State private var isLoading = true
    @State private var selectedProvider: String = UserDefaults.standard.string(forKey: "externalAPIProvider") ?? "OpenAI"
    @State private var selectedModel: String = UserDefaults.standard.string(forKey: "externalAPIModel") ?? "gpt-4.1"
    @State private var openaiKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess: Bool = false
    
    // Track if coming from Year Wrap flow
    let fromYearWrap: Bool
    
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
    
    private var currentKey: String {
        selectedProvider == "OpenAI" ? openaiKey : anthropicKey
    }
    
    var body: some View {
        List {
            // Status
            Section {
                EngineSelectionRow(
                    tier: .external,
                    isActive: activeEngine == .external,
                    isAvailable: availableEngines.contains(.external)
                ) {
                    activateExternalEngine()
                }
            } header: {
                Text("Status")
            } footer: {
                if availableEngines.contains(.external) {
                    Text("External API is configured and ready to use.")
                } else {
                    Text("Configure an API key below to enable external AI.")
                }
            }
            
            // Provider Selection
            Section {
                Picker("Provider", selection: $selectedProvider) {
                    Text("OpenAI").tag("OpenAI")
                    Text("Anthropic").tag("Anthropic")
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedProvider) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "externalAPIProvider")
                    // Reset to default model for new provider
                    let defaultModel = newValue == "OpenAI" ? "gpt-4.1" : "claude-sonnet-4-5"
                    selectedModel = defaultModel
                    UserDefaults.standard.set(defaultModel, forKey: "externalAPIModel")
                }
            } header: {
                Text("AI Provider")
            }
            
            // Model Selection
            Section {
                Picker("Model", selection: $selectedModel) {
                    ForEach(currentModels, id: \.0) { model in
                        Text(model.1).tag(model.0)
                    }
                }
                .onChange(of: selectedModel) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "externalAPIModel")
                    coordinator.showSuccess("Model updated to \(newValue)")
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Different models have varying capabilities, speed, and cost.")
            }
            
            // API Key Input
            Section {
                if selectedProvider == "OpenAI" {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SecureField("OpenAI API Key", text: $openaiKey)
                                .textContentType(.password)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .onChange(of: openaiKey) { _, newValue in
                                    // Normalize: trim whitespace and newlines
                                    let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if normalized != newValue {
                                        openaiKey = normalized
                                    }
                                    
                                    // Auto-save when key is entered
                                    if !normalized.isEmpty {
                                        autoSaveKey()
                                    }
                                }
                            
                            // Test button inline
                            Button {
                                testAPIKey()
                            } label: {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "checkmark.shield")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(openaiKey.isEmpty || isTesting)
                        }
                        
                        if !openaiKey.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("API key configured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if let result = testResult {
                            Label(result, systemImage: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(testSuccess ? .green : .red)
                        }
                    }
                    
                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                        Label("Get OpenAI API Key", systemImage: "arrow.up.right.square")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SecureField("Anthropic API Key", text: $anthropicKey)
                                .textContentType(.password)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .onChange(of: anthropicKey) { _, newValue in
                                    // Normalize: trim whitespace and newlines
                                    let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if normalized != newValue {
                                        anthropicKey = normalized
                                    }
                                    
                                    // Auto-save when key is entered
                                    if !normalized.isEmpty {
                                        autoSaveKey()
                                    }
                                }
                            
                            // Test button inline
                            Button {
                                testAPIKey()
                            } label: {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "checkmark.shield")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(anthropicKey.isEmpty || isTesting)
                        }
                        
                        if !anthropicKey.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("API key configured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if let result = testResult {
                            Label(result, systemImage: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(testSuccess ? .green : .red)
                        }
                    }
                    
                    Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                        Label("Get Anthropic API Key", systemImage: "arrow.up.right.square")
                    }
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Your API key is saved automatically. Tap the shield icon to verify it works.")
            }
            
            // Clear Keys
            if !openaiKey.isEmpty || !anthropicKey.isEmpty {
                Section {
                    Button(role: .destructive) {
                        clearAPIKeys()
                    } label: {
                        Label("Clear All API Keys", systemImage: "trash")
                    }
                }
            }
            
            // Warning
            Section {
                Label {
                    Text("Data will be sent to \(selectedProvider) servers for processing.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Privacy Notice")
            }
        }
        .navigationTitle("External API")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadEngineStatus()
            loadSavedKeys()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
            Task {
                await loadEngineStatus()
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
    
    private func loadSavedKeys() {
        // Load from keychain
        openaiKey = KeychainHelper.load(key: "openai_api_key") ?? ""
        anthropicKey = KeychainHelper.load(key: "anthropic_api_key") ?? ""
        
        // Load saved model selection
        if let savedModel = UserDefaults.standard.string(forKey: "externalAPIModel") {
            selectedModel = savedModel
        }
    }
    
    private func activateExternalEngine() {
        Task {
            // Refresh available engines first
            guard let summCoord = coordinator.summarizationCoordinator else { return }
            let available = await summCoord.getAvailableEngines()
            
            guard available.contains(.external) else {
                // No valid API key - fall back to next best engine
                await fallbackToNextBestEngine()
                return
            }
            
            await summCoord.setPreferredEngine(.external)
            await loadEngineStatus()
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            
            await MainActor.run {
                coordinator.showSuccess("Switched to External API")
            }
        }
    }
    
    private func testAPIKey() {
        isTesting = true
        testResult = nil
        
        Task {
            let key = currentKey
            guard !key.isEmpty else {
                await MainActor.run {
                    testSuccess = false
                    testResult = "Please enter an API key"
                    isTesting = false
                }
                return
            }
            
            // Use the ExternalAPIEngine to validate the key with a real API request
            guard let summCoord = coordinator.summarizationCoordinator else {
                await MainActor.run {
                    testSuccess = false
                    testResult = "Summarization not initialized"
                    isTesting = false
                }
                return
            }
            
            let provider: ExternalAPIEngine.Provider = selectedProvider == "OpenAI" ? .openai : .anthropic
            let result = await summCoord.validateExternalAPIKey(key, for: provider)
            
            await MainActor.run {
                testSuccess = result.isValid
                testResult = result.message
                isTesting = false
                
                // If validation succeeded, ensure it's saved and activated
                if result.isValid {
                    performSaveAndActivate()
                } else {
                    // Show warning that invalid key won't be saved
                    coordinator.showError("Invalid API key - not saved")
                    
                    // Fall back to next best available engine
                    Task {
                        await fallbackToNextBestEngine()
                    }
                }
            }
        }
    }
    
    private func saveAPIKey() {
        // Save to keychain
        let key = currentKey
        let keychainKey = selectedProvider == "OpenAI" ? "openai_api_key" : "anthropic_api_key"
        
        if KeychainHelper.save(key: keychainKey, value: key) {
            UserDefaults.standard.set(selectedProvider, forKey: "externalAPIProvider")
            UserDefaults.standard.set(selectedModel, forKey: "externalAPIModel")
            coordinator.showSuccess("API key saved securely")
            
            Task {
                await loadEngineStatus()
                NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            }
        } else {
            coordinator.showError("Failed to save API key")
        }
    }
    
    private func clearAPIKeys() {
        KeychainHelper.delete(key: "openai_api_key")
        KeychainHelper.delete(key: "anthropic_api_key")
        openaiKey = ""
        anthropicKey = ""
        
        Task {
            // Check if External was the active engine before clearing
            let wasExternalActive = activeEngine == .external
            
            await loadEngineStatus()
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            
            // If External was active, fall back to best available engine
            if wasExternalActive {
                await fallbackToNextBestEngine()
            }
            
            await MainActor.run {
                coordinator.showSuccess("API keys cleared")
            }
        }
    }
    
    private func fallbackToNextBestEngine() async {
        guard let summCoord = coordinator.summarizationCoordinator else { return }
        
        // Refresh available engines after key removal
        let available = await summCoord.getAvailableEngines()
        
        // Determine fallback: Local AI → Apple Intelligence → Basic
        let fallbackEngine: EngineTier
        let fallbackName: String
        
        if available.contains(.local) {
            fallbackEngine = .local
            fallbackName = "Local AI"
        } else if available.contains(.apple) {
            fallbackEngine = .apple
            fallbackName = "Apple Intelligence"
        } else {
            fallbackEngine = .basic
            fallbackName = "Smart"
        }
        
        // Switch to fallback engine
        await summCoord.setPreferredEngine(fallbackEngine)
        await loadEngineStatus()
        NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
        
        await MainActor.run {
            coordinator.showSuccess("Switched to \(fallbackName)")
        }
    }
    
    private func autoSaveKey() {
        // Save API key to keychain immediately when entered
        let key = currentKey
        let keychainKey = selectedProvider == "OpenAI" ? "openai_api_key" : "anthropic_api_key"
        
        guard !key.isEmpty else { return }
        
        _ = KeychainHelper.save(key: keychainKey, value: key)
        
        // Save provider and model preferences
        UserDefaults.standard.set(selectedProvider, forKey: "externalAPIProvider")
        UserDefaults.standard.set(selectedModel, forKey: "externalAPIModel")
        
        // Activate External engine
        Task {
            guard let summCoord = coordinator.summarizationCoordinator else { return }
            await summCoord.setPreferredEngine(.external)
            await loadEngineStatus()
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
        }
    }
    
    private func performSaveAndActivate() {
        // Save API key to keychain
        let key = currentKey
        let keychainKey = selectedProvider == "OpenAI" ? "openai_api_key" : "anthropic_api_key"
        
        guard KeychainHelper.save(key: keychainKey, value: key) else {
            coordinator.showError("Failed to save API key")
            return
        }
        
        // Save provider and model preferences
        UserDefaults.standard.set(selectedProvider, forKey: "externalAPIProvider")
        UserDefaults.standard.set(selectedModel, forKey: "externalAPIModel")
        
        // Auto-select "Smartest" engine (External)
        Task {
            guard let summCoord = coordinator.summarizationCoordinator else { return }
            await summCoord.setPreferredEngine(.external)
            await loadEngineStatus()
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            
            await MainActor.run {
                coordinator.showSuccess("API key validated • Smartest AI selected")
                
                // If coming from Year Wrap, navigate back to Overview
                if fromYearWrap {
                    // Delay to let user see success message
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        NotificationCenter.default.post(name: NSNotification.Name("NavigateToOverviewTab"), object: nil)
                    }
                }
            }
        }
    }
}
