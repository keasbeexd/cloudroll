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

/// Response of Memories' `api/describe?manifest=1` endpoint.
struct MemoriesInfo: Decodable {
    let version: String
    let baseUrl: URL
    let uid: String?
    /// Signed asset manifest; only Memories 9+ sends it, which enables the local shell.
    let jsManifest: SignedManifest.Envelope?
    /// Stylesheets the server page would link, as attribute maps (`rel`, `href`, `media`, `class`).
    let cssManifest: [[String: String?]]?

    /// The web UI address, accepted only on the signed-in server so a misconfigured
    /// server can't send the app and its credentials elsewhere.
    func entry(for server: URL) throws -> URL {
        guard baseUrl.scheme?.lowercased() == "https",
              baseUrl.host == server.host,
              baseUrl.port == server.port
        else { throw MemoriesError.unexpectedBaseURL(baseUrl.absoluteString) }
        return baseUrl
    }

    /// Nextcloud's path prefix ("" at a domain root, e.g. "/nextcloud" in a subfolder).
    var webRoot: String {
        var path = baseUrl.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        for suffix in ["/index.php/apps/memories", "/apps/memories"] where path.hasSuffix(suffix) {
            return String(path.dropLast(suffix.count))
        }
        return ""
    }
}
