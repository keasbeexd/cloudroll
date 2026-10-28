import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class AppModel {
    private(set) var accounts: [Account] = []
    private(set) var currentID: UUID?
    /// Changes whenever an account is opened, so its views start fresh even for the same account.
    private(set) var session = UUID()
    private(set) var isSigningIn = false
    /// False until old web data is cleaned up, so no web view uses a store being deleted.
    private(set) var isReady = false
    var errorMessage: String?

    var current: Account? { accounts.first { $0.id == currentID } }

    init() {
        do {
            let migrated = try AccountStore.migrateLegacy()
            accounts = try AccountStore.load()
            currentID = AccountStore.currentID.flatMap { id in accounts.first { $0.id == id }?.id } ?? accounts.first?.id
            Task {
                if migrated != nil { await AccountDataStore.clearLegacyDefault() }
                await finishLaunch()
            }
        } catch {
            errorMessage = error.localizedDescription
            isReady = true
        }
    }

    private func finishLaunch() async {
        await AccountDataStore.removeUnused(keeping: accounts)
        if let currentID { await PhotoLibrary.shared.use(account: currentID) }
        isReady = true
    }

    /// Signs in to a new account, or refreshes one that's already in the list, and opens it.
    func signIn(serverInput: String) async -> Bool {
        guard let server = ServerURL.root(from: serverInput) else {
            errorMessage = "Enter the full https:// address of your Nextcloud, e.g. https://cloud.example.com"
            return false
        }
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let privately = accounts.contains { $0.credential.server == server }
            let credential = try await BrowserLogin().signIn(server: server, privately: privately)
            let existing = accounts.first { $0.isSameUser(as: credential) }
            let displayName = try? await NextcloudAPI.displayName(credential)
            let account = Account(
                id: existing?.id ?? UUID(),
                credential: credential,
                displayName: displayName ?? existing?.displayName
            )
            try AccountStore.save(account)
            accounts = try AccountStore.load()
            if let existing {
                // The new app password replaces the old one, which would otherwise linger.
                try? await NextcloudAPI.revokeAppPassword(existing.credential)
            }
            // Reopened even if it's the current one, so the shell picks up the new password.
            await open(account.id, force: true)
            return true
        } catch is CancellationError {
            // The user closed the sign-in sheet.
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    func open(_ id: UUID, force: Bool = false) async {
        guard force || id != currentID else { return }
        await closeCurrent()
        currentID = id
        session = UUID()
        AccountStore.currentID = id
        await PhotoLibrary.shared.use(account: id)
    }

    func signOut(_ id: UUID) async {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        do {
            try AccountStore.delete(id)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        accounts.removeAll { $0.id == id }
        UserDefaults.standard.removeObject(forKey: PhotoLibrary.remoteKey(for: id))
        if id == currentID {
            await closeCurrent()
            currentID = nil
            AccountStore.currentID = nil
            if let next = accounts.first { await open(next.id) }
        }
        await AccountDataStore.clear(id)

        do {
            try await NextcloudAPI.revokeAppPassword(account.credential)
        } catch {
            errorMessage = "Signed out, but the app password couldn't be revoked on the server "
                + "(\(error.localizedDescription)). Remove it under Personal settings → Security."
        }
    }

    /// Stops the shell and drops caches keyed by its URLs, which every account shares.
    private func closeCurrent() async {
        await ShellHost.shared.stop()
        await ShellImageLoader.shared.forgetAll()
        await LiveVideoLoader.shared.forgetAll()
    }
}
