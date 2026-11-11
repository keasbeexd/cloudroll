#if SCREENSHOTS
import Foundation

/// Signs in the App Review demo account for the screenshot run, which can't drive the
/// browser sheet. Only compiled with the SCREENSHOTS flag that .github/workflows/screenshots.yml
/// sets, so TestFlight and App Store builds never contain it.
enum ScreenshotAccount {
    /// Fixed, so every run replaces the same Keychain item.
    private static let id = UUID(uuidString: "5C2EE45A-0000-4000-8000-000000000001")!

    static func installFromEnvironment() throws {
        let env = ProcessInfo.processInfo.environment
        guard let serverInput = env["CLOUDROLL_DEMO_SERVER"],
              let server = ServerURL.root(from: serverInput),
              let login = env["CLOUDROLL_DEMO_LOGIN"], !login.isEmpty,
              let password = env["CLOUDROLL_DEMO_APP_PASSWORD"], !password.isEmpty
        else { return }

        let credential = Credential(server: server, loginName: login, appPassword: password)
        try AccountStore.save(Account(id: id, credential: credential, displayName: env["CLOUDROLL_DEMO_NAME"]))
        AccountStore.currentID = id
    }
}
#endif
