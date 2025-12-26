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
