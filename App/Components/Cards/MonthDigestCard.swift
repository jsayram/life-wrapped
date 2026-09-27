// =============================================================================
// MonthDigestCard.swift — A month's digest: headline, stats and linked items
// =============================================================================

import SwiftUI
import SharedModels

struct MonthDigestCard: View {
    let digest: MonthDigest
    /// All, or only the Work or Personal side of the month
    let filter: ItemFilter
    let isUpdating: Bool
    /// The month was saved before work and personal were separate and is being split now
    var isSplitting: Bool = false
    let onCopy: () -> Void
    let onRegenerate: () -> Void
    private static let collapsedCount = 5

    @State private var expandedKinds: Set<DigestItemKind> = []

    private var story: (headline: String?, narrative: String?) { digest.story(for: filter) }

    private var monthName: String { digest.monthStart.formatted(.dateTime.month(.wide)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if isSplitting {
                Label("Separating this month into work and personal. It only happens once.", systemImage: "arrow.triangle.branch")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let stats = digest.stats(for: filter) {
                content(stats: stats)
            } else if digest.sections == nil {
                // Saved before work and personal were split; it is rebuilt when the month is opened
                Text(isUpdating ? "Separating work and personal…" : "Rebuild this month to separate work and personal.")
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                // This category had no recordings this month
                Text("No \(filter == .workOnly ? "work" : "personal") recordings in \(monthName).")
                    .font(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .graphiteCard()
    }

    @ViewBuilder
    private func content(stats: DigestStats) -> some View {
        if let headline = story.headline {
            Text(headline)
                .font(AppTheme.titleFont(size: 22))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let narrative = story.narrative {
            Text(narrative)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }

        // A month with both journals has no single story under All; show each journal's own
        if filter == .all, story.headline == nil, story.narrative == nil {
            ForEach(digest.journalStories, id: \.title) { journal in
                VStack(alignment: .leading, spacing: 4) {
                    Text(journal.title.uppercased())
                        .font(.caption)
                        .tracking(0.8)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(journal.story)
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        statsRow(stats)

        ForEach(DigestItemKind.displayOrder, id: \.self) { kind in
            let items = digest.items(of: kind, filter: filter)
            if !items.isEmpty {
                section(kind: kind, items: items)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(filter == .all ? "MONTH DIGEST" : "MONTH DIGEST · \(filter == .workOnly ? "WORK" : "PERSONAL")")
                        .font(.caption)
                        .tracking(0.8)
                        .foregroundStyle(AppTheme.textSecondary)
                    if !digest.isFinal {
                        StatusPill(text: "In progress", color: AppTheme.textSecondary)
                    }
                }
                Text(digest.monthStart.formatted(.dateTime.month(.wide).year()))
                    .font(AppTheme.titleFont(size: 24))
                    .foregroundStyle(AppTheme.textPrimary)
                if !digest.isFinal {
                    Text("Updates as you record until the month ends")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                IconSquareButton(systemImage: "doc.on.doc", accessibilityLabel: "Copy month", action: onCopy)
                if isUpdating {
                    ProgressView()
                        .frame(width: 36, height: 36)
                        .accessibilityLabel("Updating digest")
                } else {
                    IconSquareButton(systemImage: "arrow.clockwise", accessibilityLabel: "Rebuild digest", action: onRegenerate)
                }
            }
        }
    }

    private func statsRow(_ stats: DigestStats) -> some View {
        var parts = [
            stats.sessionCount == 1 ? "1 recording" : "\(stats.sessionCount) recordings",
            stats.activeDays == 1 ? "1 day" : "\(stats.activeDays) days",
            "\(stats.totalMinutes) min"
        ]
        if filter == .all && (stats.workCount > 0 || stats.personalCount > 0) {
            parts.append("\(stats.workCount) work · \(stats.personalCount) personal")
        }
        return Text(parts.joined(separator: " · "))
            .font(.footnote)
            .foregroundStyle(AppTheme.textSecondary)
    }

    // MARK: - Sections

    private func section(kind: DigestItemKind, items: [DigestItem]) -> some View {
        let isExpanded = expandedKinds.contains(kind)
        let shown = isExpanded ? items : Array(items.prefix(Self.collapsedCount))

        return VStack(alignment: .leading, spacing: 8) {
            Label(kind.displayName, systemImage: kind.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(shown) { item in
                itemRow(item)
            }

            if items.count > Self.collapsedCount {
                Button(isExpanded ? "Show less" : "Show all \(items.count)") {
                    if isExpanded { expandedKinds.remove(kind) } else { expandedKinds.insert(kind) }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.top, 4)
    }

    private func categoryMark(_ category: ItemCategory) -> some View {
        let icons: [String] = switch category {
        case .work: ["briefcase"]
        case .personal: ["house"]
        case .both: ["briefcase", "house"]
        }
        let label = switch category {
        case .work: "Work"
        case .personal: "Personal"
        case .both: "Work and personal"
        }
        return HStack(spacing: 3) {
            ForEach(icons, id: \.self) { Image(systemName: $0) }
        }
        .font(.caption2)
        .foregroundStyle(AppTheme.textSecondary)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func itemRow(_ item: DigestItem) -> some View {
        let content = HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.text)
                .font(.callout)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            // Under All, mark which side of life each item comes from
            if filter == .all, let category = item.category {
                categoryMark(category)
            }
            if let status = item.status {
                StatusPill(text: status.rawValue.capitalized, color: AppTheme.textSecondary)
            }
            if item.mentions > 1 {
                Text("×\(item.mentions)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityLabel("mentioned in \(item.mentions) recordings")
            }
            if !item.sessionIds.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 2)

        if item.sessionIds.isEmpty {
            content
        } else {
            NavigationLink {
                FilteredSessionsView(title: item.text, sessionIds: item.sessionIds)
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the recordings this came from")
        }
    }
}
