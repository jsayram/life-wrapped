import SwiftUI
import Summarization

struct EngineSelectionRow: View {
    let tier: EngineTier
    let isActive: Bool
    let isAvailable: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: tier.icon)
                    .font(.title3)
                    .foregroundStyle(isAvailable ? .blue : .secondary)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName)
                        .font(.body)
                        .foregroundStyle(isAvailable ? .primary : .secondary)
                    
                    Text(tier.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if !isAvailable {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
