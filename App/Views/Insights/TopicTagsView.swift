import SwiftUI
import SharedModels


struct TopicTagsView: View {
    let topicsJSON: String
    @State private var topics: [String] = []
    
    var body: some View {
        if !topics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Topics")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                FlowLayout(spacing: 8) {
                    ForEach(topics, id: \.self) { topic in
                        Text(topic.capitalized)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            .task {
                parseTopics()
            }
        }
    }
    
    private func parseTopics() {
        do {
            let parsed = try [String].fromTopicsJSON(topicsJSON)
            // Limit to top 10 topics for display
            topics = Array(parsed.prefix(10))
        } catch {
            print("⚠️ [TopicTagsView] Failed to parse topics: \(error)")
        }
    }
}

// MARK: - Intelligence Engine View

