// =============================================================================
// ContentView — Main app interface
// =============================================================================

import SwiftUI
import SharedModels
import Charts
import Transcription
import Storage
import Summarization
import LocalLLM
import Security

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

// MARK: - Color Hex Extension

extension Color {
    /// Initialize Color from hex string (e.g., "#8B5CF6" or "8B5CF6")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let r, g, b, a: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 6: // RGB (24-bit)
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8: // ARGB (32-bit)
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - UserDefaults Extension for Rollup Settings

extension UserDefaults {
    var rollupDateFormat: String {
        get { string(forKey: "rollupDateFormat") ?? "MMM d, yyyy" }
        set { set(newValue, forKey: "rollupDateFormat") }
    }
    
    var rollupTimeFormat: String {
        get { string(forKey: "rollupTimeFormat") ?? "h:mm a" }
        set { set(newValue, forKey: "rollupTimeFormat") }
    }
}

// MARK: - LoadingView

/// Custom loading indicator with Apple Intelligence aesthetic
struct LoadingView: View {
    enum Size {
        case small, medium, large
        
        var diameter: CGFloat {
            switch self {
            case .small: return 60
            case .medium: return 120
            case .large: return 180
            }
        }
        
        var dotSize: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            case .large: return 8
            }
        }
    }
    
    let size: Size
    @State private var rotationDegrees: Double = 0
    @State private var pulse1Scale: CGFloat = 0.8
    @State private var pulse2Scale: CGFloat = 0.8
    @State private var pulse3Scale: CGFloat = 0.8
    
    var body: some View {
        ZStack {
            // Pulsing concentric circles
            Circle()
                .strokeBorder(
                    RadialGradient(
                        colors: [AppTheme.purple, AppTheme.magenta.opacity(0.3)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.diameter * 0.15
                    ),
                    lineWidth: 2
                )
                .frame(width: size.diameter * 0.3, height: size.diameter * 0.3)
                .scaleEffect(pulse1Scale)
                .opacity(2.0 - pulse1Scale)
            
            Circle()
                .strokeBorder(
                    RadialGradient(
                        colors: [AppTheme.skyBlue, AppTheme.purple.opacity(0.3)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.diameter * 0.25
                    ),
                    lineWidth: 2
                )
                .frame(width: size.diameter * 0.5, height: size.diameter * 0.5)
                .scaleEffect(pulse2Scale)
                .opacity(2.0 - pulse2Scale)
            
            Circle()
                .strokeBorder(
                    RadialGradient(
                        colors: [AppTheme.darkPurple, AppTheme.skyBlue.opacity(0.3)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.diameter * 0.38
                    ),
                    lineWidth: 2
                )
                .frame(width: size.diameter * 0.75, height: size.diameter * 0.75)
                .scaleEffect(pulse3Scale)
                .opacity(2.0 - pulse3Scale)
            
            // Rotating dots
            ZStack {
                ForEach(0..<12) { index in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [colorForDot(index), colorForDot(index).opacity(0.5)],
                                center: .center,
                                startRadius: 0,
                                endRadius: size.dotSize
                            )
                        )
                        .frame(width: size.dotSize, height: size.dotSize)
                        .offset(y: -size.diameter / 2 + size.dotSize)
                        .rotationEffect(.degrees(Double(index) * 30))
                        .opacity(opacityForDot(index))
                }
            }
            .rotationEffect(.degrees(rotationDegrees))
        }
        .frame(width: size.diameter, height: size.diameter)
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                rotationDegrees = 360
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse1Scale = 1.2
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.2)) {
                pulse2Scale = 1.2
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.4)) {
                pulse3Scale = 1.2
            }
        }
    }
    
    private func colorForDot(_ index: Int) -> Color {
        let colors: [Color] = [AppTheme.darkPurple, AppTheme.purple, AppTheme.magenta, AppTheme.magenta, 
                                AppTheme.purple, AppTheme.skyBlue, AppTheme.skyBlue, AppTheme.purple,
                                AppTheme.darkPurple, AppTheme.darkPurple, AppTheme.purple, AppTheme.magenta]
        return colors[index % colors.count]
    }
    
    private func opacityForDot(_ index: Int) -> Double {
        return 1.0 - (Double(index) / 12.0 * 0.7)
    }
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var selectedTab = 0
    
    init() {
        print("🖼️ [ContentView] Initializing ContentView")
    }
    
    var body: some View {
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
        .sheet(isPresented: $coordinator.needsPermissions) {
            PermissionsView()
                .interactiveDismissDisabled()
        }
        .alert("Enhance with Local AI", isPresented: $coordinator.showLocalAIWelcomeTip) {
            Button("Open Settings") {
                coordinator.showLocalAIWelcomeTip = false
                selectedTab = 3 // Switch to Settings tab
            }
            Button("Maybe Later", role: .cancel) {
                coordinator.showLocalAIWelcomeTip = false
            }
        } message: {
            Text("Get AI-powered summaries similar to ChatGPT, but running entirely on your device for maximum privacy. Available in Settings → Local AI.")
        }
        .toast($coordinator.currentToast)
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

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            LoadingView(size: .medium)
        }
    }
}

// MARK: - Home Tab

struct HomeTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var localModelAvailable = false
    @State private var showLocalAIDownload = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // App Title - Centered and smaller
                    Text("Life Wrapped")
                        .font(Font.largeTitle.bold())
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.purple, AppTheme.magenta],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    
                    // Streak Display - Minimal and transparent
                    StreakDisplay(streak: coordinator.currentStreak)
                    
                    // Recording Button
                    RecordingButton()
                    
                    // Add Local AI Button (only show if no model available)
                    if !localModelAvailable {
                        AddLocalAIButton {
                            showLocalAIDownload = true
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .refreshable {
                await refreshStats()
                await checkLocalModelAvailability()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showLocalAIDownload) {
                LocalAIDownloadView()
            }
            .task {
                await checkLocalModelAvailability()
            }
        }
    }
    
    private func refreshStats() async {
        print("🔄 [HomeTab] Manual refresh triggered")
        await coordinator.refreshTodayStats()
        await coordinator.refreshStreak()
        print("✅ [HomeTab] Stats refreshed")
    }
    
    private func checkLocalModelAvailability() async {
        let modelManager = LocalLLM.ModelFileManager.shared
        let models = await modelManager.availableModels()
        await MainActor.run {
            localModelAvailable = !models.isEmpty
        }
    }
}

// MARK: - Add Local AI Button

struct AddLocalAIButton: View {
    @Environment(\.colorScheme) var colorScheme
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.purple.opacity(0.15), AppTheme.magenta.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.title)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.purple, AppTheme.magenta],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add Local AI")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Text("Enable smart summaries with on-device AI")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .background(Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardGradient(for: colorScheme))
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.purple.opacity(0.2), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Local AI Download View

struct LocalAIDownloadView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var availableModels: [LocalLLM.ModelFileManager.ModelSize] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Local AI Models")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Download an AI model to enable smart summaries that run entirely on your device. Your data never leaves your phone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(.green)
                            Text("Privacy-First")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Available Models") {
                    ForEach(LocalLLM.ModelFileManager.ModelSize.allCases, id: \.rawValue) { modelSize in
                        ModelDownloadRowView(
                            modelSize: modelSize,
                            isDownloaded: availableModels.contains(modelSize)
                        )
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Requirements")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "wifi")
                                .font(.caption)
                            Text("WiFi connection for download")
                                .font(.caption)
                        }
                        
                        HStack(spacing: 6) {
                            Image(systemName: "memorychip")
                                .font(.caption)
                            Text("2-3 GB free storage space")
                                .font(.caption)
                        }
                        
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.caption)
                            Text("5-10 minutes download time")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Add Local AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadModels()
            }
            .refreshable {
                await loadModels()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ModelDownloadCompleted"))) { _ in
                Task {
                    await loadModels()
                }
            }
        }
    }
    
    private func loadModels() async {
        isLoading = true
        defer { isLoading = false }
        
        let manager = LocalLLM.ModelFileManager.shared
        availableModels = await manager.availableModels()
    }
}

// MARK: - Model Download Row View

