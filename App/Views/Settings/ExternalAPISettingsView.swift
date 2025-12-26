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
                    
                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                        Label("Get OpenAI API Key", systemImage: "arrow.up.right.square")
                    }
                } else {
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
                    
                    Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                        Label("Get Anthropic API Key", systemImage: "arrow.up.right.square")
                    }
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Your API key is stored securely in the device keychain.")
            }
            
            // Test & Save
            Section {
                Button {
                    testAPIKey()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Testing...")
                        } else {
                            Label("Test API Key", systemImage: "checkmark.shield")
                        }
                    }
                }
                .disabled(currentKey.isEmpty || isTesting)
                
                if let result = testResult {
                    Label(result, systemImage: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(testSuccess ? .green : .red)
                }
                
                Button {
                    saveAPIKey()
                } label: {
                    Label("Save API Key", systemImage: "square.and.arrow.down")
                }
                .disabled(currentKey.isEmpty)
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
        guard availableEngines.contains(.external) else {
            coordinator.showError("Configure an API key first")
            return
        }
        
        Task {
            guard let summCoord = coordinator.summarizationCoordinator else { return }
            await summCoord.setPreferredEngine(.external)
            await loadEngineStatus()
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            coordinator.showSuccess("Switched to External API")
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
        coordinator.showSuccess("API keys cleared")
        
        Task {
            await loadEngineStatus()
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
        }
    }
}
