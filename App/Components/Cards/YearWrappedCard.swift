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
            return "All"
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
            return AppTheme.accent
        case .personalOnly:
            return AppTheme.accent
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Text(filter == .all ? "YEAR WRAPPED" : "YEAR WRAPPED · \(filterLabel.uppercased())")
                    .font(.caption)
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.onAccent.opacity(0.7))

                Spacer(minLength: 0)

                Button {
                    let summaryText = extractYearSummary(from: summary.text)
                    UIPasteboard.general.string = summaryText
                    coordinator.showSuccess("Year Wrapped summary copied")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy Year Wrapped summary")

                Button {
                    onRegenerate()
                } label: {
                    Group {
                        if isRegenerating {
                            ProgressView()
                                .tint(AppTheme.onAccent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15))
                        }
                    }
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRegenerating)
                .accessibilityLabel("Regenerate Year Wrap")
            }
            .foregroundStyle(AppTheme.onAccent)

            Text(String(Calendar.current.component(.year, from: summary.periodStart)))
                .font(AppTheme.titleFont(size: 44))
                .foregroundStyle(AppTheme.onAccent)

            Text(extractYearSummary(from: summary.text))
                .font(.body)
                .foregroundStyle(AppTheme.onAccent.opacity(0.85))
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Staleness note
            if coordinator.yearWrapNewSessionCount > 0 {
                Label(
                    "\(coordinator.yearWrapNewSessionCount) new \(coordinator.yearWrapNewSessionCount == 1 ? "session" : "sessions") since this wrap",
                    systemImage: "exclamationmark.circle"
                )
                .font(.footnote)
                .foregroundStyle(AppTheme.onAccent.opacity(0.7))
            }

            Button {
                showDetailView = true
            } label: {
                HStack(spacing: 6) {
                    Text("View full wrap")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(AppTheme.onAccent)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.accent)
        )
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

