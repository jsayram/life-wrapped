import SwiftUI
import SharedModels

struct HomeTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
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
                    
                    Spacer()
                }
                .padding()
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
