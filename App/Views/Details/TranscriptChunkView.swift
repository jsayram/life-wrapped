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
                            .foregroundStyle(isCurrentChunk ? AppTheme.accent : .secondary)
                            .fontWeight(isCurrentChunk ? .semibold : .regular)
                        
                        if let chunkId = chunkId {
                            transcriptionStatusBadge(for: chunkId)
                        }
                        
                        if isEdited {
                            HStack(spacing: 2) {
                                Image(systemName: "pencil")
                                    .font(.caption2)
                                Text("Edited")
                                    .font(.caption2)
                            }
                            .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                } else if isEdited {
                    HStack(spacing: 2) {
                        Image(systemName: "pencil")
                            .font(.caption2)
                        Text("Edited")
                            .font(.caption2)
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                }
                
                Spacer()
                
                // Action buttons - compact
                if !combinedText.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            editedText = combinedText
                            isEditing = true
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "pencil")
                                Text("Edit")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit part \(chunkIndex + 1)")
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
            onSeekToChunk()
        }
        .sheet(isPresented: $isEditing) {
            editorSheet
        }
        .animation(.easeInOut(duration: 0.15), value: isEditing)
        .animation(.easeInOut(duration: 0.3), value: isCurrentChunk)
        .animation(.easeInOut(duration: 0.3), value: isEdited)
    }
    
    // Only the playing part is highlighted; an edit is shown by its "Edited" badge alone
    private var chunkBackground: Color {
        if isCurrentChunk {
            return AppTheme.accent.opacity(0.1)
        } else {
            return Color.clear
        }
    }
    
    private var chunkBorderColor: Color {
        if isCurrentChunk {
            return AppTheme.accent.opacity(0.5)
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
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    AppTheme.accent.opacity(0.2)
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
                .foregroundColor(AppTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    AppTheme.accent.opacity(0.2)
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
                .foregroundColor(AppTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    AppTheme.textSecondary.opacity(0.2)
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
                        Text("Retry transcription")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AppTheme.onAccent)  // light fill in dark mode needs dark text
                .tint(AppTheme.magenta)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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
    
    /// Full-screen editor: room for long text, paste and dictation, and Cancel/Save where iOS puts them
    private var editorSheet: some View {
        NavigationStack {
            TextEditor(text: $editedText)
                .font(.body)
                .focused($isTextFocused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .background(AppTheme.background)
                .navigationTitle(session.chunkCount > 1 ? "Edit part \(chunkIndex + 1)" : "Edit transcript")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { cancelEdit() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveEdit() }
                            .fontWeight(.semibold)
                            .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editedText == combinedText)
                    }
                }
                .onAppear { isTextFocused = true }
        }
        // Swiping down would throw away changes; make the user pick Cancel or Save
        .interactiveDismissDisabled(editedText != combinedText)
    }

    private func cancelEdit() {
        isTextFocused = false
        isEditing = false
        editedText = ""
    }

    private func saveEdit() {
        let trimmedText = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, trimmedText != combinedText, let firstSegment = segments.first else {
            cancelEdit()
            return
        }
        
        // Save the edited text to the first segment (we combine all segments into one for simplicity)
        onTextEdited(firstSegment.id, trimmedText)
        isTextFocused = false
        isEditing = false
        editedText = ""
    }
}