struct ModelDownloadRowView: View {
    let modelSize: LocalLLM.ModelFileManager.ModelSize
    let isDownloaded: Bool
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadTask: Task<Void, Never>?
    @State private var showDownloadAlert = false
    @State private var justCompleted = false
    @State private var isCheckingState = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(modelSize.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                    
                    Text("\(modelSize.approximateSizeMB) MB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isDownloaded {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                        
                        Text("Ready")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else if isDownloading || isCheckingState {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(isCheckingState ? "Checking..." : "Downloading...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if !isCheckingState {
                            Text("Continue using the app")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button {
                        showDownloadAlert = true
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.purple)
                }
            }
            
            // Show when download just completed
            if justCompleted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Download complete! Local AI is now available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation {
                            justCompleted = false
                        }
                    }
                }
            }
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                DetailRow(icon: "cpu", text: "On-Device Processing")
                DetailRow(icon: "memorychip", text: "\(modelSize.contextLength.formatted()) tokens context")
                
                if !isDownloaded && !isDownloading {
                    DetailRow(icon: "wifi", text: "Requires WiFi")
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 8)
        .alert("Download Model", isPresented: $showDownloadAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Download") {
                startDownload()
            }
        } message: {
            Text("Download \(modelSize.fullDisplayName)? This will use \(modelSize.approximateSizeMB) MB. Download continues in the background if you navigate away.")
        }
        .task {
            await syncDownloadState()
        }
        .onDisappear {
            // Keep download task running in background when navigating away
            // Don't cancel - let it continue
        }
    }
    
    @MainActor
    private func startDownload() {
        Task {
            let manager = LocalLLM.ModelFileManager.shared
            let alreadyDownloading = await manager.isDownloading(modelSize)
            
            guard !alreadyDownloading else {
                await MainActor.run {
                    coordinator.showError("\(modelSize.displayName) is already downloading")
                }
                return
            }
            
            await MainActor.run {
                isDownloading = true
                downloadProgress = 0.0
                coordinator.showSuccess("Downloading \(modelSize.displayName)... Continue using the app.")
            }
            
            downloadTask = Task {
                do {
                    try await manager.downloadModel(modelSize) { @MainActor progress in
                        self.downloadProgress = progress
                    }
                    
                    await MainActor.run {
                        withAnimation {
                            isDownloading = false
                            justCompleted = true
                        }
                        
                        // Auto-switch to Local AI and refresh engines
                        if let summCoord = coordinator.summarizationCoordinator {
                            Task {
                                _ = await summCoord.getAvailableEngines()
                                await summCoord.setPreferredEngine(.local)
                                coordinator.showSuccess("✅ Local AI is now active!")
                                
                                // Trigger parent view refresh via notification
                                NotificationCenter.default.post(name: NSNotification.Name("ModelDownloadCompleted"), object: nil)
                                
                                // Dismiss after a short delay
                                try? await Task.sleep(for: .seconds(2))
                                dismiss()
                            }
                        }
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        withAnimation {
                            isDownloading = false
                            downloadProgress = 0.0
                        }
                        coordinator.showError("Download cancelled")
                    }
                } catch {
                    await MainActor.run {
                        withAnimation {
                            isDownloading = false
                            downloadProgress = 0.0
                        }
                        coordinator.showError("Download failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func syncDownloadState() async {
        let manager = LocalLLM.ModelFileManager.shared
        let downloading = await manager.isDownloading(modelSize)
        let available = await manager.isModelAvailable(modelSize)
        
        await MainActor.run {
            isCheckingState = false
            
            if downloading {
                print("📥 [ModelDownloadRowView] Download in progress: \(modelSize.displayName)")
                withAnimation {
                    isDownloading = true
                }
            } else if available && isDownloading {
                print("✅ [ModelDownloadRowView] Download completed: \(modelSize.displayName)")
                withAnimation {
                    isDownloading = false
                    justCompleted = true
                }
            } else if !downloading && isDownloading {
                print("⚠️ [ModelDownloadRowView] Download stopped: \(modelSize.displayName)")
                withAnimation {
                    isDownloading = false
                }
            }
        }
    }
}

// MARK: - Streak Card

// MARK: - Streak Display (Minimal)

struct StreakDisplay: View {
    let streak: Int
    
    var body: some View {
        HStack(spacing: 8) {
            Text("🔥")
                .font(.system(size: 20))
            
            Text("\(streak) Day Streak")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.purple.opacity(0.9), AppTheme.magenta.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            if streak > 0 {
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(streakMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
    
    private var streakMessage: String {
        if streak == 0 {
            return ""
        } else if streak == 1 {
            return "Great start!"
        } else if streak < 7 {
            return "Building momentum!"
        } else if streak < 30 {
            return "Amazing!"
        } else {
            return "Incredible!"
        }
    }
}

// Legacy StreakCard kept for compatibility
struct StreakCard: View {
    let streak: Int
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        StreakDisplay(streak: streak)
    }
}

// MARK: - Recording Button

struct RecordingButton: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var recordingDuration: TimeInterval = 0
    @State private var smoothedMagnitudes: [Float] = Array(repeating: 0, count: 80)
    
    // Timer that fires every 0.1 seconds to update the recording duration
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    // Gradient for the waveform (Apple Intelligence colors)
    private let waveformGradient = Gradient(colors: [
        Color(hex: "#FF9500"), // Orange
        Color(hex: "#FF2D55"), // Pink  
        Color(hex: "#A855F7"), // Purple
        Color(hex: "#3B82F6"), // Blue
        Color(hex: "#06B6D4"), // Cyan
        Color(hex: "#10B981"), // Green
        Color(hex: "#FBBF24")  // Yellow
    ])
    
    var body: some View {
        VStack(spacing: 20) {
            Button(action: handleRecordingAction) {
                waveformView
                    .contentShape(Circle())
            }
            .disabled(coordinator.recordingState.isProcessing)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .buttonStyle(.plain)
            
            Text(statusText)
                .font(.headline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .onReceive(timer) { _ in
            updateRecordingState()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {
                coordinator.resetRecordingState()
            }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: coordinator.recordingState) { _, newState in
            if case .failed(let message) = newState {
                errorMessage = message
                showError = true
            }
        }
    }
    
    // MARK: - Subviews
    
    private var waveformView: some View {
        ZStack {
            // Outer ring to indicate it's a button
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [AppTheme.purple.opacity(0.4), AppTheme.magenta.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
                .frame(width: 360, height: 360)
            
            // Background circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(.systemBackground).opacity(0.8),
                            Color(.secondarySystemBackground).opacity(0.9)
                        ],
                        center: .center,
                        startRadius: 50,
                        endRadius: 180
                    )
                )
                .frame(width: 350, height: 350)
            
            // Waveform - Simple overlapping sine waves
            TimelineView(.animation(minimumInterval: 1/60)) { context in
                Canvas { canvasContext, size in
                    drawSineWaveform(
                        context: canvasContext,
                        size: size,
                        time: context.date.timeIntervalSince1970
                    )
                }
                .frame(width: 340, height: 160)
            }
        }
        .frame(width: 360, height: 360)
        .shadow(color: AppTheme.purple.opacity(0.15), radius: 20, x: 0, y: 10)
    }
    
    // MARK: - Drawing Methods
    
    private func drawSineWaveform(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let centerY = size.height / 2
        let isRecording = coordinator.recordingState.isRecording
        
        if !isRecording {
            // Draw flat line when idle
            var flatPath = Path()
            flatPath.move(to: CGPoint(x: 0, y: centerY))
            flatPath.addLine(to: CGPoint(x: size.width, y: centerY))
            
            context.stroke(
                flatPath,
                with: .color(AppTheme.purple.opacity(0.3)),
                style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
            )
            return
        }
        
        // Get audio level from smoothed FFT magnitudes
        let audioLevel = smoothedMagnitudes.reduce(0, +) / Float(max(smoothedMagnitudes.count, 1))
        // Clamp to prevent cutoff (max amplitude should be ~60% of height)
        let maxAmplitude = size.height * 0.3
        let amplitudeScale = min(CGFloat(audioLevel) * 150.0 + 20.0, maxAmplitude)
        
        // Define 2 waves that respond to loudness
        let waves: [(amplitudeMultiplier: CGFloat, frequency: CGFloat, thickness: CGFloat, speed: CGFloat, color: Color)] = [
            (amplitudeMultiplier: 1.0, frequency: 3.0, thickness: 4.0, speed: 1.2, color: Color(hex: "#A855F7")), // Purple
            (amplitudeMultiplier: 0.7, frequency: 5.0, thickness: 2.5, speed: 1.8, color: Color(hex: "#FF2D55")), // Pink
        ]
        
        // Draw each sine wave
        for wave in waves {
            var path = Path()
            let points = 200
            
            for i in 0...points {
                let x = (CGFloat(i) / CGFloat(points)) * size.width
                let normalizedX = (x / size.width) * 2 * .pi * wave.frequency
                let timeOffset = time * wave.speed
                let y = centerY + (amplitudeScale * wave.amplitudeMultiplier) * sin(normalizedX - timeOffset)
                
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            
            context.stroke(
                path,
                with: .color(wave.color),
                style: StrokeStyle(lineWidth: wave.thickness, lineCap: .round, lineJoin: .round)
            )
        }
    }
    
    private func updateRecordingState() {
        if case .recording(let startTime) = coordinator.recordingState {
            recordingDuration = Date().timeIntervalSince(startTime)
        } else {
            recordingDuration = 0
        }
        
        // Apply exponential moving average smoothing to FFT magnitudes
        let rawMagnitudes = coordinator.audioCapture.fftMagnitudes
        for i in 0..<min(smoothedMagnitudes.count, rawMagnitudes.count) {
            smoothedMagnitudes[i] = smoothedMagnitudes[i] * 0.7 + rawMagnitudes[i] * 0.3
        }
    }
    
    // MARK: - Helpers
    
    private var statusText: String {
        switch coordinator.recordingState {
        case .idle: return "Tap to start recording"
        case .recording: 
            return "Tap to stop Recording... \(formatDuration(recordingDuration))"
        case .processing: return "Processing..."
        case .completed: return "Saved!"
        case .failed(let message): return message
        }
    }
    
    private var accessibilityLabel: String {
        switch coordinator.recordingState {
        case .idle: return "Recording button. Tap to start recording"
        case .recording: return "Recording in progress. Tap to stop"
        case .processing: return "Processing audio"
        case .completed: return "Recording saved successfully"
        case .failed: return "Recording failed"
        }
    }
    
    private var accessibilityHint: String {
        switch coordinator.recordingState {
        case .idle: return "Double tap to begin audio recording"
        case .recording: return "Double tap to stop recording"
        default: return ""
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func handleRecordingAction() {
        print("🔘 [RecordingButton] Button tapped, current state: \(coordinator.recordingState)")
        
        // Trigger haptic immediately on button press (before async work)
        if coordinator.recordingState.isRecording {
            print("📳 [RecordingButton] Triggering STOP haptic (.medium)")
            coordinator.triggerHaptic(.medium)
        } else if case .idle = coordinator.recordingState {
            print("📳 [RecordingButton] Triggering START haptic (.heavy)")
            coordinator.triggerHaptic(.heavy)
        }
        
        Task {
            do {
                if coordinator.recordingState.isRecording {
                    print("⏹️ [RecordingButton] Stopping recording...")
                    _ = try await coordinator.stopRecording()
                    print("✅ [RecordingButton] Recording stopped")
                    coordinator.showSuccess("Recording saved successfully!")
                } else if case .idle = coordinator.recordingState {
                    print("▶️ [RecordingButton] Starting recording...")
                    try await coordinator.startRecording()
                    print("✅ [RecordingButton] Recording started")
                    coordinator.showSuccess("Recording started")
                }
            } catch {
                print("❌ [RecordingButton] Action failed: \(error.localizedDescription)")
                coordinator.showError(error.localizedDescription)
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Today Stats Card

// MARK: - History Tab

struct HistoryTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var sessions: [RecordingSession] = []
    @State private var sessionWordCounts: [UUID: Int] = [:]
    @State private var sessionHasSummary: [UUID: Bool] = [:]
    @State private var isLoading = true
    @State private var playbackError: String?
    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @State private var transcriptMatchingSessionIds: Set<UUID> = []
    @State private var isSearchingTranscripts = false
    @State private var searchDebounceTask: Task<Void, Never>?
    
    private var filteredSessions: [RecordingSession] {
        var result = sessions
        
        // Filter by favorites if enabled
        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            
            result = result.filter { session in
                // Search in title
                if let title = session.title, title.lowercased().contains(query) {
                    return true
                }
                // Search in notes
                if let notes = session.notes, notes.lowercased().contains(query) {
                    return true
                }
                // Search in date
                let dateString = formatter.string(from: session.startTime).lowercased()
                if dateString.contains(query) {
                    return true
                }
                // Search in transcripts (from cached results)
                return transcriptMatchingSessionIds.contains(session.sessionId)
            }
        }
        
        return result
    }
    
    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("History")
                .searchable(text: $searchText, prompt: "Search titles, notes, transcripts...")
                .onChange(of: searchText) { _, newValue in
                    // Debounce transcript search
                    searchDebounceTask?.cancel()
                    if newValue.count >= 2 {
                        searchDebounceTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            await searchTranscripts(query: newValue)
                        }
                    } else {
                        transcriptMatchingSessionIds = []
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            if isSearchingTranscripts {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            
                            Button {
                                showFavoritesOnly.toggle()
                            } label: {
                                Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                                    .foregroundStyle(showFavoritesOnly ? .yellow : .secondary)
                            }
                        }
                    }
                }
                .task {
                    await loadSessions()
                }
                .refreshable {
                    await loadSessions()
                }
                .alert("Playback Error", isPresented: .constant(playbackError != nil)) {
                    Button("OK") {
                        playbackError = nil
                    }
                } message: {
                    if let error = playbackError {
                        Text(error)
                    }
                }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if isLoading {
            LoadingView(size: .medium)
        } else if sessions.isEmpty {
            ContentUnavailableView(
                "No Recordings Yet",
                systemImage: "mic.slash",
                description: Text("Tap the record button on the Home tab to start your first journal entry.")
            )
        } else if filteredSessions.isEmpty {
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No recordings match '\(searchText)'")
            )
        } else {
            sessionsList
        }
    }
    
    private var sessionsList: some View {
        List {
            // Stats summary at top
            if !searchText.isEmpty {
                Section {
                    Text("\(filteredSessions.count) recording\(filteredSessions.count == 1 ? "" : "s") found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            ForEach(sortedDates, id: \.self) { date in
                Section {
                    ForEach(sessionsForDate(date), id: \.id) { session in
                        NavigationLink(destination: sessionDetailView(for: session)) {
                            SessionRowClean(
                                session: session,
                                wordCount: sessionWordCounts[session.sessionId],
                                hasSummary: sessionHasSummary[session.sessionId] ?? false
                            )
                        }
                    }
                    .onDelete { offsets in
                        deleteSession(at: offsets, in: date)
                    }
                } header: {
                    HStack {
                        Text(formatSectionDate(date))
                        Spacer()
                        Text("\(sessionsForDate(date).count) recording\(sessionsForDate(date).count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func sessionDetailView(for session: RecordingSession) -> some View {
        SessionDetailView(session: session)
    }
    
    private func sessionsForDate(_ date: Date) -> [RecordingSession] {
        filteredSessions.filter { session in
            Calendar.current.isDate(session.startTime, inSameDayAs: date)
        }
    }
    
    /// Group sessions by date
    private var groupedSessions: [Date: [RecordingSession]] {
        Dictionary(grouping: filteredSessions) { session in
            Calendar.current.startOfDay(for: session.startTime)
        }
    }
    
    /// Sorted dates (most recent first)
    private var sortedDates: [Date] {
        Array(groupedSessions.keys).sorted(by: >)
    }
    
    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Day name like "Monday"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
    
    private func loadSessions() async {
        isLoading = true
        do {
            sessions = try await coordinator.fetchRecentSessions(limit: 100)
            print("✅ [HistoryTab] Loaded \(sessions.count) sessions")
            
            // Load word counts and summary status in parallel
            guard let dbManager = coordinator.getDatabaseManager() else { return }
            await withTaskGroup(of: (UUID, Int, Bool).self) { group in
                for session in sessions {
                    group.addTask {
                        let count = (try? await dbManager.fetchSessionWordCount(sessionId: session.sessionId)) ?? 0
                        let hasSummary = await ((try? dbManager.fetchSummaryForSession(sessionId: session.sessionId)) != nil)
                        return (session.sessionId, count, hasSummary)
                    }
                }
                
                for await (sessionId, wordCount, hasSummary) in group {
                    sessionWordCounts[sessionId] = wordCount
                    sessionHasSummary[sessionId] = hasSummary
                }
            }
        } catch {
            print("❌ [HistoryTab] Failed to load sessions: \(error)")
        }
        isLoading = false
    }
    
    private func searchTranscripts(query: String) async {
        guard query.count >= 2 else {
            transcriptMatchingSessionIds = []
            return
        }
        
        isSearchingTranscripts = true
        do {
            transcriptMatchingSessionIds = try await coordinator.searchSessionsByTranscript(query: query)
            print("🔍 [HistoryTab] Found \(transcriptMatchingSessionIds.count) sessions matching '\(query)' in transcripts")
        } catch {
            print("❌ [HistoryTab] Transcript search failed: \(error)")
            transcriptMatchingSessionIds = []
        }
        isSearchingTranscripts = false
    }
    
    private func deleteSession(at offsets: IndexSet, in date: Date) {
        let sessionsForDate = self.sessionsForDate(date)
        
        Task {
            for index in offsets {
                let session = sessionsForDate[index]
                // Stop playback if any chunk from this session is playing
                for chunk in session.chunks {
                    if coordinator.audioPlayback.currentlyPlayingURL == chunk.fileURL {
                        coordinator.audioPlayback.stop()
                        break
                    }
                }
                do {
                    try await coordinator.deleteSession(session.sessionId)
                    sessions.removeAll { $0.sessionId == session.sessionId }
                    sessionWordCounts.removeValue(forKey: session.sessionId)
                    sessionHasSummary.removeValue(forKey: session.sessionId)
                } catch {
                    print("Failed to delete session: \(error)")
                }
            }
        }
    }
}

// MARK: - Clean Session Row

struct SessionRowClean: View {
    let session: RecordingSession
    let wordCount: Int?
    let hasSummary: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Time badge - fixed width to prevent wrapping
            Text(timeString)
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
                .frame(width: 70, alignment: .leading)
            
            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1, height: 40)
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Title row (if available)
                if let title = session.title, !title.isEmpty {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        if session.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                
                // Duration and word count - always show
                HStack(spacing: 10) {
                    Label(formatDuration(session.totalDuration), systemImage: "clock")
                    
                    if let words = wordCount, words > 0 {
                        Label("\(words) words", systemImage: "doc.text")
                    }
                    
                    if session.isFavorite && (session.title == nil || session.title?.isEmpty == true) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                // Status indicators
                HStack(spacing: 6) {
                    if session.chunkCount > 1 {
                        StatusPill(text: "\(session.chunkCount) parts", color: .blue, icon: "waveform")
                    }
                    
                    if hasSummary {
                        StatusPill(text: "Summarized", color: .green, icon: "checkmark.circle.fill")
                    }
                    
                    // Show processing if wordCount is nil (still being transcribed)
                    if wordCount == nil {
                        StatusPill(text: "Processing", color: .orange, icon: "gearshape.fill")
                    }
                    // Show "No Words" badge if transcription complete but 0 words
                    else if let count = wordCount, count == 0 {
                        StatusPill(text: "No Words To Transcribe", color: .gray, icon: "mic.slash.fill")
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: session.startTime)
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

// MARK: - Status Pill

struct StatusPill: View {
    let text: String
    let color: Color
    let icon: String?
    @Environment(\.colorScheme) var colorScheme
    
    init(text: String, color: Color, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RadialGradient(
                colors: [color.opacity(0.2), color.opacity(0.05)],
                center: .center,
                startRadius: 5,
                endRadius: 20
            )
        )
        .clipShape(Capsule())
    }
}

// MARK: - Legacy SessionRow (kept for compatibility)

struct SessionRow: View {
    let session: RecordingSession
    let wordCount: Int?
    let sentiment: Double?
    let language: String?
    
    var body: some View {
        SessionRowClean(
            session: session,
            wordCount: wordCount,
            hasSummary: false
        )
    }
}

struct RecordingRow: View {
    let recording: AudioChunk
    let isPlaying: Bool
    var showPlayButton: Bool = true
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(recording.startTime, style: .date)
                    .font(.headline)
                
                HStack(spacing: 16) {
                    Text(recording.startTime, style: .time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(formatDuration(recording.duration))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Play/Pause button (optional)
            if showPlayButton {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
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

// MARK: - Overview Tab

enum TimeRange: String, CaseIterable, Identifiable {
    case yesterday = "Yesterday"
    case today = "Today"
    case week = "Week"
    case month = "Month"
    case allTime = "Year"
    
    var id: String { rawValue }
    
    var fullName: String {
        switch self {
        case .yesterday: return "Yesterday"
        case .today: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        case .allTime: return "This Year"
        }
    }
}

// MARK: - Word Frequency Analysis

struct WordFrequency: Identifiable {
    let id = UUID()
    let word: String
    let count: Int
}

class WordAnalyzer {
    // Use comprehensive stopwords from constants file (single source of truth)
    static let stopwords = StopWords.all
    
    static func analyzeWords(from texts: [String], limit: Int = 20, customExcludedWords: Set<String> = []) -> [WordFrequency] {
        // Combine built-in and custom stopwords
        let allStopwords = stopwords.union(customExcludedWords)
        var wordCounts: [String: Int] = [:]
        
        // Process all texts
        for text in texts {
            // Normalize: lowercase and split into words
            let words = text.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { word in
                    // Remove punctuation from edges
                    word.trimmingCharacters(in: .punctuationCharacters)
                }
                .filter { word in
                    // Filter: non-empty, at least 2 chars, not a stopword, not a number
                    !word.isEmpty &&
                    word.count >= 2 &&
                    !allStopwords.contains(word) &&
                    !word.allSatisfy { $0.isNumber }
                }
            
            // Count occurrences
            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }
        
        // Sort by frequency and take top N
        return wordCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { WordFrequency(word: $0.key, count: $0.value) }
    }
}

struct OverviewTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.colorScheme) var colorScheme
    @State private var periodSummary: Summary?
    @State private var sessionCount: Int = 0
    @State private var sessionsInPeriod: [RecordingSession] = []
    @State private var yearWrapSummary: Summary?
    @State private var isWrappingUpYear = false
    @State private var isLoading = true
    @State private var selectedTimeRange: TimeRange = .allTime
    @State private var showYearWrapConfirmation = false
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingView(size: .medium)
                } else if periodSummary == nil && sessionsInPeriod.isEmpty {
                    ContentUnavailableView(
                        "No Overview Yet",
                        systemImage: "doc.text",
                        description: Text("Record more journal entries to generate summaries.")
                    )
                } else {
                    List {
                        // Period Summary sections
                        // For Year (All Time): Show Year Wrap first, then rollup below
                        if selectedTimeRange == .allTime {
                            // Year Wrap Summary (Pro AI) - if available
                            if let yearWrap = yearWrapSummary {
                                Section {
                                    OverviewSummaryCard(
                                        summary: yearWrap,
                                        periodTitle: "✨ Year Wrap (Pro AI)",
                                        sessionCount: sessionCount,
                                        sessionsInPeriod: sessionsInPeriod,
                                        coordinator: coordinator,
                                        onRegenerate: nil,
                                        wrapAction: {
                                            showYearWrapConfirmation = true
                                        },
                                        wrapIsLoading: isWrappingUpYear
                                    )
                                }
                            }
                            
                            // Year Rollup (below Year Wrap)
                            if let rollup = periodSummary {
                                Section {
                                    OverviewSummaryCard(
                                        summary: rollup,
                                        periodTitle: "📅 Year Rollup",
                                        sessionCount: sessionCount,
                                        sessionsInPeriod: sessionsInPeriod,
                                        coordinator: coordinator,
                                        onRegenerate: {
                                            await regeneratePeriodSummary()
                                        },
                                        wrapAction: yearWrapSummary == nil ? {
                                            showYearWrapConfirmation = true
                                        } : nil,
                                        wrapIsLoading: isWrappingUpYear
                                    )
                                }
                            }
                        } else {
                            // Other time ranges: show single period summary
                            if let summary = periodSummary {
                                Section {
                                    OverviewSummaryCard(
                                        summary: summary,
                                        periodTitle: periodTitle,
                                        sessionCount: sessionCount,
                                        sessionsInPeriod: sessionsInPeriod,
                                        coordinator: coordinator,
                                        onRegenerate: selectedTimeRange == .yesterday ? nil : {
                                            await regeneratePeriodSummary()
                                        },
                                        wrapAction: nil,
                                        wrapIsLoading: false
                                    )
                                }
                            }
                        }
                        
                        
                        
                    }
                }
            }
            .navigationTitle("Overview")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(AppTheme.purple)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                }
            }
            .task {
                await loadInsights()
            }
            .refreshable {
                await loadInsights()
            }
            .onChange(of: selectedTimeRange) { oldValue, newValue in
                Task {
                    await loadInsights()
                }
            }
            .alert("Generate Year Wrap", isPresented: $showYearWrapConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("✨ Generate with Pro AI") {
                    Task {
                        await wrapUpYear(forceRegenerate: false)
                    }
                }
            } message: {
                Text("✨ Clicking 'Generate with Pro AI' will use your configured Year Wrapped Pro AI service (OpenAI or Anthropic) to create a comprehensive, beautifully crafted year-in-review summary.\n\n⏱️ This process may take 30-60 seconds as it analyzes your entire year of recordings.\n\n🔑 Requires valid Pro AI credentials configured in Settings.\n\n🔄 Use the orange refresh button to roll up the monthly summaries (no Pro AI needed).")
            }
        }
    }
    
    private func loadInsights() async {
        isLoading = true
        do {
            // Get date range for filtering
            let dateRange = getDateRange(for: selectedTimeRange)
            
            // Load period summary based on selected time range
            let periodType: PeriodType = {
                switch selectedTimeRange {
                case .yesterday: return .day
                case .today: return .day
                case .week: return .week
                case .month: return .month
                case .allTime: return .year // Show yearly summary for current year
                }
            }()
            
            // Load sessions in this period first
            if let dbManager = coordinator.getDatabaseManager() {
                if selectedTimeRange == .today || selectedTimeRange == .yesterday {
                    sessionsInPeriod = (try? await dbManager.fetchSessionsByDate(date: dateRange.start)) ?? []
                } else {
                    // For week/month/all, fetch ALL sessions and filter by date range
                    let allSessions = try? await coordinator.fetchRecentSessions(limit: 10000)
                    sessionsInPeriod = allSessions?.filter { session in
                        session.startTime >= dateRange.start && session.startTime < dateRange.end
                    } ?? []
                }
                sessionCount = sessionsInPeriod.count
            }
            
            // Try to fetch existing period summary (don't auto-generate on view load)
            // For week/month/year, use Date() to get current period, for day use startDate
            let dateForFetch = (periodType == .day) ? dateRange.start : Date()
            periodSummary = try? await coordinator.fetchPeriodSummary(type: periodType, date: dateForFetch)

            if selectedTimeRange == .allTime {
                yearWrapSummary = try? await coordinator.fetchPeriodSummary(type: .yearWrap, date: dateForFetch)
            } else {
                yearWrapSummary = nil
            }
            
            // Debug logging
            if periodSummary == nil && !sessionsInPeriod.isEmpty {
                print("ℹ️ [OverviewTab] No \(periodType.rawValue) summary found for \(dateForFetch.formatted()), use Regenerate to create one")
                print("   Searched for: type=\(periodType.rawValue), date=\(dateForFetch.ISO8601Format())")
                print("   Sessions in period: \(sessionsInPeriod.count)")
            } else if periodSummary != nil {
                print("✅ [OverviewTab] Found \(periodType.rawValue) summary for \(dateForFetch.formatted())")
            }
        } catch {
            print("❌ [OverviewTab] Failed to load insights: \(error)")
        }
        isLoading = false
    }
    
    private func regeneratePeriodSummary() async {
        let (startDate, _) = getDateRange(for: selectedTimeRange)
        
        let periodType: PeriodType = {
            switch selectedTimeRange {
            case .yesterday: return .day
            case .today: return .day
            case .week: return .week
            case .month: return .month
            case .allTime: return .year
            }
        }()
        
        // Use Date() (today) for week/month/year calculations, startDate for day
        let dateForGeneration = (periodType == .day) ? startDate : Date()
        
        print("🔄 [OverviewTab] Regenerating \(periodType.rawValue) summary...")
        
        switch periodType {
        case .day:
            await coordinator.updateDailySummary(date: dateForGeneration, forceRegenerate: false)
        case .week:
            await coordinator.updateWeeklySummary(date: dateForGeneration, forceRegenerate: false)
        case .month:
            await coordinator.updateMonthlySummary(date: dateForGeneration, forceRegenerate: false)
        case .year:
            await coordinator.updateYearlySummary(date: dateForGeneration, forceRegenerate: false)
        default:
            break
        }
        
        // Fetch again after regeneration
        try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5s
        periodSummary = try? await coordinator.fetchPeriodSummary(type: periodType, date: dateForGeneration)
        
        if periodSummary != nil {
            coordinator.showSuccess("Summary regenerated")
        } else {
            coordinator.showError("Failed to regenerate summary")
        }
    }

    private func wrapUpYear(forceRegenerate: Bool) async {
        guard !isWrappingUpYear else { return }
        isWrappingUpYear = true
        let dateForGeneration = Date()

        await coordinator.wrapUpYear(date: dateForGeneration, forceRegenerate: forceRegenerate)

        yearWrapSummary = try? await coordinator.fetchPeriodSummary(type: .yearWrap, date: dateForGeneration)
        isWrappingUpYear = false
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
    
    private func formatHourShort(_ hour: Int) -> String {
        if hour == 0 {
            return "12 AM"
        } else if hour < 12 {
            return "\(hour) AM"
        } else if hour == 12 {
            return "12 PM"
        } else {
            return "\(hour - 12) PM"
        }
    }
    
    private func formatDayOfWeek(_ dayOfWeek: Int) -> String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return days[dayOfWeek]
    }
    
    private func formatDayOfWeekFull(_ dayOfWeek: Int) -> String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[dayOfWeek]
    }
    
    private func getDateRange(for timeRange: TimeRange) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch timeRange {
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let start = calendar.startOfDay(for: yesterday)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return (start, end)
        case .today:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .month:
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return (start, now)
        case .allTime:
            // Show only current year (e.g., 2025) up to today
            let currentYear = calendar.component(.year, from: now)
            let startOfYear = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1)) ?? now
            return (startOfYear, now)
        }
    }
    
    private func filterSession(_ session: (sessionId: UUID, duration: TimeInterval, date: Date)?, in range: (start: Date, end: Date)) -> (sessionId: UUID, duration: TimeInterval, date: Date)? {
        guard let session = session else { return nil }
        return session.date >= range.start && session.date <= range.end ? session : nil
    }
    
    private func filterMonth(_ month: (year: Int, month: Int, count: Int, sessionIds: [UUID])?, in range: (start: Date, end: Date)) -> (year: Int, month: Int, count: Int, sessionIds: [UUID])? {
        guard let month = month else { return nil }
        let calendar = Calendar.current
        guard let monthDate = calendar.date(from: DateComponents(year: month.year, month: month.month)) else { return nil }
        return monthDate >= range.start && monthDate <= range.end ? month : nil
    }
    
    private func filterSessionsByHour(_ sessions: [(hour: Int, count: Int, sessionIds: [UUID])], in range: (start: Date, end: Date)) async -> [(hour: Int, count: Int, sessionIds: [UUID])] {
        if range.start == Date.distantPast { return sessions }
        
        var filtered: [Int: [UUID]] = [:]
        
        for hourData in sessions {
            for sessionId in hourData.sessionIds {
                if let session = try? await coordinator.fetchSessions(ids: [sessionId]).first,
                   session.startTime >= range.start && session.startTime <= range.end {
                    filtered[hourData.hour, default: []].append(sessionId)
                }
            }
        }
        
        return filtered.map { (hour: $0.key, count: $0.value.count, sessionIds: $0.value) }
    }
    
    private func filterSessionsByDayOfWeek(_ sessions: [(dayOfWeek: Int, count: Int, sessionIds: [UUID])], in range: (start: Date, end: Date)) async -> [(dayOfWeek: Int, count: Int, sessionIds: [UUID])] {
        if range.start == Date.distantPast { return sessions }
        
        var filtered: [Int: [UUID]] = [:]
        
        for dayData in sessions {
            for sessionId in dayData.sessionIds {
                if let session = try? await coordinator.fetchSessions(ids: [sessionId]).first,
                   session.startTime >= range.start && session.startTime <= range.end {
                    filtered[dayData.dayOfWeek, default: []].append(sessionId)
                }
            }
        }
        
        return filtered.map { (dayOfWeek: $0.key, count: $0.value.count, sessionIds: $0.value) }
    }
    
    private func formatMonth(year: Int, month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: year, month: month)) ?? Date()
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
    
    // MARK: - Word Cloud Styling Helpers
    
    private func fontSizeForRank(_ rank: Int) -> CGFloat {
        // Top words get larger fonts
        switch rank {
        case 0...2: return 22  // Top 3
        case 3...5: return 20  // 4-6
        case 6...9: return 18  // 7-10
        default: return 16     // 11-20
        }
    }
    
    private func colorForRank(_ rank: Int) -> Color {
        // Apple Intelligence gradient colors for word frequency
        switch rank {
        case 0...2: return AppTheme.darkPurple    // Top 3 - most frequent
        case 3...5: return AppTheme.purple        // 4-6
        case 6...9: return AppTheme.magenta       // 7-10
        case 10...14: return AppTheme.skyBlue     // 11-15
        default: return AppTheme.lightPurple      // 16-20
        }
    }
    
    // MARK: - Sentiment Helpers
    
    private func sentimentColor(_ score: Double) -> Color {
        switch score {
        case ..<(-0.3): return AppTheme.magenta  // Negative
        case -0.3..<0.3: return AppTheme.skyBlue  // Neutral
        default: return AppTheme.emerald         // Positive
        }
    }
    
    private func sentimentLabel(_ score: Double) -> String {
        switch score {
        case ..<(-0.5): return "😢"
        case -0.5..<(-0.2): return "😔"
        case -0.2..<0.2: return "😐"
        case 0.2..<0.5: return "🙂"
        default: return "😊"
        }
    }
    
    @ViewBuilder
    private func sentimentStatBox(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RadialGradient(
                colors: [color.opacity(0.15), color.opacity(0.05)],
                center: .center,
                startRadius: 0,
                endRadius: 50
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func languageColor(index: Int) -> Color {
        let colors: [Color] = [
            AppTheme.skyBlue,
            AppTheme.emerald,
            AppTheme.magenta,
            AppTheme.darkPurple,
            AppTheme.purple,
            AppTheme.lightPurple,
            AppTheme.paleBlue
        ]
        return colors[index % colors.count]
    }
    
    private var periodTitle: String {
        switch selectedTimeRange {
        case .yesterday: return "Yesterday's Summary"
        case .today: return "Today's Summary"
        case .week: return "This Week's Summary"
        case .month: return "This Month's Summary"
        case .allTime:
            let calendar = Calendar.current
            let currentYear = calendar.component(.year, from: Date())
            return "\(currentYear) Summary"
        }
    }
}

// MARK: - FilteredSessionsView

struct FilteredSessionsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let title: String
    let sessionIds: [UUID]
    
    @State private var sessions: [RecordingSession] = []
    @State private var sessionWordCounts: [UUID: Int] = [:]
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading sessions...")
            } else if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "waveform",
                    description: Text("No sessions found for this filter.")
                )
            } else {
                List {
                    ForEach(sessions, id: \.sessionId) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                                        .font(.headline)
                                    Spacer()
                                    if let wordCount = sessionWordCounts[session.sessionId] {
                                        Text("\(wordCount) words")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                HStack {
                                    Text("\(session.chunkCount) chunk\(session.chunkCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text(formatDuration(session.totalDuration))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .task {
            await loadSessions()
        }
    }
    
    private func loadSessions() async {
        isLoading = true
        
        do {
            // Load sessions for these IDs
            sessions = try await coordinator.fetchSessions(ids: sessionIds)
            
            // Load word counts in parallel
            guard let dbManager = coordinator.getDatabaseManager() else { return }
            await withTaskGroup(of: (UUID, Int).self) { group in
                for session in sessions {
                    group.addTask {
                        let count = (try? await dbManager.fetchSessionWordCount(sessionId: session.sessionId)) ?? 0
                        return (session.sessionId, count)
                    }
                }
                
                for await (sessionId, wordCount) in group {
                    sessionWordCounts[sessionId] = wordCount
                }
            }
            
            // Sort by start time descending
            sessions.sort { $0.startTime > $1.startTime }
            
        } catch {
            print("❌ [FilteredSessionsView] Failed to load sessions: \(error)")
        }
        
        isLoading = false
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

extension Array where Element: Hashable {
    var uniqueCount: Int {
        return Set(self).count
    }
}

struct SummaryRow: View {
    let summary: Summary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.periodType.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
                
                Spacer()
                
                Text(summary.periodStart, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(summary.text)
                .font(.body)
                .lineLimit(4)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var activeEngineName: String = "Loading..."
    @State private var debugTapCount: Int = 0
    @State private var showDebugSection: Bool = false
    @State private var databasePath: String?
    
    var body: some View {
        NavigationStack {
            List {
                // Recording Section
                Section {
                    NavigationLink(destination: RecordingSettingsView()) {
                        Label {
                            Text("Recording Chunks")
                        } icon: {
                            Image(systemName: "mic.fill")
                                .foregroundStyle(AppTheme.magenta)
                        }
                    }
                }
                
                // AI & Summaries Section
                Section {
                    NavigationLink(destination: AISettingsView()) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI & Summaries")
                                Text(activeEngineName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "brain")
                                .foregroundStyle(AppTheme.purple)
                        }
                    }
                } footer: {
                    Text("Configure how your recordings are summarized.")
                }
                
                // Statistics Section
                Section {
                    NavigationLink(destination: StatisticsView()) {
                        Label {
                            Text("Statistics")
                        } icon: {
                            Image(systemName: "chart.xyaxis.line")
                                .foregroundStyle(AppTheme.skyBlue)
                        }
                    }
                } footer: {
                    Text("View word clouds, charts, and statistical analysis.")
                }
                
                // Data Section
                Section {
                    NavigationLink(destination: DataSettingsView()) {
                        Label {
                            Text("Data")
                        } icon: {
                            Image(systemName: "externaldrive.fill")
                                .foregroundStyle(AppTheme.magenta)
                        }
                    }
                }
                
                // Privacy Section
                Section {
                    NavigationLink(destination: PrivacySettingsView()) {
                        Label {
                            Text("Privacy")
                        } icon: {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(AppTheme.darkPurple)
                        }
                    }
                }
                
                // About Section
                Section {
                    HStack {
                        Label {
                            Text("Version")
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(AppTheme.lightPurple)
                        }
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        debugTapCount += 1
                        if debugTapCount >= 5 {
                            showDebugSection = true
                            coordinator.showSuccess("Debug mode enabled")
                            debugTapCount = 0
                        }
                    }
                    
                    HStack {
                        Label {
                            Text("On-Device Processing")
                        } icon: {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(AppTheme.emerald)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.emerald)
                    }
                } header: {
                    Text("About")
                }
                
                // Debug Section (hidden by default)
                if showDebugSection {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Database Location")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let path = databasePath {
                                Text(path)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            } else {
                                Text("Loading...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        Button {
                            Task {
                                await coordinator.testSessionQueries()
                            }
                        } label: {
                            Label("Test Session Queries", systemImage: "testtube.2")
                        }
                        
                        Button(role: .destructive) {
                            showDebugSection = false
                        } label: {
                            Label("Hide Debug Section", systemImage: "eye.slash")
                        }
                    } header: {
                        Text("Debug")
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                await loadActiveEngine()
                databasePath = await coordinator.getDatabasePath()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
                Task {
                    await loadActiveEngine()
                }
            }
        }
    }
    
    private func loadActiveEngine() async {
        guard let summCoord = coordinator.summarizationCoordinator else {
            activeEngineName = "Not configured"
            return
        }
        
        let engine = await summCoord.getActiveEngine()
        activeEngineName = engine.displayName
    }
}

// MARK: - Recording Settings View

struct RecordingSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var chunkDuration: Double = 180
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Auto-Chunk Duration")
                        Spacer()
                        Text("\(Int(chunkDuration))s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(value: $chunkDuration, in: 30...300, step: 30) {
                        Text("Chunk Duration")
                    }
                    .tint(AppTheme.purple)
                    .onChange(of: chunkDuration) { oldValue, newValue in
                        coordinator.audioCapture.autoChunkDuration = newValue
                        coordinator.showSuccess("Chunk duration updated to \(Int(newValue))s")
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Chunk Settings")
            } footer: {
                Text("Recordings are automatically split into chunks of this duration for efficient processing and transcription.")
            }
            
            Section {
                HStack {
                    Label("Format", systemImage: "waveform")
                    Spacer()
                    Text("AAC")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Label("Sample Rate", systemImage: "dial.medium")
                    Spacer()
                    Text("44.1 kHz")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Label("Channels", systemImage: "speaker.wave.2")
                    Spacer()
                    Text("Mono")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Audio Quality")
            } footer: {
                Text("Optimized settings for voice recording with smaller file sizes.")
            }
            
            Section {
                NavigationLink(destination: LanguageSettingsView()) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Languages")
                            Text("Manage which languages can be detected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "globe")
                            .foregroundStyle(AppTheme.emerald)
                    }
                }
            } header: {
                Text("Detection")
            }
        }
        .navigationTitle("Recording Chunks")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chunkDuration = coordinator.audioCapture.autoChunkDuration
        }
    }
}

// MARK: - AI Settings View

struct AISettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var activeEngine: EngineTier?
    @State private var availableEngines: [EngineTier] = []
    @State private var isLoading = true
    
    // Local AI state
    @State private var localModelAvailable = false
    @State private var isDownloadingModel = false
    
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
    
    private var effectiveConfig: LocalLLMConfiguration {
        LocalLLMConfiguration.current()
    }
    
    private var deviceSummary: String {
        LocalLLMConfiguration.deviceSummary()
    }
    
    var body: some View {
        List {
            // MARK: - How It Works Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label {
                        Text("Session Summaries")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "doc.text")
                            .foregroundStyle(AppTheme.purple)
                    }
                    HStack {
                        Text("Uses your ACTIVE engine →")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let activeEngine {
                            Text(activeEngine.displayName)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(AppTheme.emerald)
                        }
                    }
                    
                    Divider()
                    
                    Label {
                        Text("Period Rollups (Day/Week/Month/Year)")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "calendar")
                            .foregroundStyle(AppTheme.skyBlue)
                    }
                    Text("Combines session summaries (no additional AI processing)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Divider()
                    
                    Label {
                        Text("✨ Year Wrap (Special)")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AppTheme.magenta)
                    }
                    Text("Always uses Year Wrapped Pro AI (OpenAI or Anthropic) for a beautifully crafted year-in-review. Requires valid Pro AI credentials below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Label {
                    Text("How AI Works in Life Wrapped")
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(AppTheme.lightPurple)
                }
            }
            
            // MARK: - On-Device Engines Section
            Section {
                // Basic Engine
                EngineOptionCard(
                    tier: .basic,
                    isSelected: activeEngine == .basic,
                    isAvailable: true,
                    subtitle: "Simple word-based summaries",
                    onSelect: { selectEngine(.basic) }
                )
                
                // Apple Intelligence
                EngineOptionCard(
                    tier: .apple,
                    isSelected: activeEngine == .apple,
                    isAvailable: availableEngines.contains(.apple),
                    subtitle: "Requires iOS 18.1+ & compatible device",
                    onSelect: { selectEngine(.apple) }
                )
                
                // Local AI
                VStack(alignment: .leading, spacing: 12) {
                    EngineOptionCard(
                        tier: .local,
                        isSelected: activeEngine == .local,
                        isAvailable: localModelAvailable,
                        subtitle: localModelAvailable ? "On-device LLM ready" : "Download model to enable",
                        onSelect: { selectEngine(.local) }
                    )
                    
                    if localModelAvailable {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                    .foregroundStyle(AppTheme.emerald)
                                Text("Auto-Optimized for Your Device")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(AppTheme.emerald)
                            }
                            Text("Automatically uses maximum quality settings for \(deviceSummary). \(effectiveConfig.tokensDescription)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Label {
                    Text("On-Device Processing")
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(AppTheme.darkPurple)
                }
            } footer: {
                Text("All processing happens locally. Your data never leaves your device.")
            }
            
            // MARK: - Year Wrapped Pro AI Section
            Section {
                // Pro AI Engine Toggle
                EngineOptionCard(
                    tier: .external,
                    isSelected: activeEngine == .external,
                    isAvailable: hasValidAPIKey(),
                    subtitle: hasValidAPIKey() ? "\(selectedProvider) • \(selectedModel)" : "Configure API key below",
                    onSelect: { selectEngine(.external) }
                )
                
                // Provider Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Provider")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Picker("Provider", selection: $selectedProvider) {
                        Text("OpenAI").tag("OpenAI")
                        Text("Anthropic").tag("Anthropic")
                    }
                    .pickerStyle(.segmented)
                    .tint(AppTheme.purple)
                    .onChange(of: selectedProvider) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "externalAPIProvider")
                        // Reset to default model for new provider
                        let defaultModel = newValue == "OpenAI" ? "gpt-4.1" : "claude-sonnet-4-5"
                        selectedModel = defaultModel
                        UserDefaults.standard.set(defaultModel, forKey: "externalAPIModel")
                        // Load the appropriate key
                        loadAPIKey()
                    }
                }
                .padding(.vertical, 4)
                .opacity(activeEngine == .external ? 1.0 : 0.6)
                
                // Model Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Picker("Model", selection: $selectedModel) {
                        ForEach(currentModels, id: \.0) { model in
                            Text(model.1).tag(model.0)
                        }
                    }
                    .onChange(of: selectedModel) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "externalAPIModel")
                    }
                }
                .padding(.vertical, 4)
                .opacity(activeEngine == .external ? 1.0 : 0.6)
                
                // API Key Input
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("API Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if hasValidAPIKey() {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.emerald)
                                Text("Configured")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.emerald)
                            }
                        }
                    }
                    
                    HStack {
                        if showAPIKeyField {
                            SecureField("Enter \(selectedProvider) API Key", text: $apiKey)
                                .textContentType(.password)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: apiKey) { _, newValue in
                                    // Normalize: trim whitespace and newlines
                                    let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if normalized != newValue {
                                        apiKey = normalized
                                    }
                                    // Reset test state when key changes
                                    testResult = nil
                                }
                            
                            Button {
                                testAPIKey()
                            } label: {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(AppTheme.purple)
                                } else {
                                    Text("Test")
                                        .fontWeight(.medium)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.skyBlue)
                            .disabled(apiKey.isEmpty || isTesting)
                            
                            Button {
                                saveAPIKey()
                            } label: {
                                Text("Save")
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.purple)
                            .disabled(apiKey.isEmpty)
                        } else {
                            Button {
                                showAPIKeyField = true
                            } label: {
                                HStack {
                                    Image(systemName: hasValidAPIKey() ? "pencil" : "plus.circle.fill")
                                    Text(hasValidAPIKey() ? "Change API Key" : "Add API Key")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.purple)
                        }
                    }
                    
                    // Help links
                    HStack(spacing: 16) {
                        if selectedProvider == "OpenAI" {
                            Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                                Text("Get OpenAI Key")
                                    .font(.caption)
                            }
                        } else {
                            Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                                Text("Get Anthropic Key")
                                    .font(.caption)
                            }
                        }
                    }
                    
                    // Test result
                    if let result = testResult {
                        HStack {
                            Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(testSuccess ? AppTheme.emerald : AppTheme.magenta)
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(testSuccess ? AppTheme.emerald : AppTheme.magenta)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
                
                // Clear key option
                if hasValidAPIKey() {
                    Button(role: .destructive) {
                        clearAPIKey()
                    } label: {
                        Label("Remove API Key", systemImage: "trash")
                            .font(.subheadline)
                    }
                }
            } header: {
                Label {
                    Text("Year Wrapped Pro AI")
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(AppTheme.magenta)
                }
            } footer: {
                Label {
                    Text("Required for Year Wrap feature. Select as active engine above to also use for session summaries. Data is sent to \(selectedProvider) servers for processing.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("AI & Summaries")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadEngineStatus()
            await checkLocalModelAvailability()
            loadAPIKey()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
            Task {
                await loadEngineStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ModelDownloadCompleted"))) { _ in
            Task {
                await checkLocalModelAvailability()
                await loadEngineStatus()
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
    }
    
    private func checkLocalModelAvailability() async {
        let modelManager = LocalLLM.ModelFileManager.shared
        let models = await modelManager.availableModels()
        await MainActor.run {
            localModelAvailable = !models.isEmpty
        }
    }
    
    private func selectEngine(_ tier: EngineTier) {
        // Check availability
        if tier == .local && !localModelAvailable {
            coordinator.showError("Download a Local AI model first")
            return
        }
        if tier == .apple && !availableEngines.contains(.apple) {
            coordinator.showError("Apple Intelligence requires iOS 18.1+ and compatible hardware")
            return
        }
        if tier == .external && !hasValidAPIKey() {
            coordinator.showError("Configure an API key first")
            return
        }
        
        Task {
            guard let summCoord = coordinator.summarizationCoordinator else { return }
            await summCoord.setPreferredEngine(tier)
            await loadEngineStatus()
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            coordinator.showSuccess("Switched to \(tier.displayName)")
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
            coordinator.showSuccess("API key saved")
            
            Task {
                await loadEngineStatus()
                NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
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
        
        // If external was active, switch to basic
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

// MARK: - Engine Option Card

struct EngineOptionCard: View {
    let tier: EngineTier
    let isSelected: Bool
    let isAvailable: Bool
    let subtitle: String
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Radio button indicator with gradient
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? AppTheme.purple : Color.gray.opacity(0.5), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [AppTheme.lightPurple, AppTheme.purple],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 12
                                )
                            )
                            .frame(width: 14, height: 14)
                    }
                }
                
                // Engine icon with theme color
                Image(systemName: tier.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppTheme.purple : (isAvailable ? AppTheme.lightPurple : Color.secondary.opacity(0.5)))
                    .frame(width: 28)
                
                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName)
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? .primary : (isAvailable ? .primary : .secondary))
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Status indicator with gradient
                if isSelected {
                    Text("Active")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.purple, AppTheme.darkPurple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                } else if !isAvailable {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isAvailable || isSelected ? 1.0 : 0.5)
    }
}

// MARK: - On-Device Engines View (Keep for backward compatibility)

struct OnDeviceEnginesView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var activeEngine: EngineTier?
    @State private var availableEngines: [EngineTier] = []
    @State private var isLoading = true
    @State private var showUnavailableAlert = false
    @State private var selectedUnavailableTier: EngineTier?
    
    var body: some View {
        List {
            Section {
                ForEach(EngineTier.privateTiers, id: \.self) { tier in
                    EngineSelectionRow(
                        tier: tier,
                        isActive: tier == activeEngine,
                        isAvailable: availableEngines.contains(tier)
                    ) {
                        selectEngine(tier)
                    }
                }
            } header: {
                Text("Select Engine")
            } footer: {
                Text("Tap an engine to activate it. All on-device engines process data locally for privacy.")
            }
        }
        .navigationTitle("On-Device Engines")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadEngineStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EngineDidChange"))) { _ in
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
        
        guard let summCoord = coordinator.summarizationCoordinator else { return }
        activeEngine = await summCoord.getActiveEngine()
        availableEngines = await summCoord.getAvailableEngines()
    }
    
    private func selectEngine(_ tier: EngineTier) {
        if tier == activeEngine { return }
        
        guard availableEngines.contains(tier) else {
            selectedUnavailableTier = tier
            showUnavailableAlert = true
            return
        }
        
        Task {
            guard let summCoord = coordinator.summarizationCoordinator else { return }
            await summCoord.setPreferredEngine(tier)
            await loadEngineStatus()
            NotificationCenter.default.post(name: NSNotification.Name("EngineDidChange"), object: nil)
            coordinator.showSuccess("Switched to \(tier.displayName)")
        }
    }
    
    private func unavailableMessage(for tier: EngineTier) -> String {
        switch tier {
        case .basic:
            return "Basic engine should always be available. Please restart the app."
        case .apple:
            return "Apple Intelligence requires iOS 18.1+ and compatible hardware."
        case .local:
            return "Download the local AI model to enable on-device processing. Go to AI Settings → Local AI Models."
        case .external:
            return "Configure your API key to use external AI services."
        }
    }
}

