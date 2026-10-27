import SwiftUI

struct RootView: View {
    @State private var model = AppModel()
    @State private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .environment(lock)
            .onChange(of: scenePhase, initial: true) { _, phase in lock.sceneChanged(to: phase) }
            .alert("Cloudroll", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let credential = model.credential {
            SignedInView(credential: credential) {
                Task { await model.signOut() }
            }
        } else {
            ServerSetupView(isBusy: model.isSigningIn) { input in
                Task { await model.signIn(serverInput: input) }
            }
        }
    }
}
