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

/// Stores the single signed-in account. Multiple accounts are planned (see docs/roadmap.md).
enum CredentialStore {
    private static let baseQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "app.cloudroll.credential",
        kSecAttrAccount as String: "current",
    ]

    static func load() throws -> Credential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(operation: "read", status: status)
        }
        return try JSONDecoder().decode(Credential.self, from: data)
    }

    static func save(_ credential: Credential) throws {
        try delete()
        var query = baseQuery
        query[kSecValueData as String] = try JSONEncoder().encode(credential)
        // Not synced to other devices; app passwords are per device in Nextcloud.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(operation: "save", status: status) }
    }

    static func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(operation: "delete", status: status)
        }
    }
}
