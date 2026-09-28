// =============================================================================
// SummaryVersionsSheet.swift — Earlier versions of a summary, with Restore
// =============================================================================
//
// Every rewrite of a recording's summary, a month digest or a Year Wrap keeps
// the text it replaced. This sheet lists those versions, newest first, and puts
// one back as the current summary. Restoring keeps the replaced text too, so
// nothing here is one-way.
//

import SwiftUI
import SharedModels
import Storage
import Summarization

struct SummaryVersionsSheet: View {
    /// The current summaries to show history for: one recording, one Year Wrap, or a month's
    /// journal digests (one row per journal)
    let rows: [Summary]
    let coordinator: AppCoordinator
    /// Called after a version was restored, so the screen behind can reload
    let onRestored: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var current: [Summary] = []
    @State private var versions: [UUID: [SummaryVersion]] = [:]
    @State private var isLoading = true
    @State private var restoring: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if current.isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("There is no summary to keep versions of."))
                } else {
                    List {
                        ForEach(current) { row in
                            Section {
                                versionRow(engine: row.engineTier, date: row.createdAt, text: row.text, type: row.periodType, isCurrent: true)
                                let history = versions[row.id] ?? []
                                if history.isEmpty {
                                    Text("No earlier versions. One is kept each time this summary is rewritten.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(history) { version in
                                    versionRow(engine: version.engineTier, date: version.createdAt, text: version.text, type: row.periodType, isCurrent: false) {
                                        Button {
                                            Task { await restore(version, replacing: row) }
                                        } label: {
                                            if restoring == version.id {
                                                ProgressView()
                                            } else {
                                                Text("Restore")
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(restoring != nil)
                                    }
                                }
                            } header: {
                                if current.count > 1 {
                                    Text(row.category?.displayName ?? "Month")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func versionRow(engine: String?, date: Date, text: String, type: PeriodType, isCurrent: Bool,
                            @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(engineName(engine), systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                if isCurrent {
                    Text("Current")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.accent.opacity(0.15), in: Capsule())
                }
                Spacer()
                trailing()
            }
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Self.preview(text, type: type))
                .font(.footnote)
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .lineLimit(isCurrent ? 6 : 4)
        }
        .padding(.vertical, 4)
    }

    private func engineName(_ stored: String?) -> String {
        guard let stored else { return "Unknown engine" }
        return stored.split(separator: "+").map { EngineTier(rawValue: String($0))?.displayName ?? "AI" }.joined(separator: " and ")
    }

    /// Readable text for a version: the summary itself, a month's headline and story, or a wrap's title
    static func preview(_ text: String, type: PeriodType) -> String {
        switch type {
        case .monthDigest:
            guard let digest = MonthDigest.fromJSON(text) else { return text }
            let story = [digest.headline, digest.narrative].compactMap { $0 }
            if !story.isEmpty { return story.joined(separator: " ") }
            let journals = digest.journalStories.map { "\($0.title): \($0.story)" }
            return journals.isEmpty ? "\(digest.items.count) items, \(digest.stats.sessionCount) recordings" : journals.joined(separator: " ")
        case .yearWrap, .yearWrapWork, .yearWrapPersonal:
            guard let wrap = YearWrapData.parse(text) else { return text }
            return [wrap.yearTitle, wrap.yearSummary].joined(separator: ". ")
        default:
            return text.withoutSummaryTitlePrefix
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let db = coordinator.getDatabaseManager() else { return }
        var fresh: [Summary] = []
        var history: [UUID: [SummaryVersion]] = [:]
        for row in rows {
            // Re-read the row: a restore changes it
            let latest = (try? await db.fetchSummary(id: row.id)) ?? row
            fresh.append(latest)
            history[latest.id] = (try? await db.fetchSummaryVersions(for: latest)) ?? []
        }
        current = fresh
        versions = history
    }

    private func restore(_ version: SummaryVersion, replacing row: Summary) async {
        guard let db = coordinator.getDatabaseManager() else { return }
        restoring = version.id
        defer { restoring = nil }
        do {
            try await db.restoreSummaryVersion(version, replacing: row)
            if let sessionId = row.sessionId {
                try? await db.markSessionChanged(sessionId: sessionId, content: true)
                NotificationCenter.default.post(name: .sessionSummaryUpdated, object: sessionId)
            }
            NotificationCenter.default.post(name: .periodSummariesUpdated, object: nil)
            coordinator.showSuccess("Restored the \(engineName(version.engineTier)) version")
            await load()
            onRestored()
        } catch {
            coordinator.showError("Couldn't restore this version")
        }
    }
}
