//
//  YearWrapLoadingOverlay.swift
//  LifeWrapped
//

import SwiftUI

/// Shown while a Year Wrap is being generated.
/// Graphite style: dimmed backdrop, one flat card, system spinner, step dots in ink.
struct YearWrapLoadingOverlay: View {
    let statusMessage: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .scaledFont(size: 28, weight: .regular)
                    .foregroundStyle(AppTheme.textPrimary)
                    .symbolEffect(.pulse)

                Text("Wrapping up your year")
                    .scaledFont(size: 24, design: .serif)
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.easeInOut, value: statusMessage)
                }

                if let progress = stepProgress {
                    let current = progress.current, total = progress.total
                    if total <= 6 {
                        HStack(spacing: 8) {
                            ForEach(1...total, id: \.self) { step in
                                Capsule()
                                    .fill(step <= current ? AppTheme.accent : AppTheme.hairline)
                                    .frame(width: 24, height: 4)
                            }
                        }
                        .accessibilityLabel("Step \(current) of \(total)")
                    } else {
                        ProgressView(value: Double(current), total: Double(total))
                            .tint(AppTheme.accent)
                            .frame(maxWidth: 200)
                            .accessibilityLabel("Step \(current) of \(total)")
                    }
                }

                ProgressView()
                    .tint(AppTheme.textPrimary)
                    .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 400)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .fill(AppTheme.card)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
            .padding(.horizontal, 32)
        }
    }

    /// Reads the step from messages like "Step 2 of 5: March digest"
    private var stepProgress: (current: Int, total: Int)? {
        guard let range = statusMessage.range(of: "Step \\d+ of \\d+", options: .regularExpression) else { return nil }
        let numbers = statusMessage[range].split(separator: " ").compactMap { Int($0) }
        guard numbers.count == 2, numbers[1] > 0 else { return nil }
        return (min(numbers[0], numbers[1]), numbers[1])
    }
}

#Preview {
    YearWrapLoadingOverlay(statusMessage: "Step 2 of 5: February digest")
}
