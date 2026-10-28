import WebKit

/// Each account's cookies, local storage and caches live in their own persistent store.
/// The shell's origin is the same for every account, so a shared store would mix them.
@MainActor
enum AccountDataStore {
    static func store(for account: Account) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: account.id)
    }

    /// Empties the store now; deleting it fails while a web view still uses it, so
    /// `removeUnused` finishes the job on a later launch.
    static func clear(_ id: UUID) async {
        await WKWebsiteDataStore(forIdentifier: id).removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
        try? await WKWebsiteDataStore.remove(forIdentifier: id)
    }

    /// Deletes stores whose account is gone. Runs before any web view exists.
    static func removeUnused(keeping accounts: [Account]) async {
        let keep = Set(accounts.map(\.id))
        for id in await WKWebsiteDataStore.allDataStoreIdentifiers where !keep.contains(id) {
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: id)
            } catch {
                DiagnosticsLog.shared.add("accounts", "Couldn't remove an old web data store: \(error.localizedDescription)")
            }
        }
    }

    /// Single-account installs kept everything in the default store.
    static func clearLegacyDefault() async {
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }
}
