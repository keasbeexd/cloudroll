import WebKit

/// Each account's cookies, local storage and caches live in their own persistent store.
/// The shell's origin is the same for every account, so a shared store would mix them.
@MainActor
enum AccountDataStore {
    /// Stores of signed-out accounts that WebKit hasn't deleted yet.
    private static let staleKey = "accounts.staleDataStores"
    private static let legacyKey = "accounts.clearLegacyDataStore"

    static func store(for account: Account) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: account.id)
    }

    /// Deleted by `cleanUp` when the next web view is created. Sign-out can happen before
    /// any web view exists (the load error alert), when WebKit calls aren't safe yet, and
    /// deleting fails anyway while the signed-out account's web view is still around.
    static func clear(_ id: UUID) {
        stale.insert(id.uuidString)
    }

    /// Single-account installs kept everything in the default store.
    static func clearLegacyLater() {
        UserDefaults.standard.set(true, forKey: legacyKey)
    }

    /// Only called once a web view exists: WebKit's data store calls crash if they run
    /// before WebKit has set up its main run loop (seen on launch in 0.1.51).
    static func cleanUp() async {
        if UserDefaults.standard.bool(forKey: legacyKey) {
            await WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            )
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
        for value in stale {
            guard let id = UUID(uuidString: value) else {
                stale.remove(value)
                continue
            }
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: id)
                stale.remove(value)
            } catch {
                DiagnosticsLog.shared.add("accounts", "Couldn't remove an old web data store: \(error.localizedDescription)")
            }
        }
    }

    private static var stale: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: staleKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: staleKey) }
    }
}
