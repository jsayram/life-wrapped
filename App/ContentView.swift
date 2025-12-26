// =============================================================================
// ContentView — Main app interface
// =============================================================================

import SwiftUI
import SharedModels
import Charts
import Transcription
import Storage
import Summarization
import Security

// Note: Extensions, KeychainHelper, WordAnalyzer, and WiggleModifier are now in App/Helpers/

// MARK: - AppTheme

/// Apple Intelligence-inspired design system with purple/blue/magenta/green color palette
/// 
/// WCAG Compliance: All colors meet WCAG AA standards when used appropriately:
/// - darkPurple, magenta, emerald: Suitable for text on white (≥4.5:1)
/// - purple, skyBlue: Suitable for large text/icons on white (≥3:1), meets AA for dark backgrounds
/// - lightPurple: Background/border use only, not for text content
/// 
/// Usage Guidelines:
/// - Use darkPurple/magenta for body text and important labels
/// - Use purple/skyBlue for buttons, icons, and accents
/// - Use lightPurple only for decorative backgrounds and borders
/// - All text uses system .primary/.secondary colors; theme colors are for accents only
struct AppTheme {
    // MARK: - Core Colors
    
    /// Dark purple - Primary accent for active states
    /// Contrast: White 7.8:1 (AAA) | Black 2.7:1
    /// Usage: Text, buttons, active states
    static let darkPurple = Color(hex: "#6D28D9")
    
    /// Medium purple - Secondary accent for buttons and highlights
    /// Contrast: White 5.2:1 (AA) | Black 4.0:1
    /// Usage: Icons, tints, large text
    static let purple = Color(hex: "#8B5CF6")
    
    /// Light purple - Tertiary accent for backgrounds and borders
    /// Contrast: White 2.1:1 | Black 10.0:1 (AAA)
    /// Usage: Backgrounds, borders (never for text)
    static let lightPurple = Color(hex: "#C4B5FD")
    
    /// Sky blue - Cool accent for info states
    /// Contrast: White 3.8:1 | Black 5.5:1 (AA)
    /// Usage: Icons, info badges, dark mode text
    static let skyBlue = Color(hex: "#60A5FA")
    
    /// Pale blue - Subtle backgrounds
    /// Contrast: White 1.4:1 | Black 15.0:1 (AAA)
    /// Usage: Backgrounds only (never for text)
    static let paleBlue = Color(hex: "#DBEAFE")
    
    /// Magenta - Energetic accent for recording states
    /// Contrast: White 4.9:1 (AA) | Black 4.3:1
    /// Usage: Text, recording badges, active states
    static let magenta = Color(hex: "#EC4899")
    
    /// Emerald - Success states
    /// Contrast: White 4.5:1 (AA) | Black 4.7:1 (AA)
    /// Usage: Success text, checkmarks, status badges
    static let emerald = Color(hex: "#10B981")
    
    // MARK: - Card Overlays (Environment-Aware)
    
    /// Subtle purple overlay for cards
    /// Light mode: 0.03 opacity | Dark mode: 0.05 opacity
    static func cardGradient(for colorScheme: ColorScheme) -> some ShapeStyle {
        let opacity = colorScheme == .light ? 0.03 : 0.05
        return RadialGradient(
            colors: [
                purple.opacity(opacity),
                darkPurple.opacity(opacity * 0.5),
                Color.clear
            ],
            center: .center,
            startRadius: 50,
            endRadius: 200
        )
    }
    
    // MARK: - Icon Backgrounds
    
    /// Light purple background for icon-only buttons
    static let purpleIconBackground = purple.opacity(0.1)
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var selectedTab = 0
    
    init() {
        print("🖼️ [ContentView] Initializing ContentView")
    }
    
