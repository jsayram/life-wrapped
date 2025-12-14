// =============================================================================
// ToastView — Toast notification component
// =============================================================================

import SwiftUI

/// Toast notification style
enum ToastStyle {
    case success
    case error
    case info
    case warning
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        case .warning: return .orange
        }
    }
}

/// Toast notification data
struct Toast: Equatable, Identifiable {
    let id = UUID()
    let style: ToastStyle
    let message: String
    let duration: TimeInterval
    
    init(style: ToastStyle, message: String, duration: TimeInterval = 3.0) {
        self.style = style
        self.message = message
        self.duration = duration
    }
    
    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }
}

/// Toast view modifier
struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toast {
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + toast.duration) {
                                withAnimation {
                                    self.toast = nil
                                }
                            }
                        }
                        .padding(.top, 50)
                }
            }
    }
}

/// Toast notification view
struct ToastView: View {
    let toast: Toast
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.style.icon)
                .font(.title3)
                .foregroundColor(toast.style.color)
            
            Text(toast.message)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
    }
}

// MARK: - View Extension

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}

// MARK: - Preview

#Preview("Success Toast") {
    VStack {
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.gray.opacity(0.1))
    .toast(.constant(Toast(style: .success, message: "Recording saved successfully!")))
}

#Preview("Error Toast") {
    VStack {
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.gray.opacity(0.1))
    .toast(.constant(Toast(style: .error, message: "Failed to start recording. Please check microphone permissions.")))
}

#Preview("Info Toast") {
    VStack {
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.gray.opacity(0.1))
    .toast(.constant(Toast(style: .info, message: "Processing your recording...")))
}
