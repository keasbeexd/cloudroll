import Foundation

enum LocalRoute: Equatable {
    /// A verified Memories web asset, by file name.
    case asset(String)
    /// Forwarded to the Nextcloud server.
    case proxy
    case notFound
}

/// Decides what the local server does with a request path. Paths outside `/local/`
/// mirror the Nextcloud server's own paths, so they're forwarded unchanged.
enum LocalRouter {
    static let assetPrefix = "/local/assets/"

    static func route(path: String) -> LocalRoute {
        if path.hasPrefix(assetPrefix) {
            let name = String(path.dropFirst(assetPrefix.count))
            return WebAsset.isSafeName(name) ? .asset(name) : .notFound
        }
        // Everything under /local/ lives on the device and is never forwarded.
        if path == "/local" || path.hasPrefix("/local/") {
            return .notFound
        }
        return .proxy
    }
}
