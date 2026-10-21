import FlyingFox
import Foundation

/// The HTTP half of Memories' native API (`NAPI` in Memories' src/native/api.ts).
/// Phone photos arrive in step 4b; until then the device reports no local photos.
/// Endpoints that aren't implemented answer 501 so Memories shows an error instead of hanging.
enum BridgeEndpoints {
    static let shareURLPrefix = "/api/share/url/"

    static func respond(to request: HTTPRequest, proxy: UpstreamProxy, localOrigin: URL) async -> HTTPResponse {
        let path = request.path
        if path == "/api/days" || isDayPath(path) {
            return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json"], body: Data("[]".utf8))
        }
        if path == "/api/share/blobs" {
            do {
                try await ShareCenter.shared.sharePendingBlobs(using: proxy, localOrigin: localOrigin)
                return HTTPResponse(statusCode: .ok)
            } catch {
                return LocalRequestHandler.plain(HTTPStatusCode(500, phrase: "Internal Server Error"), error.localizedDescription)
            }
        }
        if path.hasPrefix(shareURLPrefix) {
            guard let link = sharedLink(fromPath: path) else {
                return LocalRequestHandler.plain(HTTPStatusCode(400, phrase: "Bad Request"), "Not a shareable link.")
            }
            await ShareCenter.shared.shareLink(link)
            return HTTPResponse(statusCode: .ok)
        }
        DiagnosticsLog.record("bridge", "\(request.method.rawValue) \(path) -> 501")
        return LocalRequestHandler.plain(
            HTTPStatusCode(501, phrase: "Not Implemented"),
            "Cloudroll doesn't support \(path) yet."
        )
    }

    /// Memories double-encodes the link into one path segment; only web links are shared.
    static func sharedLink(fromPath path: String) -> URL? {
        guard path.hasPrefix(shareURLPrefix),
              let decoded = String(path.dropFirst(shareURLPrefix.count)).removingPercentEncoding?.removingPercentEncoding,
              let url = URL(string: decoded),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return nil }
        return url
    }

    private static func isDayPath(_ path: String) -> Bool {
        guard path.hasPrefix("/api/days/") else { return false }
        let id = path.dropFirst("/api/days/".count)
        return !id.isEmpty && id.allSatisfy(\.isNumber)
    }
}
