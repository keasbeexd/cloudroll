import SwiftUI

@main
struct CloudrollApp: App {
    init() {
        TipJar.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
