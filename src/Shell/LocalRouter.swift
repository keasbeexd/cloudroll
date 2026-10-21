import Foundation

enum LocalRoute: Equatable {
    /// The generated Memories page.
    case shell
    /// A verified Memories web asset, by file name.
    case asset(String)
    /// The native API Memories calls in native mode (`/api/…`, `/image/…`, `/video/…`).
    case bridge
    /// Forwarded to the Nextcloud server.
    case proxy
    case notFound
}

/// Decides what the local server does with a request. Paths outside the local
/// namespaces mirror the Nextcloud server's own paths and are forwarded unchanged.
struct LocalRouter: Sendable {
    static let assetPrefix = "/local/assets/"

    /// Nextcloud's path prefix, "" at a domain root.
    let webRoot: String

    /// Memories' router base outside Nextcloud: `generateUrl` adds `/index.php` because
    /// the shell has no server config saying pretty URLs work.
    var entryPath: String { webRoot + "/index.php/apps/memories/" }

    func route(method: String, path: String, wantsDocument: Bool) -> LocalRoute {
        if path.hasPrefix(Self.assetPrefix) {
            return Self.assetRoute(String(path.dropFirst(Self.assetPrefix.count)))
        }
        // Everything under /local/ lives on the device and is never forwarded.
        if Self.isUnder(path, "/local") {
            return .notFound
        }
        if ["/api", "/image", "/video"].contains(where: { Self.isUnder(path, $0) }) {
            return .bridge
        }

        let isGet = method.uppercased() == "GET"
        for appPrefix in [webRoot + "/index.php/apps/memories", webRoot + "/apps/memories"] {
            if isGet, path.hasPrefix(appPrefix + "/js/") {
                return Self.assetRoute(String(path.dropFirst(appPrefix.count + "/js/".count)))
            }
            if isGet, wantsDocument, Self.isUnder(path, appPrefix) {
                return .shell
            }
        }
        // Remote pages must never render on the local origin, where they could reach
        // the native bridge; only the shell is served as a document.
        if isGet, wantsDocument {
            return .notFound
        }
        return .proxy
    }

    private static func assetRoute(_ name: String) -> LocalRoute {
        WebAsset.isSafeName(name) ? .asset(name) : .notFound
    }

    private static func isUnder(_ path: String, _ prefix: String) -> Bool {
        path == prefix || path.hasPrefix(prefix + "/")
    }
}
