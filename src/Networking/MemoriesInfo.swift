import Foundation

enum MemoriesError: LocalizedError, Equatable {
    case notInstalled
    case unexpectedBaseURL(String)
    case scriptsNotFound

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Memories isn't installed on this Nextcloud. Ask your admin to install it from the Nextcloud app store."
        case .unexpectedBaseURL(let url):
            "Memories reported an unexpected address (\(url)), so it wasn't opened."
        case .scriptsNotFound:
            "Couldn't find where the server publishes Memories' scripts."
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

/// Where the server actually publishes Memories' scripts. The signed manifest's hrefs
/// assume `/apps/memories/js/`, but app store installs usually live elsewhere
/// (e.g. `/custom_apps/`), so the folder is read from the server's own Memories page.
enum MemoriesScripts {
    // A constant pattern; failing to compile it is a programming error.
    private static let scriptSource = try! NSRegularExpression(pattern: #"src="(/[^"]*?)/memories-main\.js"#)

    static func base(inPage html: String, server: URL) -> URL? {
        guard let match = scriptSource.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html)
        else { return nil }
        let folder = String(html[range])
        guard !folder.hasPrefix("//") else { return nil }
        return URL(string: folder + "/", relativeTo: server)?.absoluteURL
    }
}

