import SwiftUI

struct SignedInView: View {
    let credential: Credential
    let onSignOut: () -> Void

    @State private var loadError: String?
    @State private var reloadToken = UUID()

    var body: some View {
        MemoriesWebView(
            credential: credential,
            onLoadError: { loadError = $0.localizedDescription },
            onSignOut: onSignOut
        )
        .id(reloadToken)
        .ignoresSafeArea(edges: .bottom)
        .alert("Couldn't load Memories", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("Retry") {
                loadError = nil
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
}
