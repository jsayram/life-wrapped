import SwiftUI
import SharedModels

struct HomeTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var isLocalModelDownloaded: Bool = true  // Default true to hide initially
    @State private var showDownloadCompleteBanner: Bool = false
    
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
                    
                    // Download in progress banner
                    if coordinator.isDownloadingLocalModel {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Downloading AI model...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Download complete banner
                    if showDownloadCompleteBanner {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("AI model ready!")
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Category Selector
                    if let recordingCoord = coordinator.recordingCoordinator {
                        Picker("Category", selection: Binding(
                            get: { recordingCoord.selectedCategory },
                            set: { recordingCoord.selectedCategory = $0 }
                        )) {
                            ForEach(SessionCategory.allCases, id: \.self) { cat in
                                Label {
                                    Text(cat.displayName)
                                        .font(.subheadline)
                                } icon: {
                                    Image(systemName: cat.systemImage)
                                }
                                .tag(cat)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(coordinator.recordingState != .idle)
                        .opacity(coordinator.recordingState != .idle ? 0.6 : 1.0)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 8)
                    }
                    
                    // Recording Button
                    RecordingButton()
                    
                    // Subtle Local AI reminder (only shows when model not downloaded)
                    if !isLocalModelDownloaded && !coordinator.isDownloadingLocalModel {
                        VStack(spacing: 6) {
                            Text("Transcription works! Summaries use basic mode.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text("Download AI model for smarter summaries.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            
                            NavigationLink(destination: AISettingsView()) {
                                Text("Configure in Settings →")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.purple)
                            }
                        }
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .task {
                // Check if local model is downloaded
                isLocalModelDownloaded = await coordinator.isLocalModelDownloaded()
            }
            .onChange(of: coordinator.isDownloadingLocalModel) { wasDownloading, isDownloading in
                // Show completion banner when download finishes
                if wasDownloading && !isDownloading {
                    Task {
                        let downloaded = await coordinator.isLocalModelDownloaded()
                        if downloaded {
                            withAnimation {
                                isLocalModelDownloaded = true
                                showDownloadCompleteBanner = true
                            }
                            // Auto-hide after 3 seconds
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            withAnimation {
                                showDownloadCompleteBanner = false
                            }
                        }
                    }
                }
            }
            .refreshable {
                await refreshStats()
            }
            .navigationBarHidden(true)
        }
    }
    
    private func refreshStats() async {
        print("🔄 [HomeTab] Manual refresh triggered")
        await coordinator.refreshTodayStats()
        await coordinator.refreshStreak()
        print("✅ [HomeTab] Stats refreshed")
    }
}
