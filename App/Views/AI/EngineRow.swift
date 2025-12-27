import SwiftUI
import Summarization


struct EngineRow: View {
    let tier: EngineTier
    let isActive: Bool
    let isAvailable: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(isAvailable ? iconColor : iconColor.opacity(0.3))
                .frame(width: 32, height: 32)
            
            // Name and description
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(tier.displayName)
                        .font(.body)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundStyle(isAvailable ? .primary : .secondary)
                    
                    if isActive {
                        Text("Active")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.green.gradient)
                            .clipShape(Capsule())
                    } else if isAvailable && !isActive {
                        Text("Available")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.1))
                            .clipShape(Capsule())
                    } else if !isAvailable {
                        Text("Unavailable")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.gray.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                
                Text(tier.description)
                    .font(.caption)
                    .foregroundStyle(isAvailable ? .secondary : .tertiary)
                    .lineLimit(2)
                
                // Attributes
                HStack(spacing: 12) {
                    AttributeBadge(
                        icon: tier.isPrivacyPreserving ? "lock.fill" : "lock.open.fill",
                        text: tier.isPrivacyPreserving ? "Private" : "Cloud",
                        color: tier.isPrivacyPreserving ? .green : .orange,
                        isAvailable: isAvailable
                    )
                    
                    if tier.requiresInternet {
                        AttributeBadge(
                            icon: "wifi",
                            text: "Internet",
                            color: .blue,
                            isAvailable: isAvailable
                        )
                    }
                }
                .padding(.top, 4)
            }
            
            Spacer()
            
            // Chevron for available engines
            if isAvailable && !isActive {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.green.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isActive ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .opacity(isAvailable ? 1.0 : 0.5)
    }
    
    private var iconName: String {
        switch tier {
        case .basic: return "text.alignleft"
        case .local: return "cpu"
        case .apple: return "apple.logo"
        case .external: return "cloud"
        }
    }
    
    private var iconColor: Color {
        switch tier {
        case .basic: return .gray
        case .local: return .purple
        case .apple: return .blue
        case .external: return .orange
        }
    }
}

struct AttributeBadge: View {
    let icon: String
    let text: String
    let color: Color
    var isAvailable: Bool = true
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(isAvailable ? color : color.opacity(0.4))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isAvailable ? color.opacity(0.1) : color.opacity(0.05))
        .clipShape(Capsule())
    }
}

// MARK: - External AI View

