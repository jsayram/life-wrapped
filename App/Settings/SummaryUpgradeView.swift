// =============================================================================
// SummaryUpgradeView.swift — Which recordings a stronger engine would rewrite, and what happened
// =============================================================================
//
// Nothing is rewritten from this screen until the person taps Upgrade. Before that it
// lists every recording that would change and the engine that wrote its current
// summary. While the upgrade runs each row shows its state, and afterwards the list
// stays as a record: upgraded, or kept with the reason.
//

import SwiftUI
import SharedModels
import Summarization

struct SummaryUpgradeView: View {
    let tier: EngineTier
    @EnvironmentObject var coordinator: AppCoordinator

    @State private var candidates: [AppCoordinator.SummaryUpgradeCandidate] = []
    @State private var isLoading = true
    @State private var showConfirmation = false

    /// The report for this engine, running or finished
    private var report: AppCoordinator.SummaryUpgradeReport? {
        coordinator.summaryUpgrade.flatMap { $0.tier == tier ? $0 : nil }
    }

    private var name: String { tier.displayName }

    /// Candidates not part of the running or finished report, so a recording is listed once
    private var pendingCandidates: [AppCoordinator.SummaryUpgradeCandidate] {
        guard let report else { return candidates }
        return candidates.filter { report.outcomes[$0.sessionId] == nil }
    }

    var body: some View {
        List {
            if let report, report.isRunning || pendingCandidates.isEmpty {
                reportSection(report)
            }
            if !pendingCandidates.isEmpty {
                candidatesSection
            } else if !isLoading && report == nil {
                ContentUnavailableView("Nothing to upgrade", systemImage: "checkmark.circle",
                                       description: Text("Every recording is already summarized by \(name) or something stronger."))
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Earlier summaries")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: coordinator.summaryUpgrade) { _, report in
            if report?.isRunning == false {
                Task { await load() }
            }
        }
        .alert("Upgrade \(pendingCandidates.count) \(pendingCandidates.count == 1 ? "recording" : "recordings")?", isPresented: $showConfirmation) {
            Button("Upgrade with \(name)") {
                coordinator.upgradeSummaries(pendingCandidates, with: tier)
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(Self.warning(for: tier, provider: providerName))
        }
    }

    // MARK: - Sections

    private var candidatesSection: some View {
        Section {
            ForEach(pendingCandidates) { candidate in
                row(candidate, trailing: {
                    Text(Self.engineName(candidate.engineTier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                })
            }
        } header: {
            HStack {
                Text(report?.isRunning == true ? "Still to do" : "Will be rewritten with \(name)")
                Spacer()
                if report?.isRunning != true {
                    Button("Upgrade \(pendingCandidates.count)") { showConfirmation = true }
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                }
            }
        } footer: {
            Text("Each recording's current summary is kept under Earlier versions, so this can be undone one by one. Months and the Year Wrap update as you open them.")
        }
    }

    private func reportSection(_ report: AppCoordinator.SummaryUpgradeReport) -> some View {
        Section {
            ForEach(report.candidates) { candidate in
                row(candidate, trailing: {
                    outcomeView(report.outcome(for: candidate))
                })
            }
        } header: {
            if report.isRunning {
                HStack {
                    Text("Upgrading \(report.doneCount) of \(report.candidates.count) with \(name)")
                    Spacer()
                    ProgressView()
                }
            } else {
                Text("Last upgrade with \(name) · \(report.finishedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")")
            }
        } footer: {
            if !report.isRunning {
                Text("\(report.upgradedCount) upgraded, \(report.keptCount) kept. A kept recording still has its earlier summary; try again later or open it to regenerate.")
            }
        }
    }

    // MARK: - Rows

    private func row(_ candidate: AppCoordinator.SummaryUpgradeCandidate, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title ?? "Recording")
                    .font(.body)
                    .lineLimit(2)
                Text(Self.subtitle(for: candidate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func outcomeView(_ outcome: AppCoordinator.SummaryUpgradeOutcome) -> some View {
        switch outcome {
        case .waiting:
            Text("Waiting")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .upgrading:
            ProgressView()
        case .upgraded(let engine):
            Label("Upgraded", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .accessibilityLabel("Upgraded with \(engine.displayName)")
        case .kept(let reason):
            VStack(alignment: .trailing, spacing: 2) {
                Label("Kept", systemImage: "arrow.uturn.backward.circle")
                    .font(.caption.weight(.semibold))
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 160, alignment: .trailing)
            }
        }
    }

    // MARK: - Helpers

    private func load() async {
        isLoading = true
        candidates = await coordinator.upgradeableSummaries(for: tier)
        isLoading = false
    }

    private var providerName: String {
        UserDefaults.standard.string(forKey: "externalAPIProvider") ?? "OpenAI"
    }

    static func engineName(_ stored: String?) -> String {
        stored.flatMap(EngineTier.init(rawValue:))?.displayName ?? "an earlier option"
    }

    static func subtitle(for candidate: AppCoordinator.SummaryUpgradeCandidate) -> String {
        var parts = [candidate.date.formatted(date: .abbreviated, time: .shortened)]
        if let category = candidate.category { parts.append(category.displayName) }
        return parts.joined(separator: " · ")
    }

    /// What the person agrees to before the upgrade runs
    static func warning(for tier: EngineTier, provider: String) -> String {
        switch tier {
        case .external:
            return "Sends the transcript of each recording to \(provider) with your API key. What it costs depends on your plan and the length of the recordings. Keep the app open."
        case .local:
            return "Runs the offline model once per recording. It can take a while; keep the app open and plugged in."
        case .apple:
            return "Runs Apple Intelligence once per recording on this \(DeviceName.current). Keep the app open."
        case .basic:
            return ""
        }
    }
}