    var body: some View {
        Group {
            if coordinator.isInitialized {
                TabView(selection: $selectedTab) {
                    HomeTab()
                        .tabItem {
                            Label("Home", systemImage: "house.fill")
                        }
                        .tag(0)

                    HistoryTab()
                        .tabItem {
                            Label("History", systemImage: "list.bullet")
                        }
                        .tag(1)

            OverviewTab()
                .tabItem {
                    Label("Overview", systemImage: "doc.text.fill")
                }
                .tag(2)

            SettingsTab()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
                }
                .tint(AppTheme.purple)
            } else {
                // Show loading state while not initialized
                Color.clear
            }
        }
        .sheet(isPresented: $coordinator.needsPermissions) {
            PermissionsView()
                .environmentObject(coordinator)
                .interactiveDismissDisabled()
        }
        .toast($coordinator.currentToast)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToSettingsTab"))) { _ in
            selectedTab = 3
        }
        .overlay {
            if !coordinator.isInitialized && coordinator.initializationError == nil && !coordinator.needsPermissions {
                LoadingOverlay()
            }
        }
        .alert("Initialization Error", isPresented: .constant(coordinator.initializationError != nil)) {
            Button("Retry") {
                Task {
                    await coordinator.initialize()
                }
            }
        } message: {
            if let error = coordinator.initializationError {
                Text(error.localizedDescription)
            }
        }
    }
}

// MARK: - Home Tab

// MARK: - Summary Quality Card

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

struct WordCategory {
    let category: String
    let icon: String
    let color: Color
    let words: [String]
}

// Simple flow layout for wrapping words
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy First")
                    .font(.title.bold())
                
                VStack(alignment: .leading, spacing: 12) {
                    PrivacyPoint(
                        icon: "waveform",
                        title: "Transcription: 100% On-Device",
                        description: "All audio recording and speech-to-text happens locally using Apple's Speech framework. Zero network calls."
                    )
                    
                    PrivacyPoint(
                        icon: "sparkles",
                        title: "AI Summaries: User-Controlled",
                        description: "Uses OpenAI or Anthropic APIs only if you provide your own API keys. Otherwise, on-device processing with Apple Intelligence or Basic summaries."
                    )
                    
                    PrivacyPoint(
                        icon: "network",
                        title: "Network Calls: Transparent",
                        description: "With API keys: Connects to OpenAI (api.openai.com) or Anthropic (api.anthropic.com) using YOUR keys. Without keys: 100% offline."
                    )
                    
                    PrivacyPoint(
                        icon: "eye.slash.fill",
                        title: "No Tracking",
                        description: "We don't collect analytics, telemetry, or usage data. Your API keys are stored securely in Keychain."
                    )
                    
                    PrivacyPoint(
                        icon: "square.and.arrow.up",
                        title: "Your Data, Your Control",
                        description: "Export or delete your data anytime. Audio files and transcripts never leave your device."
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyPoint: View {
    @Environment(\.colorScheme) var colorScheme
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardGradient(for: colorScheme))
                .allowsHitTesting(false)
        )
        .cornerRadius(12)
    }
}

// MARK: - Recording Detail View

// MARK: - Session Detail View


// MARK: - Language Settings View

// MARK: - Overview Summary Card

struct InsightSessionRow: View {
    @Environment(\.colorScheme) var colorScheme
    let session: RecordingSession
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.startTime, style: .time)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text("\(Int(session.totalDuration / 60)) min • \(session.chunkCount) part\(session.chunkCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.cardGradient(for: colorScheme))
                .allowsHitTesting(false)
        )
        .cornerRadius(8)
    }
}

// MARK: - Session Summary Card (Feed View)

