import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class AppModel {
    private(set) var credential: Credential?
    private(set) var isSigningIn = false
    var errorMessage: String?

    init() {
        do {
            credential = try CredentialStore.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(serverInput: String) async {
        guard let server = ServerURL.root(from: serverInput) else {
            errorMessage = "Enter the full https:// address of your Nextcloud, e.g. https://cloud.example.com"
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let credential = try await BrowserLogin().signIn(server: server)
            try CredentialStore.save(credential)
            self.credential = credential
        } catch is CancellationError {
            // The user closed the sign-in sheet.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        guard let credential else { return }
        do {
            try CredentialStore.delete()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        self.credential = nil
        // Drop the web session cookie so the next account starts clean.
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )

        do {
            try await NextcloudAPI.revokeAppPassword(credential)
        } catch {
            errorMessage = "Signed out, but the app password couldn't be revoked on the server "
                + "(\(error.localizedDescription)). Remove it under Personal settings → Security."
        }
    }
}
