import SwiftUI
import SharedModels

struct ContentView: View {
    @State private var listeningState: ListeningState = .idle
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Status Display
                VStack(spacing: 12) {
                    Image(systemName: listeningState.systemImage)
                        .font(.system(size: 60))
                        .foregroundStyle(statusColor)
                    
                    Text(listeningState.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding()
                
                // Control Buttons
                VStack(spacing: 16) {
                    if listeningState.canStart {
                        Button(action: startListening) {
                            Label("Start Listening", systemImage: "mic.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    
                    if listeningState.canStop {
                        Button(action: stopListening) {
                            Label("Stop Listening", systemImage: "stop.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.red)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Placeholder for stats
                Text("Stats and insights will appear here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .navigationTitle("Life Wrapped")
            .padding()
        }
    }
    
    private var statusColor: Color {
        switch listeningState {
        case .idle: .gray
        case .starting: .orange
        case .listening: .green
        case .paused: .yellow
        case .stopping: .orange
        case .error: .red
        }
    }
    
    private func startListening() {
        listeningState = .listening(mode: .active)
        // TODO: Connect to AudioCapture
    }
    
    private func stopListening() {
        listeningState = .idle
        // TODO: Connect to AudioCapture
    }
}

#Preview {
    ContentView()
}
