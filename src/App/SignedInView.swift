import SwiftUI

struct SignedInView: View {
    let credential: Credential
    let onSignOut: () -> Void

    @State private var entry: URL?
    @State private var loadError: String?
    @State private var reloadToken = UUID()

    var body: some View {
        content
            .task(id: reloadToken) { await resolveEntry() }
            .alert("Couldn't load Memories", isPresented: Binding(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) {
                Button("Retry") {
                    loadError = nil
                    entry = nil
                    reloadToken = UUID()
                }
                Button("Sign out", role: .destructive) {
                    loadError = nil
                    onSignOut()
                }
            } message: {
                Text(loadError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let entry {
            MemoriesWebView(
                entry: entry,
                credential: credential,
                onLoadError: { loadError = $0.localizedDescription },
                onSignOut: onSignOut
            )
            .id(reloadToken)
            .ignoresSafeArea(edges: .bottom)
        } else {
            ProgressView()
        }
    }

    private func resolveEntry() async {
        guard entry == nil else { return }
        do {
            entry = try await NextcloudAPI.describeMemories(server: credential.server).entry(for: credential.server)
        } catch is CancellationError {
            // The view went away or a retry started a new attempt.
        } catch {
            loadError = error.localizedDescription
        }
    }
}
