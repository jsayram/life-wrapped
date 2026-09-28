import SwiftUI
import Summarization

struct SummaryQualityCard: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let detail: String
    let tier: EngineTier
    let isSelected: Bool
    let isAvailable: Bool
    var showsLock: Bool = false
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: systemImage)
                    .scaledFont(size: 18, weight: .regular)
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        if showsLock {
                            Image(systemName: "lock")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .accessibilityLabel("Locked")
                        }
                    }

                    // Fixed two-line slot so rows never change height when the
                    // text changes (e.g. switching provider or model on Smartest)
                    Text("\(subtitle)\n\(detail)")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2, reservesSpace: true)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Radio on the right
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? AppTheme.accent : AppTheme.hairline, lineWidth: isSelected ? 2 : 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 10, height: 10)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .opacity(isAvailable ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
