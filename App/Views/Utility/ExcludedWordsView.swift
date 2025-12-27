import SwiftUI
import SharedModels
import Storage


struct ExcludedWordsView: View {
    @Environment(\.dismiss) private var dismiss
    private let excludedWords = Array(StopWords.all).sorted()
    @State private var customWordsText: String = ""
    @State private var customWords: Set<String> = []
    @State private var savedCustomWordsText: String = "" // Track saved state
    @State private var showUnsavedAlert = false
    @FocusState private var isTextFieldFocused: Bool
    
    private let customWordsKey = "customExcludedWords"
    
    private var hasUnsavedChanges: Bool {
        // Check if text field has content that differs from saved state
        let currentText = customWordsText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !currentText.isEmpty && currentText != savedCustomWordsText
    }
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Common words that are filtered out from the word frequency analysis to focus on meaningful content.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("\(excludedWords.count) words excluded")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("About Excluded Words")
            }
            
            Section {
                ForEach(categoryGroups, id: \.category) { group in
                    DisclosureGroup {
                        FlowLayout(spacing: 8) {
                            ForEach(group.words, id: \.self) { word in
                                Text(word)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.gray.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 8)
                    } label: {
                        HStack {
                            Image(systemName: group.icon)
                                .foregroundStyle(group.color)
                                .frame(width: 24)
                            Text(group.category)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(group.words.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Word Categories")
            }
            
            // Display saved custom words
            if !customWords.isEmpty {
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(customWords).sorted(), id: \.self) { word in
                            HStack(spacing: 6) {
                                Text(word)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Button {
                                    withAnimation {
                                        removeCustomWord(word)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.purple.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    HStack {
                        Text("Your Custom Words")
                        Spacer()
                        Text("\(customWords.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Tap the X to remove a custom word")
                        .font(.caption2)
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add your own words to exclude")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("Enter words separated by commas", text: $customWordsText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTextFieldFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    Button("Save Custom Words") {
                        // Dismiss keyboard first, then save after a brief delay
                        isTextFieldFocused = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            saveCustomWords()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.purple)
                    .disabled(customWordsText.isEmpty)
                    
                    Text("Words will be converted to lowercase and trimmed. Separate multiple words with commas.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Add Custom Words")
            }
        }
        .navigationTitle("Excluded Words")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasUnsavedChanges)
        .toolbar {
            if hasUnsavedChanges {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showUnsavedAlert = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
            }
        }
        .alert("Unsaved Custom Words", isPresented: $showUnsavedAlert) {
            Button("Save and Go Back", role: .none) {
                saveCustomWords()
                dismiss()
            }
            Button("Discard", role: .destructive) {
                customWordsText = savedCustomWordsText
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved words in the text field. Do you want to save them before going back?")
        }
        .onAppear {
            loadCustomWords()
        }
    }
    
    private func loadCustomWords() {
        if let savedWords = UserDefaults.standard.stringArray(forKey: customWordsKey) {
            customWords = Set(savedWords)
            // Keep track of saved state but don't populate text field
            savedCustomWordsText = savedWords.sorted().joined(separator: ", ")
        }
    }
    
    private func saveCustomWords() {
        // Parse comma-separated words
        let newWords = customWordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0.count >= 2 }
        
        // Add new words to existing set (don't replace)
        customWords.formUnion(newWords)
        
        // Save to UserDefaults
        UserDefaults.standard.set(Array(customWords), forKey: customWordsKey)
        
        // Update saved state and clear text field
        savedCustomWordsText = Array(customWords).sorted().joined(separator: ", ")
        customWordsText = ""
    }
    
    private func removeCustomWord(_ word: String) {
        customWords.remove(word)
        UserDefaults.standard.set(Array(customWords), forKey: customWordsKey)
        // Update saved state (text field should remain empty)
        savedCustomWordsText = Array(customWords).sorted().joined(separator: ", ")
    }
    
    private var categoryGroups: [WordCategory] {
        // Use categories from constants file (single source of truth)
        StopWords.categories.map { category in
            WordCategory(
                category: category.name,
                icon: category.icon,
                color: category.color,
                words: Array(category.words).sorted()
            )
        }
    }
}