struct YearWrappedCard: View {
    let summary: Summary
    let coordinator: AppCoordinator
    let onRegenerate: () -> Void
    let isRegenerating: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("✨")
                            .font(.title2)
                        Text("Year Wrapped")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    Text("AI-powered yearly summary")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Copy button
                    Button {
                        UIPasteboard.general.string = summary.text
                        coordinator.showSuccess("Year Wrapped summary copied")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.body)
                            .foregroundStyle(AppTheme.skyBlue)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.skyBlue.opacity(0.1))
                    )
                    
                    // Regenerate button
                    Button {
                        onRegenerate()
                    } label: {
                        if isRegenerating {
                            ProgressView()
                                .tint(AppTheme.purple)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.body)
                                .foregroundStyle(AppTheme.magenta)
                        }
                    }
                    .disabled(isRegenerating)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.magenta.opacity(0.1))
                    )
                }
            }
            
            Divider()
            
            // Summary text - scrollable
            ScrollView {
                Text(summary.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: 300)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(8)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    AppTheme.darkPurple.opacity(0.15),
                    AppTheme.magenta.opacity(0.1),
                    AppTheme.purple.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.magenta.opacity(0.3), AppTheme.purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .cornerRadius(16)
        .shadow(color: AppTheme.purple.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Generate Year Wrap Card

struct GenerateYearWrapCard: View {
    let onGenerate: () -> Void
    let isGenerating: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button {
            onGenerate()
        } label: {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.magenta, AppTheme.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(spacing: 8) {
                    Text("Generate Year Wrapped")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("Create an AI-powered summary of your entire year")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                if isGenerating {
                    ProgressView()
                        .tint(AppTheme.purple)
                        .scaleEffect(1.2)
                        .padding(.top, 8)
                } else {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Generate with AI")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.magenta, AppTheme.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(
                LinearGradient(
                    colors: [
                        AppTheme.darkPurple.opacity(0.1),
                        AppTheme.magenta.opacity(0.05),
                        AppTheme.purple.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.magenta.opacity(0.3), AppTheme.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }
}

// MARK: - Topic Tags View

struct TopicTagsView: View {
    let topicsJSON: String
    @State private var topics: [String] = []
    
    var body: some View {
        if !topics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Topics")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                FlowLayout(spacing: 8) {
                    ForEach(topics, id: \.self) { topic in
                        Text(topic.capitalized)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            .task {
                parseTopics()
            }
        }
    }
    
    private func parseTopics() {
        do {
            let parsed = try [String].fromTopicsJSON(topicsJSON)
            // Limit to top 10 topics for display
            topics = Array(parsed.prefix(10))
        } catch {
            print("⚠️ [TopicTagsView] Failed to parse topics: \(error)")
        }
    }
}

// MARK: - Intelligence Engine View

struct IntelligenceEngineView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var activeEngine: EngineTier?
    @State private var availableEngines: [EngineTier] = []
    @State private var isLoading = true
    @State private var showUnavailableAlert = false
    @State private var selectedUnavailableTier: EngineTier?
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading engines...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(EngineTier.privateTiers, id: \.self) { tier in
                    EngineRow(
                        tier: tier,
                        isActive: tier == activeEngine,
                        isAvailable: availableEngines.contains(tier)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectEngine(tier)
                    }
                    
                    if tier != EngineTier.privateTiers.last {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .task {
            await loadEngineStatus()
        }
        .onAppear {
            // Refresh engine status when view appears to catch changes
            Task {
                await loadEngineStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
            // Refresh when engine changes from any view
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
        
        guard let summCoord = coordinator.summarizationCoordinator else {
            print("⚠️ [IntelligenceEngineView] No summarization coordinator available")
            return
        }
        
        // Get active engine
        activeEngine = await summCoord.getActiveEngine()
        
        // Get available engines
        availableEngines = await summCoord.getAvailableEngines()
    }
    
    private func selectEngine(_ tier: EngineTier) {
        // Check if already active
        if tier == activeEngine {
            return
        }
        
        // Check if available
        guard availableEngines.contains(tier) else {
            selectedUnavailableTier = tier
            showUnavailableAlert = true
            return
        }
        
        // Set preferred engine
        Task {
            guard let summCoord = coordinator.summarizationCoordinator else { return }
            
            await summCoord.setPreferredEngine(tier)
            await loadEngineStatus()  // Refresh UI
            
            // Notify other views to refresh
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            
            // Show success toast
            coordinator.showSuccess("Switched to \(tier.displayName)")
        }
    }
    
    private func unavailableMessage(for tier: EngineTier) -> String {
        switch tier {
        case .basic:
            return "Basic engine should always be available. Please restart the app."
        case .local:
            return "Local AI model needs to be downloaded. Go to Settings to download Phi-3.5."
        case .apple:
            return "Apple Intelligence requires iOS 18.1+ and compatible hardware. Your device or OS version doesn't support it yet."
        case .external:
            return "External API engine is not yet configured. You'll need to provide your own API key in a future update."
        }
    }
}

struct EngineRow: View {
    let tier: EngineTier
    let isActive: Bool
    let isAvailable: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(isAvailable ? iconColor : iconColor.opacity(0.3))
                .frame(width: 32, height: 32)
            
            // Name and description
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(tier.displayName)
                        .font(.body)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(isAvailable ? .primary : .secondary)
                    
                    if isActive {
                        Text("Active")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.green.gradient)
                            .clipShape(Capsule())
                    } else if isAvailable && !isActive {
                        Text("Available")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.1))
                            .clipShape(Capsule())
                    } else if !isAvailable {
                        Text("Unavailable")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.gray.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                
                Text(tier.description)
                    .font(.caption)
                    .foregroundStyle(isAvailable ? .secondary : .tertiary)
                    .lineLimit(2)
                
                // Attributes
                HStack(spacing: 12) {
                    AttributeBadge(
                        icon: tier.isPrivacyPreserving ? "lock.fill" : "lock.open.fill",
                        text: tier.isPrivacyPreserving ? "Private" : "Cloud",
                        color: tier.isPrivacyPreserving ? .green : .orange,
                        isAvailable: isAvailable
                    )
                    
                    if tier.requiresInternet {
                        AttributeBadge(
                            icon: "wifi",
                            text: "Internet",
                            color: .blue,
                            isAvailable: isAvailable
                        )
                    }
                }
                .padding(.top, 4)
            }
            
            Spacer()
            
            // Chevron for available engines
            if isAvailable && !isActive {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.green.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isActive ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .opacity(isAvailable ? 1.0 : 0.5)
    }
    
    private var iconName: String {
        switch tier {
        case .basic: return "text.alignleft"
        case .local: return "cpu"
        case .apple: return "apple.logo"
        case .external: return "cloud"
        }
    }
    
    private var iconColor: Color {
        switch tier {
        case .basic: return .gray
        case .local: return .purple
        case .apple: return .blue
        case .external: return .orange
        }
    }
}

struct AttributeBadge: View {
    let icon: String
    let text: String
    let color: Color
    var isAvailable: Bool = true
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(isAvailable ? color : color.opacity(0.4))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isAvailable ? color.opacity(0.1) : color.opacity(0.05))
        .clipShape(Capsule())
    }
}

// MARK: - External AI View

struct ExternalAIView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var activeEngine: EngineTier?
    @State private var availableEngines: [EngineTier] = []
    @State private var isLoading = true
    @State private var showConfigSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                EngineRow(
                    tier: .external,
                    isActive: activeEngine == .external,
                    isAvailable: availableEngines.contains(.external)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectEngine(.external)
                }
                
                Divider()
                    .padding(.leading, 48)
                
                // Configuration button
                Button {
                    showConfigSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.body)
                            .foregroundStyle(.orange)
                            .frame(width: 32, height: 32)
                        
                        Text("Configure API Keys")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .task {
            await loadEngineStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
            // Refresh when engine changes from any view
            Task {
                await loadEngineStatus()
            }
        }
        .sheet(isPresented: $showConfigSheet, onDismiss: {
            // Refresh engine status after config sheet dismisses
            Task {
                await loadEngineStatus()
            }
        }) {
            ExternalAPIConfigView()
                .environmentObject(coordinator)
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
        // Check if available
        guard availableEngines.contains(tier) else {
            showConfigSheet = true  // Open config if not available
            return
        }
        
        // Set preferred engine
        Task {
            guard let summCoord = coordinator.summarizationCoordinator else { return }
            
            await summCoord.setPreferredEngine(tier)
            await loadEngineStatus()
            
            // Notify other views to refresh
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            
            coordinator.showSuccess("Switched to \(tier.displayName)")
        }
    }
}

// MARK: - External API Configuration View

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


struct DetailRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .frame(width: 16)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Historical Data View

struct HistoricalDataView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var yearlyData: [(year: Int, sessionCount: Int, totalDuration: TimeInterval)] = []
    @State private var isLoading = true
    @State private var showDeleteAlert = false
    @State private var selectedYear: Int?
    
    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading historical data...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } else if yearlyData.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Historical Data",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Start recording to build your history.")
                    )
                }
            } else {
                Section {
                    Text("View insights from previous years or delete old data to free up space.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                ForEach(yearlyData, id: \.year) { data in
                    Section {
                        NavigationLink(destination: YearInsightsView(year: data.year)) {
                            HStack(spacing: 16) {
                                // Year icon
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.blue.opacity(0.1))
                                        .frame(width: 50, height: 50)
                                    
                                    Text(String(data.year))
                                        .font(.headline)
                                        .foregroundStyle(.blue)
                                }
                                
                                // Stats
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(data.year)")
                                        .font(.headline)
                                    
                                    HStack(spacing: 12) {
                                        Label("\(data.sessionCount)", systemImage: "mic.circle")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        Label(formatDuration(data.totalDuration), systemImage: "timer")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                selectedYear = data.year
                                showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Historical Data")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadYearlyData()
        }
        .refreshable {
            await loadYearlyData()
        }
        .alert("Delete \(selectedYear ?? 0) Data?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let year = selectedYear {
                    deleteYear(year)
                }
            }
        } message: {
            if let year = selectedYear {
                Text("This will permanently delete all recordings and data from \(year). This action cannot be undone.")
            }
        }
    }
    
    private func loadYearlyData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Fetch all sessions
            let allSessions = try await coordinator.fetchRecentSessions(limit: 100000)
            
            // Group by year
            let calendar = Calendar.current
            var yearlyStats: [Int: (sessionCount: Int, totalDuration: TimeInterval)] = [:]
            
            for session in allSessions {
                let year = calendar.component(.year, from: session.startTime)
                let existing = yearlyStats[year] ?? (sessionCount: 0, totalDuration: 0)
                yearlyStats[year] = (
                    sessionCount: existing.sessionCount + 1,
                    totalDuration: existing.totalDuration + session.totalDuration
                )
            }
            
            // Convert to array and sort by year descending
            yearlyData = yearlyStats.map { (year: $0.key, sessionCount: $0.value.sessionCount, totalDuration: $0.value.totalDuration) }
                .sorted { $0.year > $1.year }
            
        } catch {
            print("❌ [HistoricalDataView] Failed to load yearly data: \(error)")
            coordinator.showError("Failed to load historical data")
        }
    }
    
    private func deleteYear(_ year: Int) {
        Task {
            do {
                // Fetch all sessions for this year
                let allSessions = try await coordinator.fetchRecentSessions(limit: 100000)
                let calendar = Calendar.current
                let sessionsToDelete = allSessions.filter { calendar.component(.year, from: $0.startTime) == year }
                
                // Delete each session using coordinator's delete method (handles cascading)
                for session in sessionsToDelete {
                    try? await coordinator.deleteSession(session.sessionId)
                }
                
                await MainActor.run {
                    coordinator.showSuccess("\(year) data deleted successfully")
                }
                
                // Reload data
                await loadYearlyData()
                
            } catch {
                await MainActor.run {
                    coordinator.showError("Failed to delete \(year) data: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Year Insights View

struct YearInsightsView: View {
    let year: Int
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var sessions: [RecordingSession] = []
    @State private var sessionCount: Int = 0
    @State private var totalDuration: TimeInterval = 0
    @State private var totalWordCount: Int = 0
    @State private var isLoading = true
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var exportURL: URL?
    @State private var showDeleteAlert = false
    @State private var monthlyBreakdown: [(monthNumber: Int, monthName: String, count: Int, duration: TimeInterval)] = []
    
    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading \(String(year)) insights...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } else if sessions.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Data for \(String(year))",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No recordings found for this year.")
                    )
                }
            } else {
                // Overview section
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        // Year header
                        HStack {
                            Text(String(year))
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Image(systemName: "calendar")
                                .font(.title)
                                .foregroundStyle(.blue)
                        }
                        
                        // Stats grid
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            StatCard(
                                icon: "mic.circle.fill",
                                value: "\(sessionCount)",
                                label: "Sessions",
                                color: .blue
                            )
                            
                            StatCard(
                                icon: "timer",
                                value: formatDuration(totalDuration),
                                label: "Total Time",
                                color: .green
                            )
                            
                            StatCard(
                                icon: "text.word.spacing",
                                value: formatWordCount(totalWordCount),
                                label: "Words",
                                color: .purple
                            )
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Overview")
                }
                
                // Monthly breakdown
                if !monthlyBreakdown.isEmpty {
                    Section {
                        ForEach(monthlyBreakdown, id: \.monthNumber) { item in
                            NavigationLink(destination: MonthInsightsView(year: year, month: item.monthNumber, monthName: item.monthName)) {
                                HStack {
                                    Text(item.monthName)
                                        .font(.subheadline)
                                    
                                    Spacer()
                                    
                                    Text("\(item.count) sessions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    
                                    Text(formatDuration(item.duration))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Monthly Breakdown")
                    }
                }
                
                // Export section
                Section {
                    Button {
                        exportYearData()
                    } label: {
                        HStack {
                            Label("Export \(String(year)) Data", systemImage: "square.and.arrow.up")
                            
                            Spacer()
                            
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isExporting)
                } header: {
                    Text("Export")
                } footer: {
                    Text("Export all recordings and transcripts from \(String(year)) as a JSON file.")
                }
                
                // Delete section
                Section {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete All \(String(year)) Data", systemImage: "trash")
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("Permanently delete all recordings and data from \(String(year)). This cannot be undone.")
                }
            }
        }
        .navigationTitle(String(year))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadYearData()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Delete \(String(year)) Data?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteYearData()
            }
        } message: {
            Text("This will permanently delete all \(sessionCount) recordings from \(String(year)). This action cannot be undone.")
        }
    }
    
    private func loadYearData() async {
        isLoading = true
        defer { isLoading = false }
        
        let calendar = Calendar.current
        guard let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let endOfYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return
        }
        
        do {
            // Fetch all sessions for this year
            let allSessions = try await coordinator.fetchRecentSessions(limit: 100000)
            sessions = allSessions.filter { $0.startTime >= startOfYear && $0.startTime < endOfYear }
            
            sessionCount = sessions.count
            totalDuration = sessions.reduce(0) { $0 + $1.totalDuration }
            
            // Calculate word count from database
            if let dbManager = coordinator.getDatabaseManager() {
                var wordCount = 0
                for session in sessions {
                    let count = try await dbManager.fetchSessionWordCount(sessionId: session.sessionId)
                    wordCount += count
                }
                totalWordCount = wordCount
            }
            
            // Calculate monthly breakdown
            var monthlyData: [Int: (count: Int, duration: TimeInterval)] = [:]
            for session in sessions {
                let month = calendar.component(.month, from: session.startTime)
                let existing = monthlyData[month] ?? (count: 0, duration: 0)
                monthlyData[month] = (count: existing.count + 1, duration: existing.duration + session.totalDuration)
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMMM"
            
            monthlyBreakdown = monthlyData.keys.sorted().compactMap { month -> (monthNumber: Int, monthName: String, count: Int, duration: TimeInterval)? in
                guard let data = monthlyData[month],
                      let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
                    return nil
                }
                return (monthNumber: month, monthName: dateFormatter.string(from: date), count: data.count, duration: data.duration)
            }
            
        } catch {
            print("❌ [YearInsightsView] Failed to load year data: \(error)")
            coordinator.showError("Failed to load year data")
        }
    }
    
    private func exportYearData() {
        isExporting = true
        
        Task {
            do {
                guard let dbManager = coordinator.getDatabaseManager() else {
                    throw NSError(domain: "YearInsightsView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not available"])
                }
                
                // Build export data for this year
                var exportData: [[String: Any]] = []
                
                for session in sessions {
                    // Fetch chunks for this session
                    let chunks = try await dbManager.fetchChunksBySession(sessionId: session.sessionId)
                    
                    var sessionData: [String: Any] = [
                        "sessionId": session.sessionId.uuidString,
                        "startTime": ISO8601DateFormatter().string(from: session.startTime),
                        "duration": session.totalDuration,
                        "chunkCount": chunks.count
                    ]
                    
                    // Fetch transcripts for each chunk
                    var transcripts: [[String: Any]] = []
                    for chunk in chunks {
                        let segments = try await dbManager.fetchTranscriptSegments(audioChunkID: chunk.id)
                        let text = segments.map { $0.text }.joined(separator: " ")
                        if !text.isEmpty {
                            transcripts.append([
                                "chunkIndex": chunk.chunkIndex,
                                "text": text,
                                "wordCount": segments.reduce(0) { $0 + $1.wordCount }
                            ])
                        }
                    }
                    sessionData["transcripts"] = transcripts
                    
                    // Fetch session summary if available
                    if let summary = try await dbManager.fetchSummaryForSession(sessionId: session.sessionId) {
                        sessionData["summary"] = summary.text
                    }
                    
                    exportData.append(sessionData)
                }
                
                // Create export JSON
                let exportDict: [String: Any] = [
                    "exportDate": ISO8601DateFormatter().string(from: Date()),
                    "year": year,
                    "sessionCount": sessionCount,
                    "totalDurationSeconds": totalDuration,
                    "totalWordCount": totalWordCount,
                    "sessions": exportData
                ]
                
                let jsonData = try JSONSerialization.data(withJSONObject: exportDict, options: [.prettyPrinted, .sortedKeys])
                
                let filename = "lifewrapped-\(year)-export.json"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try jsonData.write(to: tempURL)
                
                await MainActor.run {
                    exportURL = tempURL
                    showShareSheet = true
                    isExporting = false
                    coordinator.showSuccess("Exported \(sessionCount) sessions from \(year)")
                }
                
            } catch {
                await MainActor.run {
                    isExporting = false
                    coordinator.showError("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func deleteYearData() {
        Task {
            for session in sessions {
                try? await coordinator.deleteSession(session.sessionId)
            }
            
            await MainActor.run {
                coordinator.showSuccess("\(year) data deleted successfully")
            }
            
            // Reload to show empty state
            await loadYearData()
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatWordCount(_ count: Int) -> String {
        if count >= 1000 {
            let formatted = Double(count) / 1000.0
            return String(format: "%.1fK", formatted)
        }
        return "\(count)"
    }
}

// MARK: - Stat Card Component

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Month Insights View

struct MonthInsightsView: View {
    let year: Int
    let month: Int
    let monthName: String
    
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var sessions: [RecordingSession] = []
    @State private var isLoading = true
    @State private var totalDuration: TimeInterval = 0
    @State private var totalWordCount: Int = 0
    
    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading \(monthName) sessions...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } else if sessions.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("No recordings found for \(monthName) \(String(year)).")
                    )
                }
            } else {
                // Stats section
                Section {
                    HStack(spacing: 20) {
                        StatCard(
                            icon: "mic.circle.fill",
                            value: "\(sessions.count)",
                            label: "Sessions",
                            color: .blue
                        )
                        
                        StatCard(
                            icon: "timer",
                            value: formatDuration(totalDuration),
                            label: "Total Time",
                            color: .green
                        )
                        
                        StatCard(
                            icon: "text.word.spacing",
                            value: formatWordCount(totalWordCount),
                            label: "Words",
                            color: .purple
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)
                } header: {
                    Text("Overview")
                }
                
                // Sessions list
                Section {
                    ForEach(sessions, id: \.sessionId) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            SessionRowView(session: session)
                        }
                    }
                } header: {
                    Text("Sessions")
                }
            }
        }
        .navigationTitle("\(monthName) \(String(year))")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMonthData()
        }
    }
    
    private func loadMonthData() async {
        isLoading = true
        defer { isLoading = false }
        
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            return
        }
        
        do {
            // Fetch all sessions and filter by month
            let allSessions = try await coordinator.fetchRecentSessions(limit: 100000)
            sessions = allSessions.filter { $0.startTime >= startOfMonth && $0.startTime < endOfMonth }
                .sorted { $0.startTime > $1.startTime }
            
            totalDuration = sessions.reduce(0) { $0 + $1.totalDuration }
            
            // Calculate word count
            if let dbManager = coordinator.getDatabaseManager() {
                var wordCount = 0
                for session in sessions {
                    let count = try await dbManager.fetchSessionWordCount(sessionId: session.sessionId)
                    wordCount += count
                }
                totalWordCount = wordCount
            }
            
        } catch {
            print("❌ [MonthInsightsView] Failed to load month data: \(error)")
            coordinator.showError("Failed to load month data")
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatWordCount(_ count: Int) -> String {
        if count >= 1000 {
            let formatted = Double(count) / 1000.0
            return String(format: "%.1fK", formatted)
        }
        return "\(count)"
    }
}

// MARK: - Session Row View for Month

struct SessionRowView: View {
    let session: RecordingSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.startTime, style: .date)
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 12) {
                Label(formatTime(session.startTime), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Label(formatDuration(session.totalDuration), systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Array Extension

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppCoordinator.previewInstance())
    }
}
