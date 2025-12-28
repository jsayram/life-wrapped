import SwiftUI
import SharedModels
import Summarization


struct YearWrappedCard: View {
    let summary: Summary
    let coordinator: AppCoordinator
    let filter: ItemFilter
    let onRegenerate: () -> Void
    let isRegenerating: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var showDetailView = false
    
    /// Label text for the current filter
    private var filterLabel: String {
        switch filter {
        case .all:
            return "Combined"
        case .workOnly:
            return "Work"
        case .personalOnly:
            return "Personal"
        }
    }
    
    /// Icon for the current filter
    private var filterIcon: String {
        switch filter {
        case .all:
            return "square.stack.3d.up.fill"
        case .workOnly:
            return "briefcase.fill"
        case .personalOnly:
            return "house.fill"
        }
    }
    
    /// Color for the current filter
    private var filterColor: Color {
        switch filter {
        case .all:
            return AppTheme.purple
        case .workOnly:
            return .blue
        case .personalOnly:
            return .green
        }
    }
    
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
                        
                        // Filter badge
                        Label(filterLabel, systemImage: filterIcon)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(filterColor)
                            )
                    }
                    Text("AI-powered yearly summary")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Staleness badge
                    if coordinator.yearWrapNewSessionCount > 0 {
                        Label(
                            "Outdated (\(coordinator.yearWrapNewSessionCount) new \(coordinator.yearWrapNewSessionCount == 1 ? "session" : "sessions"))",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.orange.opacity(0.15))
                        )
                        .padding(.top, 2)
                    }
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
            
            // Summary preview with View Full button
            VStack(spacing: 12) {
                Text(extractYearSummary(from: summary.text))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Button {
                    showDetailView = true
                } label: {
                    HStack {
                        Spacer()
                        Text("View Full Wrap")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.subheadline)
                        Spacer()
                    }
                    .foregroundStyle(YearWrapTheme.electricPurple)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(YearWrapTheme.electricPurple.opacity(0.15))
                    )
                }
            }
            .padding(12)
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
        .sheet(isPresented: $showDetailView) {
            YearWrapDetailView(yearWrap: summary, coordinator: coordinator, initialFilter: filter)
        }
    }
    
    // MARK: - Helpers
    
    private func extractYearSummary(from text: String) -> String {
        // Try to parse JSON and extract year_summary field
        guard let data = text.data(using: .utf8) else {
            print("❌ [YearWrappedCard] Failed to convert text to data")
            return String(text.prefix(200)) + (text.count > 200 ? "..." : "")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [YearWrappedCard] Failed to parse JSON")
            print("📄 [YearWrappedCard] First 100 chars: \(String(text.prefix(100)))")
            return String(text.prefix(200)) + (text.count > 200 ? "..." : "")
        }
        
        guard let yearSummary = json["year_summary"] as? String else {
            print("❌ [YearWrappedCard] No year_summary field found")
            print("🔑 [YearWrappedCard] Available keys: \(json.keys.joined(separator: ", "))")
            return String(text.prefix(200)) + (text.count > 200 ? "..." : "")
        }
        
        print("✅ [YearWrappedCard] Extracted year_summary: \(String(yearSummary.prefix(50)))...")
        return yearSummary
    }
}

// MARK: - Generate Year Wrap Card

