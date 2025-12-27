import SwiftUI
import Summarization
import Security


struct ExternalAPIConfigView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var coordinator: AppCoordinator
    
    @State private var selectedProvider: String = UserDefaults.standard.string(forKey: "externalAPIProvider") ?? "OpenAI"
    @State private var openaiKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $selectedProvider) {
                        Text("OpenAI").tag("OpenAI")
                        Text("Anthropic").tag("Anthropic")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("AI Provider")
                } footer: {
                    Text("Select which external AI service you want to use")
                }
                
                if selectedProvider == "OpenAI" {
                    Section {
                        SecureField("API Key", text: $openaiKey)
                            .textContentType(.password)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                        
                        Button {
                            testAPIKey()
                        } label: {
                            HStack {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Testing Key...")
                                } else {
                                    Label("Test API Key", systemImage: "checkmark.shield")
                                }
                            }
                        }
                        .disabled(openaiKey.isEmpty || isTesting)
                        
                        if let result = testResult {
                            Label(result, systemImage: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(testSuccess ? .green : .red)
                        }
                        
                        Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                            Label("Get OpenAI API Key", systemImage: "arrow.up.right.square")
                        }
                    } header: {
                        Text("OpenAI Configuration")
                    } footer: {
                        Text("Your API key is stored securely in Keychain. Never shared with anyone.\n\nNote: Using OpenAI sends your transcript data to their servers. Standard API rates apply.")
                    }
                } else {
                    Section {
                        SecureField("API Key", text: $anthropicKey)
                            .textContentType(.password)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                        
                        Button {
                            testAPIKey()
                        } label: {
                            HStack {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Testing Key...")
                                } else {
                                    Label("Test API Key", systemImage: "checkmark.shield")
                                }
                            }
                        }
                        .disabled(anthropicKey.isEmpty || isTesting)
                        
                        if let result = testResult {
                            Label(result, systemImage: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(testSuccess ? .green : .red)
                        }
                        
                        Link(destination: URL(string: "https://console.anthropic.com/account/keys")!) {
                            Label("Get Anthropic API Key", systemImage: "arrow.up.right.square")
                        }
                    } header: {
                        Text("Anthropic Configuration")
                    } footer: {
                        Text("Your API key is stored securely in Keychain. Never shared with anyone.\n\nNote: Using Anthropic sends your transcript data to their servers. Standard API rates apply.")
                    }
                }
                
                Section {
                    Button {
                        saveConfiguration()
                    } label: {
                        if isSaving {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Saving...")
                            }
                        } else {
                            Text("Save Configuration")
                        }
                    }
                    .disabled(isSaving || (selectedProvider == "OpenAI" ? openaiKey.isEmpty : anthropicKey.isEmpty))
                }
            }
            .navigationTitle("External AI Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadExistingKeys()
            }
            .onChange(of: selectedProvider) { _, _ in
                testResult = nil  // Clear test result when switching providers
            }
            .onChange(of: openaiKey) { _, _ in
                testResult = nil  // Clear test result when key changes
            }
            .onChange(of: anthropicKey) { _, _ in
                testResult = nil  // Clear test result when key changes
            }
        }
    }
    
    private func loadExistingKeys() async {
        // Load existing keys from Keychain
        let keychain = KeychainManager.shared
        if let openaiExisting = await keychain.getAPIKey(for: .openai) {
            openaiKey = openaiExisting
        }
        if let anthropicExisting = await keychain.getAPIKey(for: .anthropic) {
            anthropicKey = anthropicExisting
        }
    }
    
    private func testAPIKey() {
        isTesting = true
        testResult = nil
        
        Task {
            do {
                // Simple test: check if key format looks valid
                let currentKey = selectedProvider == "OpenAI" ? openaiKey : anthropicKey
                
                if selectedProvider == "OpenAI" {
                    // OpenAI keys start with "sk-"
                    if currentKey.hasPrefix("sk-") && currentKey.count > 20 {
                        testSuccess = true
                        testResult = "Key format looks valid"
                    } else {
                        testSuccess = false
                        testResult = "Invalid key format (should start with 'sk-')"
                    }
                } else {
                    // Anthropic keys start with "sk-ant-"
                    if currentKey.hasPrefix("sk-ant-") && currentKey.count > 20 {
                        testSuccess = true
                        testResult = "Key format looks valid"
                    } else {
                        testSuccess = false
                        testResult = "Invalid key format (should start with 'sk-ant-')"
                    }
                }
                
                isTesting = false
            }
        }
    }
    
    private func saveConfiguration() {
        isSaving = true
        
        Task {
            let keychain = KeychainManager.shared
            
            if selectedProvider == "OpenAI" && !openaiKey.isEmpty {
                await keychain.setAPIKey(openaiKey, for: .openai)
                UserDefaults.standard.set("OpenAI", forKey: "externalAPIProvider")
            } else if selectedProvider == "Anthropic" && !anthropicKey.isEmpty {
                await keychain.setAPIKey(anthropicKey, for: .anthropic)
                UserDefaults.standard.set("Anthropic", forKey: "externalAPIProvider")
            }
            
            // Immediately refresh available engines so External AI becomes available
            if let summCoord = coordinator.summarizationCoordinator {
                _ = await summCoord.getAvailableEngines()
            }
            
            isSaving = false
            coordinator.showSuccess("API key saved! External AI is now available.")
            dismiss()
        }
    }
}


