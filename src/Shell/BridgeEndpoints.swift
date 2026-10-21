import FlyingFox
import Foundation

/// The HTTP half of Memories' native API (`NAPI` in Memories' src/native/api.ts).
/// Phone photos arrive in step 4; until then the device reports no local photos and
/// every other endpoint answers 501 so Memories shows an error instead of hanging.
enum BridgeEndpoints {
    static func respond(to request: HTTPRequest) -> HTTPResponse {
        let path = request.path
        if path == "/api/days" || isDayPath(path) {
            return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json"], body: Data("[]".utf8))
        }
        return LocalRequestHandler.plain(
            HTTPStatusCode(501, phrase: "Not Implemented"),
            "Cloudroll doesn't support \(path) yet."
        )
    }

    private static func isDayPath(_ path: String) -> Bool {
        guard path.hasPrefix("/api/days/") else { return false }
        let id = path.dropFirst("/api/days/".count)
        return !id.isEmpty && id.allSatisfy(\.isNumber)
    }
}
