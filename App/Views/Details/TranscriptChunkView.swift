import SwiftUI
import SharedModels


struct TranscriptChunkView: View {
    let chunkIndex: Int
    let segments: [TranscriptSegment]
    let session: RecordingSession
    let isCurrentChunk: Bool
    let chunkId: UUID?
    let coordinator: AppCoordinator
    let isEdited: Bool  // Track if this chunk was edited
    let onSeekToChunk: () -> Void
    let onTextEdited: (UUID, String) -> Void
    
    @State private var isEditing = false
    @State private var editedText: String = ""
    @FocusState private var isTextFocused: Bool
    
    private var combinedText: String {
        segments.map { $0.text }.joined(separator: " ")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Action buttons row at top right
            HStack {
                // Left side: Part label for multi-chunk, or edited badge
                if session.chunkCount > 1 {
                    HStack(spacing: 6) {
                        Text("Part \(chunkIndex + 1)")
                            .font(.caption)
                            .foregroundStyle(isCurrentChunk ? .blue : .secondary)
                            .fontWeight(isCurrentChunk ? .semibold : .regular)
                        
                        if let chunkId = chunkId {
                            transcriptionStatusBadge(for: chunkId)
                        }
                        
                        if isEdited {
                            HStack(spacing: 2) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.caption2)
                                Text("Edited")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                } else if isEdited {
                    HStack(spacing: 2) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.caption2)
                        Text("Edited")
                            .font(.caption2)
                    }
                    .foregroundStyle(.orange)
                }
                
                Spacer()
                
                // Action buttons - compact
                if !isEditing && !combinedText.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = combinedText
                            coordinator.showSuccess("Copied")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            editedText = combinedText
                            isEditing = true
                            isTextFocused = true
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "pencil")
                                Text("Edit")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Content
            chunkContent
        }
        .padding(10)
        .background(chunkBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(chunkBorderColor, lineWidth: 2)
        )
        .onTapGesture {
            if !isEditing {
                onSeekToChunk()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isCurrentChunk)
        .animation(.easeInOut(duration: 0.3), value: isEdited)
    }
    
    private var chunkBackground: Color {
        if isEdited {
            return Color.orange.opacity(0.08)
        } else if isCurrentChunk {
            return Color.blue.opacity(0.1)
        } else {
            return Color.clear
        }
    }
    
    private var chunkBorderColor: Color {
        if isEdited {
            return Color.orange.opacity(0.5)
        } else if isCurrentChunk {
            return Color.blue.opacity(0.5)
        } else {
            return Color.clear
        }
    }
    
    @ViewBuilder
    private func transcriptionStatusBadge(for chunkId: UUID) -> some View {
        Group {
            if coordinator.transcribingChunkIds.contains(chunkId) {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Transcribing...")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.05)],
                        center: .center,
                        startRadius: 5,
                        endRadius: 20
                    )
                )
                .clipShape(Capsule())
            } else if coordinator.transcribedChunkIds.contains(chunkId) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                    Text("Done")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RadialGradient(
                        colors: [Color.green.opacity(0.2), Color.green.opacity(0.05)],
                        center: .center,
                        startRadius: 5,
                        endRadius: 20
                    )
                )
                .clipShape(Capsule())
            } else if coordinator.failedChunkIds.contains(chunkId) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text("Failed")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RadialGradient(
                        colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.05)],
                        center: .center,
                        startRadius: 5,
                        endRadius: 20
                    )
                )
                .clipShape(Capsule())
            }
        }
    }
    
    @ViewBuilder
    private var chunkContent: some View {
        if let chunkId = chunkId, coordinator.failedChunkIds.contains(chunkId) {
            VStack(spacing: 12) {
                Text("Transcription failed for this part")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Button {
                    Task {
                        await coordinator.retryTranscription(chunkId: chunkId)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Transcription")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.magenta)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else if isEditing {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $editedText)
                    .font(.body)
                    .frame(minHeight: 200, maxHeight: 400)
                    .padding(12)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(12)
                    .focused($isTextFocused)
                    .scrollContentBackground(.hidden)
                
                HStack(spacing: 12) {
                    Button {
                        isEditing = false
                        editedText = ""
                    } label: {
                        Text("Cancel")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        saveEdit()
                    } label: {
                        Text("Save")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        } else {
            // Selectable text - user can select and copy individual words
            Text(combinedText)
                .font(.body)
                .foregroundStyle(isCurrentChunk ? .primary : .secondary)
                .textSelection(.enabled)
                .onTapGesture {
                    onSeekToChunk()
                }
        }
    }
    
    private func saveEdit() {
        let trimmedText = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, let firstSegment = segments.first else {
            isEditing = false
            return
        }
        
        // Save the edited text to the first segment (we combine all segments into one for simplicity)
        onTextEdited(firstSegment.id, trimmedText)
        isEditing = false
        editedText = ""
    }
}