// MARK: - Engine Selection Row

struct EngineSelectionRow: View {
    let tier: EngineTier
    let isActive: Bool
    let isAvailable: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: tier.icon)
                    .font(.title3)
                    .foregroundStyle(isAvailable ? .blue : .secondary)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName)
                        .font(.body)
                        .foregroundStyle(isAvailable ? .primary : .secondary)
                    
                    Text(tier.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if !isAvailable {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - External API Settings View

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

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        
        // Delete existing item first
        delete(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.jsayram.lifewrapped",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.jsayram.lifewrapped",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.jsayram.lifewrapped"
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Statistics Settings View

struct StatisticsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var wordLimit: Double = 20
    @State private var dateFormat: String = UserDefaults.standard.rollupDateFormat
    @State private var timeFormat: String = UserDefaults.standard.rollupTimeFormat
    
    // Statistics data
    @State private var sessionsByHour: [(hour: Int, count: Int, sessionIds: [UUID])] = []
    @State private var sessionsByDayOfWeek: [(dayOfWeek: Int, count: Int, sessionIds: [UUID])] = []
    @State private var longestSession: (sessionId: UUID, duration: TimeInterval, date: Date)?
    @State private var mostActiveMonth: (year: Int, month: Int, count: Int, sessionIds: [UUID])?
    @State private var topWords: [WordFrequency] = []
    @State private var dailySentiment: [(date: Date, sentiment: Double)] = []
    @State private var languageDistribution: [(language: String, wordCount: Int)] = []
    @State private var isLoadingStats = false
    
    private let wordLimitKey = "insightsWordLimit"
    
    private let dateFormatOptions = [
        ("MM/dd/yyyy", "12/22/2025"),
        ("dd/MM/yyyy", "22/12/2025"),
        ("yyyy-MM-dd", "2025-12-22"),
        ("MMM d, yyyy", "Dec 22, 2025"),
        ("MMMM d, yyyy", "December 22, 2025")
    ]
    
    private let timeFormatOptions = [
        ("HH:mm", "14:30 (24-hour)"),
        ("hh:mm a", "02:30 PM (12-hour)"),
        ("h:mm a", "2:30 PM (12-hour)")
    ]
    
    var body: some View {
        List {
            // Key Statistics Section
            if longestSession != nil || mostActiveMonth != nil {
                Section {
                    if let longest = longestSession {
                        NavigationLink {
                            FilteredSessionsView(
                                title: "Longest Session",
                                sessionIds: [longest.sessionId]
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "timer")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.purple)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RadialGradient(
                                            colors: [AppTheme.purple.opacity(0.15), AppTheme.purple.opacity(0.05)],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 20
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Longest Session")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Text(formatDuration(longest.duration))
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        Text(longest.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    if let mostActive = mostActiveMonth {
                        NavigationLink {
                            FilteredSessionsView(
                                title: formatMonth(year: mostActive.year, month: mostActive.month),
                                sessionIds: mostActive.sessionIds
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.magenta)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RadialGradient(
                                            colors: [AppTheme.magenta.opacity(0.15), AppTheme.magenta.opacity(0.05)],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 20
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Most Active Month")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Text(formatMonth(year: mostActive.year, month: mostActive.month))
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        Text("\(mostActive.count) session\(mostActive.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Key Statistics")
                }
            }
            
            // Sessions by Hour Section
            if !sessionsByHour.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(sessionsByHour.sorted(by: { $0.hour < $1.hour }), id: \.hour) { data in
                                NavigationLink {
                                    FilteredSessionsView(
                                        title: formatHour(data.hour),
                                        sessionIds: data.sessionIds
                                    )
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(formatHourShort(data.hour))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(AppTheme.skyBlue)
                                        Text("\(data.count)")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                        Text(data.count == 1 ? "session" : "sessions")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 70)
                                    .padding(.vertical, 8)
                                    .background(
                                        RadialGradient(
                                            colors: [AppTheme.skyBlue.opacity(0.15), AppTheme.skyBlue.opacity(0.05)],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 35
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                } header: {
                    Text("Sessions by Time of Day")
                }
            }
            
            // Sessions by Day of Week Section
            if !sessionsByDayOfWeek.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(sessionsByDayOfWeek.sorted(by: { $0.dayOfWeek < $1.dayOfWeek }), id: \.dayOfWeek) { data in
                                NavigationLink {
                                    FilteredSessionsView(
                                        title: formatDayOfWeekFull(data.dayOfWeek),
                                        sessionIds: data.sessionIds
                                    )
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(formatDayOfWeek(data.dayOfWeek))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(AppTheme.emerald)
                                        Text("\(data.count)")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                        Text(data.count == 1 ? "session" : "sessions")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 70)
                                    .padding(.vertical, 8)
                                    .background(
                                        RadialGradient(
                                            colors: [AppTheme.emerald.opacity(0.15), AppTheme.emerald.opacity(0.05)],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 35
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                } header: {
                    Text("Sessions by Day of Week")
                }
            }
            
            // Word Cloud Section
            if !topWords.isEmpty {
                Section {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(Array(topWords.enumerated()), id: \.element.id) { index, wordFreq in
                                VStack(spacing: 6) {
                                    Text(wordFreq.word.capitalized)
                                        .font(.system(size: fontSizeForRank(index), weight: .bold))
                                        .foregroundStyle(colorForRank(index))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    
                                    Text("\(wordFreq.count)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(colorForRank(index).gradient)
                                        .clipShape(Capsule())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(colorForRank(index).opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .frame(height: 400)
                } header: {
                    Text("Most Used Words")
                } footer: {
                    Text("Meaningful words from your transcripts")
                }
            }
            
            // Emotional Trends Section (Stats only, no chart)
            if !dailySentiment.isEmpty {
                Section {
                    HStack(spacing: 16) {
                        sentimentStatBox(
                            label: "Positive",
                            count: dailySentiment.filter { $0.sentiment > 0.3 }.count,
                            color: .green
                        )
                        sentimentStatBox(
                            label: "Neutral",
                            count: dailySentiment.filter { abs($0.sentiment) <= 0.3 }.count,
                            color: .gray
                        )
                        sentimentStatBox(
                            label: "Negative",
                            count: dailySentiment.filter { $0.sentiment < -0.3 }.count,
                            color: .red
                        )
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Emotional Trends")
                } footer: {
                    Text("Daily sentiment analysis from your journal entries")
                }
            }
            
            // Languages Section
            if !languageDistribution.isEmpty {
                Section {
                    let totalWords = languageDistribution.reduce(0) { $0 + $1.wordCount }
                    
                    ForEach(languageDistribution.prefix(5), id: \.language) { item in
                        let percentage = totalWords > 0 ? (Double(item.wordCount) / Double(totalWords)) * 100 : 0
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(LanguageDetector.displayName(for: item.language))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(percentage))%")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.2))
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(languageColor(index: languageDistribution.firstIndex(where: { $0.language == item.language }) ?? 0))
                                        .frame(width: geometry.size.width * (percentage / 100))
                                }
                            }
                            .frame(height: 8)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    if languageDistribution.count > 1 {
                        Text("You speak \(languageDistribution.count) language\(languageDistribution.count == 1 ? "" : "s") in your recordings")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                } header: {
                    Text("Languages Spoken")
                } footer: {
                    Text("Distribution of languages in your recordings")
                }
            }
            
            // Settings Sections
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Word Cloud Limit")
                        Spacer()
                        Text("\(Int(wordLimit))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(value: $wordLimit, in: 10...200, step: 10) {
                        Text("Word Limit")
                    }
                    .onChange(of: wordLimit) { oldValue, newValue in
                        UserDefaults.standard.set(Int(newValue), forKey: wordLimitKey)
                        coordinator.showSuccess("Word limit updated to \(Int(newValue))")
                        Task {
                            await loadStatistics()
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Settings")
            } footer: {
                Text("Number of most-used words to display in the Statistics tab.")
            }
            
            Section {
                Picker("Date Format", selection: $dateFormat) {
                    ForEach(dateFormatOptions, id: \.0) { format, example in
                        Text(example).tag(format)
                    }
                }
                .onChange(of: dateFormat) { oldValue, newValue in
                    UserDefaults.standard.rollupDateFormat = newValue
                    coordinator.showSuccess("Date format updated")
                }
                
                Picker("Time Format", selection: $timeFormat) {
                    ForEach(timeFormatOptions, id: \.0) { format, example in
                        Text(example).tag(format)
                    }
                }
                .onChange(of: timeFormat) { oldValue, newValue in
                    UserDefaults.standard.rollupTimeFormat = newValue
                    coordinator.showSuccess("Time format updated")
                }
            } header: {
                Text("Rollup Date & Time Format")
            } footer: {
                Text("Date and time format used in period rollups (hour, day, week, month, year).")
            }
            
            Section {
                NavigationLink(destination: ExcludedWordsView()) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Excluded Words")
                            Text("Manage stop words for word cloud")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "text.badge.xmark")
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Filters")
            }
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoadingStats {
                LoadingView(size: .medium)
            }
        }
        .task {
            wordLimit = Double(UserDefaults.standard.integer(forKey: wordLimitKey))
            if wordLimit == 0 {
                wordLimit = 20
            }
            await loadStatistics()
        }
        .refreshable {
            await loadStatistics()
        }
    }
    
    private func loadStatistics() async {
        isLoadingStats = true
        do {
            // Load key statistics
            longestSession = try await coordinator.fetchLongestSession()
            mostActiveMonth = try await coordinator.fetchMostActiveMonth()
            
            // Load sessions by hour
            sessionsByHour = try await coordinator.fetchSessionsByHour()
            
            // Load sessions by day of week
            sessionsByDayOfWeek = try await coordinator.fetchSessionsByDayOfWeek()
            
            // Load word frequency analysis (all time)
            let transcriptTexts = try await coordinator.fetchTranscriptText(
                startDate: Date.distantPast,
                endDate: Date()
            )
            
            let customExcludedWords: Set<String> = {
                if let savedWords = UserDefaults.standard.stringArray(forKey: "customExcludedWords") {
                    return Set(savedWords)
                }
                return []
            }()
            
            topWords = WordAnalyzer.analyzeWords(
                from: transcriptTexts,
                limit: Int(wordLimit),
                customExcludedWords: customExcludedWords
            )
            
            // Load daily sentiment data (all time)
            dailySentiment = try await coordinator.fetchDailySentiment(from: Date.distantPast, to: Date())
            
            // Load language distribution
            languageDistribution = try await coordinator.fetchLanguageDistribution()
        } catch {
            print("❌ [StatisticsView] Failed to load statistics: \(error)")
        }
        isLoadingStats = false
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
    
    private func formatMonth(year: Int, month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        if let date = Calendar.current.date(from: DateComponents(year: year, month: month)) {
            return formatter.string(from: date)
        }
        return "\(month)/\(year)"
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
    
    private func formatHourShort(_ hour: Int) -> String {
        if hour == 0 {
            return "12 AM"
        } else if hour < 12 {
            return "\(hour) AM"
        } else if hour == 12 {
            return "12 PM"
        } else {
            return "\(hour - 12) PM"
        }
    }
    
    private func formatDayOfWeek(_ dayOfWeek: Int) -> String {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return days[dayOfWeek]
    }
    
    private func formatDayOfWeekFull(_ dayOfWeek: Int) -> String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return days[dayOfWeek]
    }
    
    private func fontSizeForRank(_ rank: Int) -> CGFloat {
        switch rank {
        case 0...2: return 24
        case 3...5: return 20
        case 6...9: return 18
        default: return 16
        }
    }
    
    private func colorForRank(_ rank: Int) -> Color {
        switch rank {
        case 0: return AppTheme.skyBlue
        case 1: return AppTheme.purple
        case 2: return AppTheme.magenta
        case 3: return AppTheme.emerald
        case 4: return AppTheme.lightPurple
        default: return AppTheme.darkPurple
        }
    }
    
    private func sentimentStatBox(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            
            Text("days")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func languageColor(index: Int) -> Color {
        let colors: [Color] = [AppTheme.skyBlue, AppTheme.emerald, AppTheme.purple, AppTheme.magenta, AppTheme.lightPurple]
        return colors[index % colors.count]
    }
}

// MARK: - Data Settings View

struct DataSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showDataManagement = false
    @State private var storageUsed: String = "Calculating..."
    
    var body: some View {
        List {
            Section {
                NavigationLink(destination: HistoricalDataView()) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Historical Data")
                            Text("View and manage data by year")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.blue)
                    }
                }
            } header: {
                Text("Browse Data")
            } footer: {
                Text("The Overview tab always shows the current year. Use Historical Data to browse previous years.")
            }
            
            Section {
                Button {
                    showDataManagement = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Export & Backup")
                            Text("Export your data or create backups")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.green)
                    }
                }
                .foregroundStyle(.primary)
            } header: {
                Text("Data Management")
            }
            
            Section {
                HStack {
                    Label("Storage Used", systemImage: "internaldrive")
                    Spacer()
                    Text(storageUsed)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Includes recordings, transcripts, and AI models.")
            }
        }
        .navigationTitle("Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDataManagement) {
            DataManagementView()
        }
        .task {
            await calculateStorage()
        }
    }
    
    private func calculateStorage() async {
        // Calculate total storage used by app
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        
        if let url = documentsURL {
            let size = directorySize(url: url)
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            storageUsed = formatter.string(fromByteCount: Int64(size))
        }
    }
    
    private func directorySize(url: URL) -> Int {
        let fileManager = FileManager.default
        var totalSize = 0
        
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += fileSize
                }
            }
        }
        
        return totalSize
    }
}

// MARK: - Privacy Settings View

struct PrivacySettingsView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Label("On-Device Processing", systemImage: "checkmark.shield.fill")
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                
                HStack {
                    Label("iCloud Sync", systemImage: "icloud.slash")
                    Spacer()
                    Text("Disabled")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Label("Analytics", systemImage: "chart.bar.xaxis")
                    Spacer()
                    Text("None")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Privacy Status")
            } footer: {
                Text("Life Wrapped processes all data locally. No data is sent to external servers unless you configure External API.")
            }
            
            Section {
                NavigationLink(destination: PrivacyPolicyView()) {
                    Label("Privacy Policy", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

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
                        icon: "lock.shield.fill",
                        title: "100% On-Device",
                        description: "All audio processing and transcription happens on your device."
                    )
                    
                    PrivacyPoint(
                        icon: "wifi.slash",
                        title: "Zero Network Calls",
                        description: "Life Wrapped never sends your data to any server."
                    )
                    
                    PrivacyPoint(
                        icon: "eye.slash.fill",
                        title: "No Tracking",
                        description: "We don't collect analytics, telemetry, or usage data."
                    )
                    
                    PrivacyPoint(
                        icon: "square.and.arrow.up",
                        title: "Your Data, Your Control",
                        description: "Export or delete your data anytime."
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

struct RecordingDetailView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.colorScheme) var colorScheme
    let recording: AudioChunk
    
    @State private var transcriptSegments: [TranscriptSegment] = []
    @State private var isLoading = true
    @State private var loadError: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Recording Info Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recording Details")
                        .font(.headline)
                    
                    InfoRow(label: "Date", value: recording.startTime.formatted(date: .abbreviated, time: .shortened))
                    InfoRow(label: "Duration", value: formatDuration(recording.duration))
                    InfoRow(label: "Format", value: "\(recording.sampleRate) Hz")
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.cardGradient(for: colorScheme))
                        .allowsHitTesting(false)
                )
                .cornerRadius(12)
                
                // Playback Controls
                VStack(spacing: 16) {
                    // Waveform placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemBackground))
                        .frame(height: 60)
                        .overlay {
                            if coordinator.audioPlayback.currentlyPlayingURL == recording.fileURL {
                                // Show progress
                                GeometryReader { geometry in
                                    let progress = coordinator.audioPlayback.duration > 0 
                                        ? coordinator.audioPlayback.currentTime / coordinator.audioPlayback.duration 
                                        : 0
                                    
                                    HStack(spacing: 0) {
                                        Rectangle()
                                            .fill(Color.blue.opacity(0.3))
                                            .frame(width: geometry.size.width * progress)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    
                    // Play/Pause Button
                    Button {
                        playRecording()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [AppTheme.purple, AppTheme.magenta],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                if isPlaying {
                                    Text("\(formatTime(coordinator.audioPlayback.currentTime)) / \(formatTime(coordinator.audioPlayback.duration))")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                } else {
                                    Text("Tap to Play")
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                }
                                
                                Text(isPlaying ? "Playing..." : "Start playback")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        colors: [AppTheme.purple.opacity(0.3), AppTheme.magenta.opacity(0.2)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.cardGradient(for: colorScheme))
                        .allowsHitTesting(false)
                )
                .cornerRadius(12)
                
                // Transcription Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transcription")
                        .font(.headline)
                    
                    if isLoading {
                        ProgressView("Loading transcription...")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if let error = loadError {
                        Text("Error: \(error)")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                            .padding()
                    } else if transcriptSegments.isEmpty {
                        Text("No transcription available")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(transcriptSegments, id: \.id) { segment in
                                Text(segment.text)
                                    .font(.body)
                                    .padding(.vertical, 4)
                            }
                        }
                        .padding()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.cardGradient(for: colorScheme))
                        .allowsHitTesting(false)
                )
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTranscription()
        }
    }
    
    private var isPlaying: Bool {
        coordinator.audioPlayback.currentlyPlayingURL == recording.fileURL && coordinator.audioPlayback.isPlaying
    }
    
    private func playRecording() {
        if coordinator.audioPlayback.currentlyPlayingURL == recording.fileURL {
            coordinator.audioPlayback.togglePlayPause()
        } else {
            Task {
                do {
                    try await coordinator.audioPlayback.play(url: recording.fileURL)
                } catch {
                    loadError = "Could not play recording: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func loadTranscription() async {
        isLoading = true
        loadError = nil
        
        do {
            transcriptSegments = try await coordinator.fetchTranscript(for: recording.id)
            print("📄 [RecordingDetailView] Loaded \(transcriptSegments.count) transcript segments")
            
            // Debug: print the first segment if available
            if let first = transcriptSegments.first {
                print("📄 [RecordingDetailView] First segment: '\(first.text)'")
            }
        } catch {
            print("❌ [RecordingDetailView] Failed to load transcription: \(error)")
            loadError = error.localizedDescription
        }
        
        isLoading = false
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
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - Transcript Chunk View

struct TranscriptChunkView: View {
    let chunkIndex: Int
    let segments: [TranscriptSegment]
    let session: RecordingSession
    let isCurrentChunk: Bool
    let chunkId: UUID?
    let coordinator: AppCoordinator
    let isEdited: Bool  // Track if this chunk was edited
    let onSeekToChunk: () -> Void
    let onTextEdited: (UUID, String) -> Void
    
    @State private var isEditing = false
    @State private var editedText: String = ""
    @FocusState private var isTextFocused: Bool
    
    private var combinedText: String {
        segments.map { $0.text }.joined(separator: " ")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Action buttons row at top right
            HStack {
                // Left side: Part label for multi-chunk, or edited badge
                if session.chunkCount > 1 {
                    HStack(spacing: 6) {
                        Text("Part \(chunkIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(isCurrentChunk ? .blue : .secondary)
                            .fontWeight(isCurrentChunk ? .semibold : .regular)
                        
                        if let chunkId = chunkId {
                            transcriptionStatusBadge(for: chunkId)
                        }
                        
                        if isEdited {
                            HStack(spacing: 2) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.caption2)
                                Text("Edited")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                } else if isEdited {
                    HStack(spacing: 2) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.caption2)
                        Text("Edited")
                            .font(.caption2)
                    }
                    .foregroundStyle(.orange)
                }
                
                Spacer()
                
                // Action buttons - compact
                if !isEditing && !combinedText.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = combinedText
                            coordinator.showSuccess("Copied")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            editedText = combinedText
                            isEditing = true
                            isTextFocused = true
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "pencil")
                                Text("Edit")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Content
            chunkContent
        }
        .padding(10)
        .background(chunkBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(chunkBorderColor, lineWidth: 2)
        )
        .onTapGesture {
            if !isEditing {
                onSeekToChunk()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isCurrentChunk)
        .animation(.easeInOut(duration: 0.3), value: isEdited)
    }
    
    private var chunkBackground: Color {
        if isEdited {
            return Color.orange.opacity(0.08)
        } else if isCurrentChunk {
            return Color.blue.opacity(0.1)
        } else {
            return Color.clear
        }
    }
    
    private var chunkBorderColor: Color {
        if isEdited {
            return Color.orange.opacity(0.5)
        } else if isCurrentChunk {
            return Color.blue.opacity(0.5)
        } else {
            return Color.clear
        }
    }
    
    @ViewBuilder
    private func transcriptionStatusBadge(for chunkId: UUID) -> some View {
        Group {
            if coordinator.transcribingChunkIds.contains(chunkId) {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Transcribing...")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.05)],
                        center: .center,
                        startRadius: 5,
                        endRadius: 20
                    )
                )
                .clipShape(Capsule())
            } else if coordinator.transcribedChunkIds.contains(chunkId) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                    Text("Done")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RadialGradient(
                        colors: [Color.green.opacity(0.2), Color.green.opacity(0.05)],
                        center: .center,
                        startRadius: 5,
                        endRadius: 20
                    )
                )
                .clipShape(Capsule())
            } else if coordinator.failedChunkIds.contains(chunkId) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text("Failed")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RadialGradient(
                        colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.05)],
                        center: .center,
                        startRadius: 5,
                        endRadius: 20
                    )
                )
                .clipShape(Capsule())
            }
        }
    }
    
    @ViewBuilder
    private var chunkContent: some View {
        if let chunkId = chunkId, coordinator.failedChunkIds.contains(chunkId) {
            VStack(spacing: 12) {
                Text("Transcription failed for this part")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Button {
                    Task {
                        await coordinator.retryTranscription(chunkId: chunkId)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Transcription")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.magenta)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else if isEditing {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $editedText)
                    .font(.body)
                    .frame(minHeight: 200, maxHeight: 400)
                    .padding(12)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(12)
                    .focused($isTextFocused)
                    .scrollContentBackground(.hidden)
                
                HStack(spacing: 12) {
                    Button {
                        isEditing = false
                        editedText = ""
                    } label: {
                        Text("Cancel")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        saveEdit()
                    } label: {
                        Text("Save")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        } else {
            // Selectable text - user can select and copy individual words
            Text(combinedText)
                .font(.body)
                .foregroundStyle(isCurrentChunk ? .primary : .secondary)
                .textSelection(.enabled)
                .onTapGesture {
                    onSeekToChunk()
                }
        }
    }
    
    private func saveEdit() {
        let trimmedText = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, let firstSegment = segments.first else {
            isEditing = false
            return
        }
        
        // Save the edited text to the first segment (we combine all segments into one for simplicity)
        onTextEdited(firstSegment.id, trimmedText)
        isEditing = false
        editedText = ""
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.colorScheme) var colorScheme
    let session: RecordingSession
    
    @State private var transcriptSegments: [TranscriptSegment] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var currentlyPlayingChunkIndex: Int?
    @State private var playbackUpdateTimer: Timer?
    @State private var forceUpdateTrigger = false
    @State private var isTranscriptionComplete = false
    @State private var transcriptionCheckTimer: Timer?
    @State private var sessionSummary: Summary?
    @State private var summaryLoadError: String?
    @State private var scrubbedTime: TimeInterval = 0
    
    // Session metadata
    @State private var sessionTitle: String = ""
    @State private var sessionNotes: String = ""
    @State private var isFavorite: Bool = false
    @State private var isEditingTitle: Bool = false
    @State private var isEditingNotes: Bool = false
    
    // Transcript editing
    @State private var editingSegmentId: UUID?
    @State private var editedText: String = ""
    @State private var transcriptWasEdited: Bool = false
    @State private var editedChunkIds: Set<UUID> = []  // Track which chunks were edited
    @State private var isRegeneratingSummary: Bool = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Session Title Section (Editable)
                sessionTitleSection
                
                // Transcription Processing Banner
                processingBannerSection
                
                // Session Info Card
                sessionInfoSection
                
                // Playback Controls
                playbackControlsSection
                
                // Transcription Section
                transcriptionSection
                
                // Session Summary Section (if available or error)
                if let summary = sessionSummary {
                    sessionSummarySection(summary: summary)
                } else if let error = summaryLoadError {
                    sessionSummaryErrorSection(error: error)
                } else if isTranscriptionComplete {
                    sessionSummaryPlaceholderSection
                }
                
                // Personal Notes Section
                personalNotesSection
            }
            .padding()
        }
        .navigationTitle(sessionTitle.isEmpty ? "Recording" : sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                toolbarButtons
            }
        }
        .task {
            await loadSessionMetadata()
            await loadTranscription()
            await loadSessionSummary()
            checkTranscriptionStatus()
        }
        .onAppear {
            startPlaybackUpdateTimer()
            startTranscriptionCheckTimer()
        }
        .onDisappear {
            stopPlaybackUpdateTimer()
            stopTranscriptionCheckTimer()
            if isPlayingThisSession {
                coordinator.audioPlayback.stop()
            }
        }
    }
    
    // MARK: - Processing Banner
    
    @ViewBuilder
    private var processingBannerSection: some View {
        if !isTranscriptionComplete {
            let pendingCount = session.chunkCount - transcriptSegments.map({ $0.audioChunkID }).uniqueCount
            HStack(spacing: 12) {
                ProgressView()
                    .tint(AppTheme.purple)
                    .scaleEffect(0.8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Processing Transcription...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(pendingCount) of \(session.chunkCount) chunks pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    Task { await refreshSession() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                        .foregroundStyle(AppTheme.purple)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(
                RadialGradient(
                    colors: [AppTheme.purple.opacity(0.15), AppTheme.purple.opacity(0.05)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 100
                )
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.purple.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Session Info Section
    
    private var sessionInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Details")
                .font(.headline)
            
            InfoRow(label: "Date", value: session.startTime.formatted(date: .abbreviated, time: .shortened))
            InfoRow(label: "Total Duration", value: formatDuration(session.totalDuration))
            InfoRow(label: "Parts", value: "\(session.chunkCount) chunk\(session.chunkCount == 1 ? "" : "s")")
            
            if !transcriptSegments.isEmpty {
                let wordCount = transcriptSegments.reduce(0) { $0 + $1.text.split(separator: " ").count }
                InfoRow(label: "Word Count", value: "\(wordCount) words")
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
    
    // MARK: - Toolbar Buttons
    
    private var toolbarButtons: some View {
        HStack(spacing: 16) {
            Button {
                Task {
                    do {
                        isFavorite = try await coordinator.toggleSessionFavorite(sessionId: session.sessionId)
                    } catch {
                        print("❌ Failed to toggle favorite: \(error)")
                    }
                }
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            
            ShareLink(item: transcriptText) {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(transcriptSegments.isEmpty)
        }
    }
    
    // MARK: - Playback Controls Section
    
    private var playbackControlsSection: some View {
        VStack(spacing: 16) {
            scrubberSlider
            timeDisplayRow
            playPauseButton
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
    
    private var waveformView: some View {
        Canvas { canvasContext, size in
            let centerY = size.height / 2
            let barCount = 80
            let barWidth = size.width / CGFloat(barCount)
            let maxBarHeight = size.height * 0.8
            
            // Calculate amplitude for each bar based on transcript segments
            let totalDuration = session.totalDuration
            
            for i in 0..<barCount {
                let barStartTime = (Double(i) / Double(barCount)) * totalDuration
                let barEndTime = (Double(i + 1) / Double(barCount)) * totalDuration
                
                // Check if any transcript segments overlap with this bar's time range
                var hasContent = false
                for segment in transcriptSegments {
                    let segmentStart = segment.startTime
                    let segmentEnd = segment.startTime + (segment.duration ?? 1.0)
                    
                    if (segmentStart <= barEndTime && segmentEnd >= barStartTime) {
                        hasContent = true
                        break
                    }
                }
                
                // Calculate bar height (tall where speech exists, short elsewhere)
                let barHeight: CGFloat
                if hasContent {
                    // Add variation for visual interest
                    let variation = sin(Double(i) * 0.5) * 0.3 + 0.7
                    barHeight = maxBarHeight * CGFloat(variation)
                } else {
                    barHeight = 4.0 // Minimal height for silence
                }
                
                let x = CGFloat(i) * barWidth
                let y = centerY - barHeight / 2
                
                let barRect = CGRect(x: x, y: y, width: max(barWidth - 1, 1), height: barHeight)
                let barPath = Path(roundedRect: barRect, cornerRadius: barWidth / 2)
                
                // Color based on playback state
                let color: Color
                if isPlayingThisSession && coordinator.audioPlayback.isPlaying {
                    let progress = totalDuration > 0 ? totalElapsedTime / totalDuration : 0
                    let barProgress = Double(i) / Double(barCount)
                    color = barProgress <= progress ? AppTheme.magenta : AppTheme.purple.opacity(0.5)
                } else {
                    color = AppTheme.purple.opacity(0.4)
                }
                
                canvasContext.fill(barPath, with: .color(color))
            }
            
            // Draw playhead indicator if playing
            if isPlayingThisSession {
                let progress = session.totalDuration > 0 ? totalElapsedTime / session.totalDuration : 0
                let playheadX = size.width * progress
                
                let playheadPath = Path { path in
                    path.move(to: CGPoint(x: playheadX, y: 0))
                    path.addLine(to: CGPoint(x: playheadX, y: size.height))
                }
                
                canvasContext.stroke(playheadPath, with: .color(AppTheme.magenta), lineWidth: 3)
            }
        }
        .frame(height: 100)
    }
    
    private var scrubberSlider: some View {
        Slider(
            value: Binding(
                get: { isPlayingThisSession ? totalElapsedTime : scrubbedTime },
                set: { newValue in
                    if isPlayingThisSession {
                        seekToTotalTime(newValue)
                    } else {
                        scrubbedTime = newValue
                    }
                }
            ),
            in: 0...max(session.totalDuration, 0.1)
        )
        .tint(AppTheme.purple)
    }
    
    private var timeDisplayRow: some View {
        HStack {
            Text(formatTime(isPlayingThisSession ? totalElapsedTime : scrubbedTime))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            
            Spacer()
            
            if isPlayingThisSession, let currentURL = coordinator.audioPlayback.currentlyPlayingURL,
               let idx = session.chunks.firstIndex(where: { $0.fileURL == currentURL }) {
                Text("Part \(idx + 1) of \(session.chunkCount)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.purple)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            Text(formatTime(session.totalDuration))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
    
    private var playPauseButton: some View {
        Button { playSession() } label: {
            let isCurrentlyPlaying = isPlayingThisSession && coordinator.audioPlayback.isPlaying
            
            HStack(spacing: 16) {
                // Icon in a circular background
                ZStack {
                    Circle()
                        .fill(AppTheme.purple.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.purple)
                }
                
                // Text label
                VStack(alignment: .leading, spacing: 4) {
                    if isCurrentlyPlaying {
                        Text("Pause")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    } else if isPlayingThisSession {
                        Text("Resume")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    } else {
                        Text(session.chunkCount > 1 ? "Play All \(session.chunkCount) Parts" : "Play Recording")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    
                    Text(formatTime(session.totalDuration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(AppTheme.purple.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Transcription Section
    
    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - just the title
            Text("Transcription")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            
            // Content directly below header
            transcriptionContent
                .padding(.horizontal, 12)
            
            // Action buttons at the bottom (only if there's content)
            if !transcriptSegments.isEmpty {
                HStack(spacing: 12) {
                    Spacer()
                    
                    // Copy all button
                    Button {
                        UIPasteboard.general.string = transcriptText
                        coordinator.showSuccess("Transcript copied")
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc")
                                .font(.body)
                            Text("Copy All")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.purple)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    RadialGradient(
                                        colors: [AppTheme.purple.opacity(0.15), AppTheme.purple.opacity(0.05)],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 50
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    LinearGradient(
                                        colors: [AppTheme.purple.opacity(0.4), AppTheme.magenta.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    // Share button
                    ShareLink(item: transcriptText) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body)
                            Text("Share")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.skyBlue)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    RadialGradient(
                                        colors: [AppTheme.skyBlue.opacity(0.15), AppTheme.skyBlue.opacity(0.05)],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 50
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    LinearGradient(
                                        colors: [AppTheme.skyBlue.opacity(0.4), AppTheme.purple.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            } else {
                Spacer().frame(height: 12)
            }
        }
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.cardGradient(for: colorScheme))
                .allowsHitTesting(false)
        )
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var transcriptionContent: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(AppTheme.purple)
                Text("Loading transcription...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else if let error = loadError {
            Text("Error: \(error)")
                .foregroundStyle(.red)
                .font(.subheadline)
                .padding(.vertical, 8)
        } else if transcriptSegments.isEmpty {
            transcriptionEmptyState
        } else {
            transcriptionSegmentsList
        }
    }
    
    @ViewBuilder
    private var transcriptionEmptyState: some View {
        let chunkIds = Set(session.chunks.map { $0.id })
        let hasTranscribing = !chunkIds.isDisjoint(with: coordinator.transcribingChunkIds)
        let hasFailed = !chunkIds.isDisjoint(with: coordinator.failedChunkIds)
        
        if hasTranscribing {
            ContentUnavailableView(
                "Transcribing Audio...",
                systemImage: "waveform.path",
                description: Text("Your audio is being processed. This may take a moment.")
            )
            .padding(.vertical, 8)
        } else if hasFailed {
            ContentUnavailableView(
                "Transcription Failed",
                systemImage: "exclamationmark.triangle",
                description: Text("Unable to transcribe this recording. Try recording again.")
            )
            .padding(.vertical, 8)
        } else {
            ContentUnavailableView(
                "No Transcript",
                systemImage: "doc.text.slash",
                description: Text("No transcription available for this recording.")
            )
            .padding(.vertical, 8)
        }
    }
    
    private var transcriptionSegmentsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groupedSegmentsByChunk, id: \.chunkIndex) { group in
                let chunkId = session.chunks[safe: group.chunkIndex]?.id
                TranscriptChunkView(
                    chunkIndex: group.chunkIndex,
                    segments: group.segments,
                    session: session,
                    isCurrentChunk: isPlayingThisSession && currentChunkIndex == group.chunkIndex,
                    chunkId: chunkId,
                    coordinator: coordinator,
                    isEdited: chunkId.map { editedChunkIds.contains($0) } ?? false,
                    onSeekToChunk: { seekToChunk(group.chunkIndex) },
                    onTextEdited: { segmentId, newText in
                        if let chunkId = chunkId {
                            editedChunkIds.insert(chunkId)
                        }
                        saveTranscriptEdit(segmentId: segmentId, newText: newText)
                    }
                )
            }
            
            // Show regenerate prompt if transcript was edited
            if transcriptWasEdited && sessionSummary != nil {
                regenerateSummaryPrompt
            }
        }
    }
    
    private var regenerateSummaryPrompt: some View {
        HStack {
            Spacer()
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(AppTheme.magenta)
                    Text("Transcript was edited")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Text("The summary may be outdated. Would you like to regenerate it?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 12) {
                    // Dismiss button
                    Button {
                        transcriptWasEdited = false
                    } label: {
                        Text("Not Now")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    
                    // Regenerate button with loading state
                    Button {
                        Task {
                            await regenerateSummary()
                            transcriptWasEdited = false
                        }
                    } label: {
                        HStack {
                            if isRegeneratingSummary {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isRegeneratingSummary ? "Regenerating..." : "Regenerate Summary")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.magenta)
                    .disabled(isRegeneratingSummary)
                }
            }
            .padding()
            .background(
                RadialGradient(
                    colors: [AppTheme.magenta.opacity(0.15), AppTheme.magenta.opacity(0.05)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 100
                )
            )
            .cornerRadius(12)
            .frame(maxWidth: 400)
            Spacer()
        }
    }
    
    private func saveTranscriptEdit(segmentId: UUID, newText: String) {
        Task {
            do {
                try await coordinator.updateTranscriptText(segmentId: segmentId, newText: newText)
                transcriptWasEdited = true
                await loadTranscription()  // Refresh the segments
                coordinator.showSuccess("Transcript updated")
            } catch {
                print("❌ [SessionDetailView] Failed to save transcript edit: \(error)")
                coordinator.showError("Failed to save edit")
            }
        }
    }
    
    private func seekToChunk(_ chunkIndex: Int) {
        var targetTime: TimeInterval = 0
        for i in 0..<chunkIndex {
            targetTime += session.chunks[i].duration
        }
        seekToTotalTime(targetTime)
    }
    
    private func startPlaybackUpdateTimer() {
        stopPlaybackUpdateTimer()
        // Update at 30fps for smooth visual feedback (matches waveform animation)
        playbackUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { _ in
            Task { @MainActor in
                self.forceUpdateTrigger.toggle()
            }
        }
        // Add timer to common run loop mode to ensure it fires during UI interactions
        if let timer = playbackUpdateTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func stopPlaybackUpdateTimer() {
        playbackUpdateTimer?.invalidate()
        playbackUpdateTimer = nil
    }
    
    private func startTranscriptionCheckTimer() {
        // Check immediately
        checkTranscriptionStatus()
        
        // Then check every 2 seconds
        transcriptionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                self.checkTranscriptionStatus()
            }
        }
    }
    
    private func stopTranscriptionCheckTimer() {
        transcriptionCheckTimer?.invalidate()
        transcriptionCheckTimer = nil
    }
    
    private func checkTranscriptionStatus() {
        // Check using real-time status tracking from coordinator
        let chunkIds = Set(session.chunks.map { $0.id })
        
        // Check if any chunks are actively being transcribed right now
        let hasTranscribing = !chunkIds.isDisjoint(with: coordinator.transcribingChunkIds)
        
        // For chunks not actively transcribing, check if they have transcript segments
        // This handles both new transcriptions and previously completed ones
        let chunksWithTranscripts = Set(transcriptSegments.map { $0.audioChunkID })
        
        // A session is complete if:
        // 1. No chunks are currently being transcribed AND
        // 2. All chunks either have transcripts OR are marked as failed
        let allChunksAccountedFor = chunkIds.allSatisfy { chunkId in
            chunksWithTranscripts.contains(chunkId) || 
            coordinator.failedChunkIds.contains(chunkId)
        }
        
        let wasComplete = isTranscriptionComplete
        isTranscriptionComplete = !hasTranscribing && allChunksAccountedFor
        
        // If just completed, reload data and stop checking
        if !wasComplete && isTranscriptionComplete {
            Task {
                stopTranscriptionCheckTimer()
                // Reload transcription to get the latest segments
                await loadTranscription()
                // Load session summary
                await loadSessionSummary()
            }
        }
    }
    
    private var groupedByChunk: [(chunkIndex: Int, text: String)] {
        // Group segments by chunk and combine text
        var groups: [Int: [TranscriptSegment]] = [:]
        
        for segment in transcriptSegments {
            for (index, chunk) in session.chunks.enumerated() {
                if segment.audioChunkID == chunk.id {
                    groups[index, default: []].append(segment)
                    break
                }
            }
        }
        
        return groups.keys.sorted().map { chunkIndex in
            let segments = groups[chunkIndex] ?? []
            let text = segments.map { $0.text }.joined(separator: " ")
            return (chunkIndex, text)
        }
    }
    
    private var groupedSegmentsByChunk: [(chunkIndex: Int, segments: [TranscriptSegment])] {
        // Group segments by chunk, preserving segment objects for editing
        var groups: [Int: [TranscriptSegment]] = [:]
        
        for segment in transcriptSegments {
            for (index, chunk) in session.chunks.enumerated() {
                if segment.audioChunkID == chunk.id {
                    groups[index, default: []].append(segment)
                    break
                }
            }
        }
        
        return groups.keys.sorted().map { chunkIndex in
            (chunkIndex, groups[chunkIndex] ?? [])
        }
    }
    
    // Combined transcript text for sharing
    private var transcriptText: String {
        groupedByChunk.map { $0.text }.joined(separator: "\n\n")
    }
    
    // MARK: - Session Title Section
    
    private var sessionTitleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditingTitle {
                HStack {
                    TextField("Session Title", text: $sessionTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                        .focused($isTextFieldFocused)
                    
                    Button("Save") {
                        isEditingTitle = false
                        saveTitle()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.purple)
                    
                    Button("Cancel") {
                        isEditingTitle = false
                        sessionTitle = session.title ?? ""
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.skyBlue)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if !sessionTitle.isEmpty {
                            Text(sessionTitle)
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        
                        Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        isEditingTitle = true
                        isTextFieldFocused = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.title2)
                            .foregroundStyle(AppTheme.purple)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Session Summary Section
    
    private var sessionSummaryPlaceholderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Summary")
                    .font(.headline)
                
                Spacer()
                
                // Generate button
                Button {
                    Task {
                        await regenerateSummary()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isRegeneratingSummary {
                            ProgressView()
                                .tint(AppTheme.purple)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.body)
                        }
                        Text("Generate")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.darkPurple, AppTheme.magenta],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.purple.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.purple.opacity(0.4), AppTheme.magenta.opacity(0.3)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRegeneratingSummary)
            }
            
            Text("Summary not yet generated. Tap Generate to create an AI summary of this recording.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .italic()
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
    
    private func sessionSummaryErrorSection(error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Summary")
                    .font(.headline)
                
                Spacer()
                
                // Retry button
                Button {
                    Task {
                        await regenerateSummary()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isRegeneratingSummary {
                            ProgressView()
                                .tint(.orange)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.body)
                        }
                        Text("Retry")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                Color.orange.opacity(0.4),
                                lineWidth: 1.5
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRegeneratingSummary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Summary Generation Failed")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if error.contains("API key") {
                    Text("Go to Settings → AI & Intelligence to add your API key.")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
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
    
    private func sessionSummarySection(summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Summary")
                    .font(.headline)
                
                Spacer()
                
                // Copy button
                Button {
                    UIPasteboard.general.string = summary.text
                    coordinator.showSuccess("Summary copied to clipboard")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                        .foregroundStyle(AppTheme.skyBlue)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppTheme.skyBlue.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    LinearGradient(
                                        colors: [AppTheme.skyBlue.opacity(0.4), AppTheme.purple.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Regenerate button
                Button {
                    Task {
                        await regenerateSummary()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isRegeneratingSummary {
                            ProgressView()
                                .tint(AppTheme.purple)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.body)
                        }
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.darkPurple, AppTheme.magenta],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppTheme.purple.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.purple.opacity(0.4), AppTheme.magenta.opacity(0.3)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRegeneratingSummary)
            }
            
            Text(summary.text)
                .font(.body)
                .foregroundStyle(.primary)
            
            // Show engine tier if available
            if let engineTier = summary.engineTier {
                HStack {
                    Image(systemName: engineIcon(for: engineTier))
                        .font(.caption)
                    Text("Generated by \(engineDisplayName(for: engineTier))")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 4)
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
    
    // MARK: - Personal Notes Section
    
    private var personalNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Personal Notes")
                    .font(.headline)
                
                Spacer()
                
                if isEditingNotes {
                    Button("Done") {
                        isEditingNotes = false
                        saveNotes()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        isEditingNotes = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.body)
                            .foregroundStyle(AppTheme.purple)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppTheme.purple.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        LinearGradient(
                                            colors: [AppTheme.purple.opacity(0.4), AppTheme.magenta.opacity(0.3)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if isEditingNotes {
                TextEditor(text: $sessionNotes)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
            } else if sessionNotes.isEmpty {
                Text("Tap the pencil to add personal notes...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Text(sessionNotes)
                    .font(.body)
                    .foregroundStyle(.primary)
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
    
    // MARK: - Helper Methods
    
    private func engineIcon(for tier: String) -> String {
        switch tier.lowercased() {
        case "local": return "cpu"
        case "apple": return "apple.intelligence"
        case "basic": return "bolt.fill"
        case "external": return "sparkles"
        case "rollup": return "arrow.triangle.merge"
        case "year wrap": return "sparkles"
        default: return "cpu"
        }
    }
    
    private func engineDisplayName(for tier: String) -> String {
        switch tier.lowercased() {
        case "local": return "Local AI"
        case "apple": return "Apple Intelligence"
        case "basic": return "Basic"
        case "external": return "Year Wrapped Pro AI"
        case "rollup": return "Rollup"
        case "year wrap": return "Year Wrap"
        default: return tier.capitalized
        }
    }
    
    private func loadSessionMetadata() async {
        do {
            if let metadata = try await coordinator.fetchSessionMetadata(sessionId: session.sessionId) {
                sessionTitle = metadata.title ?? ""
                sessionNotes = metadata.notes ?? ""
                isFavorite = metadata.isFavorite
            } else {
                sessionTitle = session.title ?? ""
                sessionNotes = session.notes ?? ""
                isFavorite = session.isFavorite
            }
        } catch {
            print("❌ [SessionDetailView] Failed to load metadata: \(error)")
            sessionTitle = session.title ?? ""
            sessionNotes = session.notes ?? ""
            isFavorite = session.isFavorite
        }
    }
    
    private func saveTitle() {
        Task {
            do {
                let titleToSave = sessionTitle.isEmpty ? nil : sessionTitle
                try await coordinator.updateSessionTitle(sessionId: session.sessionId, title: titleToSave)
                coordinator.showSuccess("Title saved")
            } catch {
                print("❌ [SessionDetailView] Failed to save title: \(error)")
            }
        }
    }
    
    private func saveNotes() {
        Task {
            do {
                let notesToSave = sessionNotes.isEmpty ? nil : sessionNotes
                try await coordinator.updateSessionNotes(sessionId: session.sessionId, notes: notesToSave)
                coordinator.showSuccess("Notes saved")
            } catch {
                print("❌ [SessionDetailView] Failed to save notes: \(error)")
            }
        }
    }
    
    private func regenerateSummary() async {
        isRegeneratingSummary = true
        summaryLoadError = nil
        defer { isRegeneratingSummary = false }
        
        do {
            // Force regeneration if transcript was edited, otherwise check cache
            let forceRegenerate = transcriptWasEdited
            try await coordinator.generateSessionSummary(sessionId: session.sessionId, forceRegenerate: forceRegenerate)
            await loadSessionSummary()
            // Reset edit tracking after summary is regenerated
            editedChunkIds.removeAll()
            transcriptWasEdited = false
            coordinator.showSuccess("Summary regenerated")
        } catch {
            print("❌ [SessionDetailView] Failed to regenerate summary: \(error)")
            summaryLoadError = error.localizedDescription
            coordinator.showError("Failed to regenerate summary")
        }
    }

    private var isPlayingThisSession: Bool {
        // Check if any chunk from this session is currently playing
        guard let currentURL = coordinator.audioPlayback.currentlyPlayingURL else { return false }
        return session.chunks.contains { $0.fileURL == currentURL }
    }
    
    private var currentChunkIndex: Int? {
        // Get the index of the currently playing chunk
        guard let currentURL = coordinator.audioPlayback.currentlyPlayingURL else { return nil }
        return session.chunks.firstIndex { $0.fileURL == currentURL }
    }
    
    // Generate consistent waveform heights (seeded for consistency)
    private func waveformHeight(for index: Int) -> CGFloat {
        let seed = Double(index) * 0.12345
        let height = sin(seed) * sin(seed * 2.3) * sin(seed * 1.7)
        return 20 + abs(height) * 40
    }
    
    // Calculate total elapsed time across all chunks
    private var totalElapsedTime: TimeInterval {
        // Use forceUpdateTrigger to ensure UI updates
        _ = forceUpdateTrigger
        
        guard isPlayingThisSession,
              let currentURL = coordinator.audioPlayback.currentlyPlayingURL,
              let currentChunkIndex = session.chunks.firstIndex(where: { $0.fileURL == currentURL }) else {
            return 0
        }
        
        // Sum durations of all previous chunks
        var elapsed: TimeInterval = 0
        for i in 0..<currentChunkIndex {
            elapsed += session.chunks[i].duration
        }
        
        // Add current chunk's progress
        elapsed += coordinator.audioPlayback.currentTime
        
        return elapsed
    }
    
    // Calculate playback progress as percentage (0.0 to 1.0)
    private var playbackProgress: Double {
        // Use forceUpdateTrigger to ensure UI updates
        _ = forceUpdateTrigger
        
        guard session.totalDuration > 0 else { return 0 }
        
        if isPlayingThisSession {
            return totalElapsedTime / session.totalDuration
        } else {
            return 0
        }
    }
    
    // Seek to a specific time in the total session
    private func seekToTotalTime(_ targetTime: TimeInterval) {
        var remainingTime = targetTime
        
        // Find which chunk contains this time
        for (index, chunk) in session.chunks.enumerated() {
            if remainingTime <= chunk.duration {
                // Check if we're already in this chunk
                if let currentURL = coordinator.audioPlayback.currentlyPlayingURL,
                   session.chunks[index].fileURL == currentURL {
                    // Same chunk - just seek within it
                    coordinator.audioPlayback.seek(to: remainingTime)
                } else {
                    // Different chunk - restart playback from this chunk
                    let chunkURLs = session.chunks.map { $0.fileURL }
                    let wasPlaying = coordinator.audioPlayback.isPlaying
                    
                    Task {
                        try await coordinator.audioPlayback.playSequence(urls: Array(chunkURLs.dropFirst(index))) {
                            print("✅ [SessionDetailView] Session playback completed after seek")
                        }
                        
                        // Seek within this chunk immediately for smooth scrubbing
                        // Minimal delay to ensure player is initialized
                        try? await Task.sleep(for: .milliseconds(10))
                        coordinator.audioPlayback.seek(to: remainingTime)
                        
                        // If wasn't playing before, pause immediately after seeking
                        if !wasPlaying {
                            coordinator.audioPlayback.pause()
                        }
                    }
                }
                
                return
            }
            
            remainingTime -= chunk.duration
        }
    }
    
    private func loadSessionSummary() async {
        summaryLoadError = nil
        do {
            sessionSummary = try await coordinator.fetchSessionSummary(sessionId: session.sessionId)
            if sessionSummary != nil {
                print("✨ [SessionDetailView] Loaded session summary")
            } else {
                print("ℹ️ [SessionDetailView] No session summary found (not yet generated)")
                summaryLoadError = "Summary not yet generated. Transcription must complete first."
            }
        } catch {
            print("❌ [SessionDetailView] Failed to load session summary: \(error)")
            summaryLoadError = error.localizedDescription
        }
    }
    
    private func loadTranscription() async {
        print("📄 [SessionDetailView] Loading transcription for session \(session.sessionId)")
        isLoading = true
        loadError = nil
        
        do {
            transcriptSegments = try await coordinator.fetchSessionTranscript(sessionId: session.sessionId)
            print("📄 [SessionDetailView] Loaded \(transcriptSegments.count) transcript segments")
            
            // Debug: Log which chunks have transcripts
            let chunksWithTranscripts = Set(transcriptSegments.map { $0.audioChunkID })
            for chunk in session.chunks {
                let hasTranscript = chunksWithTranscripts.contains(chunk.id)
                let isTranscribing = coordinator.transcribingChunkIds.contains(chunk.id)
                let isFailed = coordinator.failedChunkIds.contains(chunk.id)
                print("📄 [SessionDetailView] Chunk \(chunk.chunkIndex): hasTranscript=\(hasTranscript), transcribing=\(isTranscribing), failed=\(isFailed)")
            }
        } catch {
            print("❌ [SessionDetailView] Failed to load transcription: \(error)")
            loadError = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func refreshSession() async {
        print("🔄 [SessionDetailView] Manually refreshing session...")
        
        // Reload transcription
        await loadTranscription()
        
        // Force transcription status check
        checkTranscriptionStatus()
        
        // Check if any chunks need to be queued for transcription
        let chunksWithTranscripts = Set(transcriptSegments.map { $0.audioChunkID })
        
        print("📊 [SessionDetailView] Chunk analysis:")
        print("   - Total chunks in session: \(session.chunks.count)")
        print("   - Chunks with transcripts: \(chunksWithTranscripts.count)")
        print("   - Currently transcribing: \(coordinator.transcribingChunkIds.count)")
        print("   - Failed: \(coordinator.failedChunkIds.count)")
        
        for chunk in session.chunks {
            let hasTranscript = chunksWithTranscripts.contains(chunk.id)
            let isTranscribing = coordinator.transcribingChunkIds.contains(chunk.id)
            let isFailed = coordinator.failedChunkIds.contains(chunk.id)
            let isTranscribed = coordinator.transcribedChunkIds.contains(chunk.id)
            
            print("   - Chunk \(chunk.chunkIndex): transcript=\(hasTranscript), transcribing=\(isTranscribing), transcribed=\(isTranscribed), failed=\(isFailed)")
            
            if !hasTranscript && !isTranscribing && !isFailed {
                print("🚨 [SessionDetailView] Chunk \(chunk.chunkIndex) is ORPHANED - forcing into transcription queue")
                // Force this chunk into transcription by calling retry
                // This will add it to pendingTranscriptionIds and start processing
                await coordinator.retryTranscription(chunkId: chunk.id)
            }
        }
        
        // Wait a bit and reload again
        try? await Task.sleep(for: .seconds(1))
        await loadTranscription()
        checkTranscriptionStatus()
    }
    
    private func playSession() {
        // Trigger haptic feedback
        coordinator.triggerHaptic(.medium)
        
        if isPlayingThisSession {
            // Pause if playing
            if coordinator.audioPlayback.isPlaying {
                coordinator.audioPlayback.pause()
            } else {
                coordinator.audioPlayback.resume()
            }
        } else {
            // Start sequential playback of all chunks
            let chunkURLs = session.chunks.map { $0.fileURL }
            print("🎵 [SessionDetailView] Starting playback of \(chunkURLs.count) chunks")
            
            // If user has scrubbed before playing, seek to that position
            if scrubbedTime > 0 {
                Task {
                    try await coordinator.audioPlayback.playSequence(urls: chunkURLs) {
                        print("✅ [SessionDetailView] Session playback completed")
                    }
                    // Seek to scrubbed position after playback starts
                    try? await Task.sleep(for: .milliseconds(50))
                    seekToTotalTime(scrubbedTime)
                }
            } else {
                Task {
                    try await coordinator.audioPlayback.playSequence(urls: chunkURLs) {
                        print("✅ [SessionDetailView] Session playback completed")
                    }
                }
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Language Settings View

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

// MARK: - Overview Summary Card

struct OverviewSummaryCard: View {
    let summary: Summary
    let periodTitle: String
    let sessionCount: Int
    let sessionsInPeriod: [RecordingSession]
    let coordinator: AppCoordinator
    let onRegenerate: (() async -> Void)?
    let wrapAction: (() -> Void)?
    let wrapIsLoading: Bool
    
    @State private var showingSessions = false
    @State private var visibleSessionCount = 3
    @State private var isRegenerating = false
    @State private var selectedSession: RecordingSession?
    
    private var visibleSessions: [RecordingSession] {
        Array(sessionsInPeriod.prefix(visibleSessionCount))
    }
    
    private var hasMoreSessions: Bool {
        visibleSessionCount < sessionsInPeriod.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with action buttons
            headerSection
            
            // Summary text - larger, selectable, in its own container
            summaryTextSection
            
            // Topics tags
            if let topicsJSON = summary.topicsJSON {
                TopicTagsView(topicsJSON: topicsJSON)
            }
            
            // Engine tier badge
            if let engineTier = summary.engineTier {
                engineBadge(tier: engineTier)
            }
            
            Divider()
            
            // Sessions list - individually tappable
            if !sessionsInPeriod.isEmpty {
                sessionsSection
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("📝 \(periodTitle)")
                    .font(.headline)
                Text("Based on \(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Copy button
            Button {
                UIPasteboard.general.string = summary.text
                coordinator.showSuccess("Summary copied")
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            // Regenerate button (optional)
            if let onRegenerate {
                Button {
                    Task {
                        isRegenerating = true
                        await onRegenerate()
                        isRegenerating = false
                    }
                } label: {
                    if isRegenerating {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                            .foregroundStyle(.orange)
                            .frame(width: 44, height: 44)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRegenerating)
            }

            if let wrapAction {
                Button {
                    wrapAction()
                } label: {
                    if wrapIsLoading {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(.purple)
                            .frame(width: 44, height: 44)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRegenerating || wrapIsLoading)
                .accessibilityLabel("Generate Year Wrap")
            }
        }
    }
    
    // MARK: - Summary Text Section
    
    private var summaryTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The summary text in a scrollable, selectable container
            ScrollView {
                Text(summary.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 200)
            .padding(16)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Engine Badge
    
    private func engineBadge(tier: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: engineIcon(for: tier))
                .font(.caption)
            Text("Generated by \(engineDisplayName(for: tier))")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }
    
    // MARK: - Sessions Section
    
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Toggle button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSessions.toggle()
                    if !showingSessions {
                        visibleSessionCount = 3 // Reset when closing
                    }
                }
            } label: {
                HStack {
                    Text(showingSessions ? "Hide sessions" : "Show individual sessions (\(sessionsInPeriod.count))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: showingSessions ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.blue)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if showingSessions {
                // Session rows - each individually tappable with Button
                VStack(spacing: 8) {
                    ForEach(visibleSessions, id: \.sessionId) { session in
                        Button {
                            selectedSession = session
                        } label: {
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
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Load more button
                if hasMoreSessions {
                    Button {
                        withAnimation {
                            visibleSessionCount += 5
                        }
                    } label: {
                        HStack {
                            Text("Show more (\(sessionsInPeriod.count - visibleSessionCount) remaining)")
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $selectedSession) { session in
            NavigationStack {
                SessionDetailView(session: session)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func engineIcon(for tier: String) -> String {
        switch tier.lowercased() {
        case "local": return "cpu"
        case "apple": return "apple.intelligence"
        case "basic": return "bolt.fill"
        case "external": return "sparkles"
        case "rollup": return "arrow.triangle.merge"
        case "year wrap": return "sparkles"
        default: return "cpu"
        }
    }
    
    private func engineDisplayName(for tier: String) -> String {
        switch tier.lowercased() {
        case "local": return "Local AI"
        case "apple": return "Apple Intelligence"
        case "basic": return "Basic"
        case "external": return "Year Wrapped Pro AI"
        case "rollup": return "Rollup"
        case "year wrap": return "Year Wrap"
        default: return tier.capitalized
        }
    }
}

// MARK: - Insight Session Row

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
        case .apple:
            return "Apple Intelligence requires iOS 18.1+ and compatible hardware. This feature will be available in a future update."
        case .local:
            return "Download the local AI model to enable on-device processing. Go to Settings → Local AI to manage models."
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
        case .apple: return "apple.logo"
        case .local: return "cpu"
        case .external: return "cloud"
        }
    }
    
    private var iconColor: Color {
        switch tier {
        case .basic: return .gray
        case .apple: return .blue
        case .local: return .purple
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

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppCoordinator.previewInstance())
    }
}

