import SwiftUI

/// Loading overlay shown during app initialization
struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            LoadingView(size: .large)
        }
    }
}
