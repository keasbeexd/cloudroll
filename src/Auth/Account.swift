import Foundation

/// A signed-in Nextcloud account. The id also names the account's web data store, so
/// cookies and Memories' local storage never mix between accounts.
struct Account: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let credential: Credential
    var displayName: String?

    var title: String { displayName ?? credential.loginName }

    /// "alice@cloud.example.com", or with the path for servers in a subfolder.
    var address: String {
        let host = credential.server.host() ?? credential.server.absoluteString
        let path = credential.server.path(percentEncoded: false)
        return "\(credential.loginName)@\(host)\(path == "/" ? "" : path)"
    }

    func isSameUser(as other: Credential) -> Bool {
        credential.server == other.server && credential.loginName == other.loginName
    }
}
