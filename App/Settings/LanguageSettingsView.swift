import SwiftUI

struct LanguageSettingsView: View {
    @State private var enabledLanguages: Set<String> = []
    @State private var allLanguages: [String] = []
    @EnvironmentObject var coordinator: AppCoordinator
    
    private let enabledLanguagesKey = "enabledLanguages"
    
    var body: some View {
        List {
            Section {
                Text("Select which languages Life Wrapped should detect in your recordings. All processing happens on-device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            Section("Supported Languages (\(allLanguages.count))") {
                ForEach(allLanguages, id: \.self) { languageCode in
                    Toggle(isOn: Binding(
                        get: { enabledLanguages.contains(languageCode) },
                        set: { isEnabled in
                            if isEnabled {
                                enabledLanguages.insert(languageCode)
                            } else {
                                enabledLanguages.remove(languageCode)
                            }
                            saveEnabledLanguages()
                        }
                    )) {
                        HStack {
                            Text(LanguageDetector.flagEmoji(for: languageCode))
                                .font(.title3)
                            Text(LanguageDetector.displayName(for: languageCode))
                            Spacer()
                            Text(languageCode)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .tint(AppTheme.purple)
                }
            }
        }
        .navigationTitle("Languages")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadLanguages()
        }
    }
    
    private func loadLanguages() {
        allLanguages = LanguageDetector.supportedLanguages()
        
        if let savedLanguages = UserDefaults.standard.array(forKey: enabledLanguagesKey) as? [String] {
            enabledLanguages = Set(savedLanguages)
        } else {
            // Default to English and Spanish only
            let defaultLanguages = ["en", "es"]
            enabledLanguages = Set(defaultLanguages.filter { allLanguages.contains($0) })
            saveEnabledLanguages()
        }
    }
    
    private func saveEnabledLanguages() {
        UserDefaults.standard.set(Array(enabledLanguages), forKey: enabledLanguagesKey)
        coordinator.showSuccess("Language preferences saved")
    }
}
