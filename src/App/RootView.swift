import SwiftUI

struct RootView: View {
    @AppStorage("serverURL") private var serverURL = ""
    @State private var loadError: String?
    @State private var reloadToken = UUID()

    var body: some View {
        guard let url = MemoriesURL.make(from: serverURL) else {
            return AnyView(ServerSetupView(serverURL: $serverURL))
        }
        return AnyView(
            MemoriesWebView(url: url) { loadError = $0.localizedDescription }
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
                    Button("Change server", role: .destructive) {
                        loadError = nil
                        serverURL = ""
                    }
                } message: {
                    Text(loadError ?? "")
                }
        )
    }
}
