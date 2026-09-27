import SwiftUI
import SharedModels
import Summarization


struct GenerateYearWrapCard: View {
    let onGenerate: () -> Void
    
    var body: some View {
        Button {
            onGenerate()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Wrap your year")
                    .font(AppTheme.titleFont(size: 24))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Your year so far, with a wrap for work, one for personal life and one for everything together. It runs in the background while you use the app.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label("Generate", systemImage: "sparkles")
                    .fontWeight(.semibold)
                    .font(.body)
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous)
                            .fill(AppTheme.accent)
                    )
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .fill(AppTheme.card)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Year Wrap Progress Card

/// Takes the Year Wrap card's place while a wrap is being written. Nothing is locked:
/// the run belongs to AppCoordinator, so the user can leave this screen and come back.
struct YearWrapProgressCard: View {
    let year: Int
    let progress: YearWrapProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YEAR WRAPPED · \(String(year))")
                .font(.caption)
                .tracking(0.8)
                .foregroundStyle(AppTheme.onAccent.opacity(0.7))

            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .symbolEffect(.pulse)
                    .accessibilityHidden(true)
                Text("Wrapping up your year")
                    .font(AppTheme.titleFont(size: 26))
            }
            .foregroundStyle(AppTheme.onAccent)

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress?.fractionDone ?? 0)
                    .tint(AppTheme.onAccent)
                    .animation(.easeInOut(duration: 0.4), value: progress?.fractionDone)

                HStack {
                    Text(progress?.label ?? "Getting ready")
                        .contentTransition(.opacity)
                        .animation(.easeInOut, value: progress?.label)
                    Spacer()
                    if let progress, progress.total > 1 {
                        Text("Step \(progress.step) of \(progress.total)")
                            .monospacedDigit()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.onAccent.opacity(0.85))
            }

            if let note = progress?.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.onAccent.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("You can keep using the app. You'll get a message here when it's ready.")
                .font(.footnote)
                .foregroundStyle(AppTheme.onAccent.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.accent)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Missing Category Wrap Card

/// Shown under Work or Personal when there's a wrap for the year but none for that category
struct MissingCategoryWrapCard: View {
    let filter: ItemFilter
    let onGenerate: () -> Void

    private var name: String { filter == .workOnly ? "work" : "personal" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No \(name) wrap yet")
                .font(AppTheme.titleFont(size: 22))
                .foregroundStyle(AppTheme.textPrimary)
            Text("A \(name) wrap is written only from recordings whose category is \(name.capitalized). Set that on a few recordings, then generate again.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onGenerate) {
                Label("Generate again", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.accent)
            .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.card)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Topic Tags View

