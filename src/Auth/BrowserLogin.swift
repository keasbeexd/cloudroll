import AuthenticationServices
import UIKit

/// Runs Login Flow v2 in a system browser sheet. The flow never redirects back to the
/// app, so the sheet is closed by us once polling returns a credential.
@MainActor
struct BrowserLogin {
    private let flow = LoginFlow()
    private let anchorProvider = KeyWindowAnchor()

    /// Throws `CancellationError` when the user closes the sheet. `privately` keeps Safari's
    /// cookies out, so adding a second account on the same server doesn't reuse the first.
    func signIn(server: URL, privately: Bool = false) async throws -> Credential {
        let start = try await flow.start(server: server)
        let polling = Task { try await flow.waitForCredential(start.poll) }

        // Only called when the user dismisses the sheet before approving.
        let session = ASWebAuthenticationSession(url: start.login, callbackURLScheme: nil) { _, _ in
            polling.cancel()
        }
        session.presentationContextProvider = anchorProvider
        session.prefersEphemeralWebBrowserSession = privately
        guard session.start() else {
            polling.cancel()
            throw LoginError.browserUnavailable
        }
        defer { session.cancel() }
        return try await polling.value
    }
}

private final class KeyWindowAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
