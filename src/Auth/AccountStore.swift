import Foundation
import Security

struct KeychainError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Keychain \(operation) failed: \(detail)"
    }
}

/// One Keychain item per account. The order of the list and the current account are
/// kept in UserDefaults, since neither is secret.
enum AccountStore {
    private static let service = "app.cloudroll.account"
    private static let orderKey = "accounts.order"
    private static let currentKey = "accounts.current"

    /// Before multiple accounts there was one item with this service and account.
    private static let legacyService = "app.cloudroll.credential"
    private static let legacyAccount = "current"

    static var currentID: UUID? {
        get { UserDefaults.standard.string(forKey: currentKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: currentKey) }
    }

    /// Accounts in the order they were added.
    static func load() throws -> [Account] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [Data] else {
            throw KeychainError(operation: "read", status: status)
        }
        let accounts = try items.map { try JSONDecoder().decode(Account.self, from: $0) }
        let order = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        return accounts.sorted {
            (order.firstIndex(of: $0.id.uuidString) ?? .max) < (order.firstIndex(of: $1.id.uuidString) ?? .max)
        }
    }

    /// Adds the account, or replaces the stored one with the same id.
    static func save(_ account: Account) throws {
        try delete(account.id)
        var query = itemQuery(account.id)
        query[kSecValueData as String] = try JSONEncoder().encode(account)
        // Not synced to other devices; app passwords are per device in Nextcloud.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(operation: "save", status: status) }

        var order = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        if !order.contains(account.id.uuidString) {
            order.append(account.id.uuidString)
            UserDefaults.standard.set(order, forKey: orderKey)
        }
    }

    static func delete(_ id: UUID) throws {
        let status = SecItemDelete(itemQuery(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(operation: "delete", status: status)
        }
        let order = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        UserDefaults.standard.set(order.filter { $0 != id.uuidString }, forKey: orderKey)
    }

    /// Moves a single-account install's credential into the account list.
    /// Returns the migrated account, so its old shared web data can be cleared.
    static func migrateLegacy() throws -> Account? {
        let legacy: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: legacyAccount,
        ]
        var query = legacy
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(operation: "read", status: status)
        }
        let account = Account(id: UUID(), credential: try JSONDecoder().decode(Credential.self, from: data))
        try save(account)
        currentID = account.id
        let defaults = UserDefaults.standard
        if let remote = defaults.stringArray(forKey: PhotoLibrary.remoteKey(for: nil)) {
            defaults.set(remote, forKey: PhotoLibrary.remoteKey(for: account.id))
            defaults.removeObject(forKey: PhotoLibrary.remoteKey(for: nil))
        }

        let deleted = SecItemDelete(legacy as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else {
            throw KeychainError(operation: "delete", status: deleted)
        }
        return account
    }

    private static func itemQuery(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }
}
