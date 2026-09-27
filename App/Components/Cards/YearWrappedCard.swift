import SwiftUI
import SharedModels
import Summarization


struct YearWrappedCard: View {
    /// The wrap for `filter`
    let summary: Summary
    /// All of this year's wraps, so the full view can switch between them
    let wraps: [ItemFilter: Summary]
    let coordinator: AppCoordinator
    let filter: ItemFilter
    let onRegenerate: () -> Void
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
                    UIPasteboard.general.string = parsed?.storyText ?? yearSummary
                    coordinator.showSuccess("Year Wrapped summary copied")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .scaledFont(size: 15)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy Year Wrapped summary")

                Button {
                    onRegenerate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .scaledFont(size: 15)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Regenerate Year Wrap")
            }
            .foregroundStyle(AppTheme.onAccent)

            Text(String(Calendar.current.component(.year, from: summary.periodStart)))
                .scaledFont(size: 44, design: .serif)
                .foregroundStyle(AppTheme.onAccent)

            if let journals = parsed?.journals, !journals.isEmpty {
                // All: each journal's own title and summary, never blended into one
                ForEach(journals, id: \.category) { journal in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(journal.category.displayName.uppercased(), systemImage: journal.category == .work ? "briefcase.fill" : "house.fill")
                            .font(.caption)
                            .tracking(0.8)
                            .foregroundStyle(AppTheme.onAccent.opacity(0.7))
                        Text(journal.title)
                            .scaledFont(size: 20, design: .serif)
                            .foregroundStyle(AppTheme.onAccent)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(journal.summary)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.onAccent.opacity(0.85))
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                if let title = parsed?.yearTitle {
                    Text(title)
                        .scaledFont(size: 22, design: .serif)
                        .foregroundStyle(AppTheme.onAccent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(yearSummary)
                    .font(.body)
                    .foregroundStyle(AppTheme.onAccent.opacity(0.85))
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Out of date: this journal's recordings added or changed since the wrap was built
            if outdatedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("\(outdatedCount) \(scopeWord)\(outdatedCount == 1 ? "recording" : "recordings") added or changed since this wrap")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Update") { update() }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.onAccent)
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.onAccent.opacity(0.8))
                .padding(10)
                .background(AppTheme.onAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                showDetailView = true
            } label: {
                HStack(spacing: 6) {
                    Text("View full wrap")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 12, weight: .semibold)
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
            YearWrapDetailView(wraps: wraps, coordinator: coordinator, initialFilter: filter)
                .presentationSizing(.page) // full-page sheet on iPad; no change on iPhone
        }
    }
    
    // MARK: - Helpers

    private var outdatedCount: Int {
        coordinator.yearWrapOutdatedCounts[filter] ?? 0
    }

    /// "work " / "personal " so the count says which journal it covers
    private var scopeWord: String {
        switch filter {
        case .all: return ""
        case .workOnly: return "work "
        case .personalOnly: return "personal "
        }
    }

    /// Rebuild with the engine that made this wrap, reusing every month and journal that didn't
    /// change. Falls back to the engine picker when that engine isn't known.
    private func update() {
        if let engine = summary.engineTier.flatMap(EngineTier.init(rawValue:)) {
            coordinator.startYearWrap(engine: engine, forceRegenerate: false)
        } else {
            onRegenerate()
        }
    }
    
    private var parsed: YearWrapData? {
        YearWrapData.parse(summary.text)
    }
    
    /// The wrap's summary, or the start of the raw text if it isn't a Year Wrap
    private var yearSummary: String {
        parsed?.yearSummary ?? String(summary.text.prefix(200)) + (summary.text.count > 200 ? "..." : "")
    }
}

// MARK: - Generate Year Wrap Card

