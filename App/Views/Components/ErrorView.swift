// =============================================================================
// ErrorView — Error display component
// =============================================================================

import SwiftUI

/// User-friendly error presentation
struct ErrorView: View {
    let error: Error
    let onRetry: (() async -> Void)?
    let onDismiss: (() -> Void)?
    
    init(error: Error, onRetry: (() async -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.error = error
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: errorIcon)
                .font(.system(size: 60))
                .foregroundStyle(.red.gradient)
            
            // Title
            Text(errorTitle)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            
            // Message
            Text(errorMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Actions
            VStack(spacing: 12) {
                if let onRetry = onRetry {
                    Button {
                        Swift.Task {
                            await onRetry()
                        }
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                
                if let onDismiss = onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Dismiss")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .padding()
    }
    
    // MARK: - Error Formatting
    
    private var errorIcon: String {
        if isPermissionError {
            return "lock.shield.fill"
        } else if isNetworkError {
            return "wifi.slash"
        } else if isStorageError {
            return "externaldrive.fill.badge.exclamationmark"
        } else {
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var errorTitle: String {
        if isPermissionError {
            return "Permission Required"
        } else if isNetworkError {
            return "Connection Issue"
        } else if isStorageError {
            return "Storage Error"
        } else {
            return "Something Went Wrong"
        }
    }
    
    private var errorMessage: String {
        // Try to provide user-friendly messages
        let description = error.localizedDescription.lowercased()
        
        if description.contains("microphone") || description.contains("recording permission") {
            return "Life Wrapped needs microphone access to record audio. Please enable it in Settings."
        } else if description.contains("speech") || description.contains("recognition") {
            return "Life Wrapped needs speech recognition permission to transcribe audio. Please enable it in Settings."
        } else if description.contains("storage") || description.contains("disk") || description.contains("space") {
            return "There's not enough storage space available. Please free up some space and try again."
        } else if description.contains("network") || description.contains("connection") {
            return "Please check your internet connection and try again."
        } else if description.contains("database") {
            return "There was a problem accessing your data. Please try restarting the app."
        } else {
            // Fall back to original error message
            return error.localizedDescription
        }
    }
    
    private var isPermissionError: Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("permission") || 
               description.contains("authorized") || 
               description.contains("microphone") ||
               description.contains("speech")
    }
    
    private var isNetworkError: Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("network") || 
               description.contains("connection") ||
               description.contains("internet")
    }
    
    private var isStorageError: Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("storage") || 
               description.contains("disk") ||
               description.contains("space") ||
               description.contains("database")
    }
}

/// Inline error banner for forms and lists
struct ErrorBanner: View {
    let message: String
    let onDismiss: (() -> Void)?
    
    init(message: String, onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            if let onDismiss = onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
    }
}

// MARK: - Preview

struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ErrorView(
                error: NSError(
                    domain: "LifeWrapped",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"]
                ),
                onRetry: {
                    print("Retry tapped")
                },
                onDismiss: {
                    print("Dismiss tapped")
                }
            )
            .previewDisplayName("Permission Error")
            
            ErrorView(
                error: NSError(
                    domain: "LifeWrapped",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Database connection failed"]
                ),
                onRetry: {
                    print("Retry tapped")
                }
            )
            .previewDisplayName("Storage Error")
            
            VStack(spacing: 16) {
                ErrorBanner(message: "Recording failed. Please try again.")
                
                ErrorBanner(
                    message: "Network connection lost.",
                    onDismiss: {
                        print("Dismissed")
                    }
                )
            }
            .padding()
        }
    }
}
