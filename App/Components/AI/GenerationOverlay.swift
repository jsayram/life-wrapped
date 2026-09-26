import SwiftUI
import Summarization

/// Shown over a recording while its summary is being generated.
/// Graphite style: dimmed backdrop, one flat card, ink progress bar, outline icons.
struct GenerationOverlay: View {
    let progress: Double
    let phase: String
    let engineTier: EngineTier?

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: tierSymbol)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.fill)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Summarizing")
                            .font(AppTheme.titleFont(size: 22))
                            .foregroundStyle(AppTheme.textPrimary)
                        if let engineTier {
                            Text(engineTier.displayName)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }

                    Spacer()

                    Text("\(Int(progress * 100))%")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.fill)
                        Capsule()
                            .fill(AppTheme.accent)
                            .frame(width: geometry.size.width * min(max(progress, 0), 1))
                            .animation(.linear(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 6)

                if !phase.isEmpty {
                    Text(phase)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let engineTier {
                    Divider().overlay(AppTheme.hairline)

                    VStack(alignment: .leading, spacing: 10) {
                        Label {
                            Text(explanation(for: engineTier))
                        } icon: {
                            Image(systemName: engineTier == .external ? "cloud" : "lock")
                        }

                        Label {
                            Text("The summary is saved, so this only runs once.")
                        } icon: {
                            Image(systemName: "checkmark.circle")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .labelStyle(.titleAndIcon)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .fill(AppTheme.card)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Summarizing, \(Int(progress * 100)) percent")
    }

    /// Same symbols as the AI & Summaries settings
    private var tierSymbol: String {
        switch engineTier {
        case .basic: return "bolt"
        case .local: return "cpu"
        case .apple: return "sparkle"
        case .external: return "cloud"
        case nil: return "sparkle"
        }
    }

    private func explanation(for tier: EngineTier) -> String {
        switch tier {
        case .basic:
            return "Basic picks out the key sentences on your \(DeviceName.current). It's fast and works offline."
        case .local:
            return "Smart runs \(LocalEngine.modelDisplayName) on your \(DeviceName.current). Your transcript never leaves it."
        case .apple:
            return "Smarter uses Apple Intelligence on your \(DeviceName.current). Your transcript never leaves it."
        case .external:
            let provider = UserDefaults.standard.string(forKey: "externalAPIProvider") ?? "OpenAI"
            return "Smartest sends this transcript to \(provider) with your API key, then saves the summary here."
        }
    }
}
