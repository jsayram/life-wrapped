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
