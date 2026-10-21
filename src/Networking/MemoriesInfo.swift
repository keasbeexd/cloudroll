import Foundation

enum MemoriesError: LocalizedError, Equatable {
    case notInstalled
    case unexpectedBaseURL(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Memories isn't installed on this Nextcloud. Ask your admin to install it from the Nextcloud app store."
        case .unexpectedBaseURL(let url):
            "Memories reported an unexpected address (\(url)), so it wasn't opened."
        }
    }
}

/// Response of Memories' public `api/describe` endpoint.
struct MemoriesInfo: Decodable {
    let version: String
    let baseUrl: URL

    /// The web UI address, accepted only on the signed-in server so a misconfigured
    /// server can't send the app and its credentials elsewhere.
    func entry(for server: URL) throws -> URL {
        guard baseUrl.scheme?.lowercased() == "https",
              baseUrl.host == server.host,
              baseUrl.port == server.port
        else { throw MemoriesError.unexpectedBaseURL(baseUrl.absoluteString) }
        return baseUrl
    }
}
