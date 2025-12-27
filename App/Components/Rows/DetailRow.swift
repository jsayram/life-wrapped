import SwiftUI


struct DetailRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .frame(width: 16)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Historical Data View

