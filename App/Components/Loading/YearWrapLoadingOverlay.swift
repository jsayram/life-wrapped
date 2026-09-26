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
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(AppTheme.textPrimary)
                    .symbolEffect(.pulse)

                Text("Wrapping up your year")
                    .font(AppTheme.titleFont(size: 24))
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

                if let current = currentStep {
                    HStack(spacing: 8) {
                        ForEach(1...3, id: \.self) { step in
                            Capsule()
                                .fill(step <= current ? AppTheme.accent : AppTheme.hairline)
                                .frame(width: 24, height: 4)
                        }
                    }
                    .accessibilityLabel("Step \(current) of 3")
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

    /// Reads the step from messages like "Step 2 of 3: Work Year Wrap"
    private var currentStep: Int? {
        guard let range = statusMessage.range(of: "Step \\d+", options: .regularExpression),
              let number = statusMessage[range].split(separator: " ").last else { return nil }
        return Int(number)
    }
}

#Preview {
    YearWrapLoadingOverlay(statusMessage: "Step 2 of 3: Work Year Wrap")
}
