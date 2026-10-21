import FlyingFox
import Foundation

/// The HTTP half of Memories' native API (`NAPI` in Memories' src/native/api.ts).
/// Endpoints that aren't implemented answer 501 so Memories shows an error instead of hanging.
enum BridgeEndpoints {
    static let shareURLPrefix = "/api/share/url/"

    static func respond(to request: HTTPRequest, proxy: UpstreamProxy, localOrigin: URL, shell: ShellConfig) async -> HTTPResponse {
        let path = request.path
        do {
            if path == "/api/upload/local" {
                return try await uploadLocal(request, proxy: proxy, shell: shell)
            }
            if let response = try await respondToLocalMedia(request, path: path) {
                return response
            }
        } catch {
            DiagnosticsLog.record("bridge", "\(request.method.rawValue) \(path) -> \(error.localizedDescription)")
            return LocalRequestHandler.plain(HTTPStatusCode(500, phrase: "Internal Server Error"), error.localizedDescription)
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

    /// Phone photos: days, day contents, previews, full images, videos, details, permission.
    private static func respondToLocalMedia(_ request: HTTPRequest, path: String) async throws -> HTTPResponse? {
        let library = PhotoLibrary.shared
        let hidesPhone = TimelineSource.current == .cloud
        if path == "/api/days" {
            return try json(hidesPhone ? [] : await library.days())
        }
        if let day = number(after: "/api/days/", in: path) {
            return try json(hidesPhone ? [] : await library.photos(onDay: day))
        }
        if let fileID = number(after: "/image/preview/", in: path) {
            let width = Int(query("x", in: request) ?? "") ?? 256
            let height = Int(query("y", in: request) ?? "") ?? width
            return jpeg(try await library.previewJPEG(fileID: fileID, width: width, height: height))
        }
        if path.hasPrefix("/image/full/") {
            let auid = String(path.dropFirst("/image/full/".count))
            return jpeg(try await library.fullJPEG(auid: auid, longEdge: Int(query("size", in: request) ?? "")))
        }
        if let fileID = number(after: "/video/full/", in: path) {
            return try serveFile(try await library.videoFile(fileID: fileID), range: request.headers[.range])
        }
        if let fileID = number(after: "/api/image/info/", in: path) {
            let info = try await library.info(fileID: fileID)
            let data = try JSONSerialization.data(withJSONObject: info)
            return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json"], body: data)
        }
        if path.hasPrefix("/api/image/delete/") {
            let auids = path.dropFirst("/api/image/delete/".count).split(separator: ",").map(String.init)
            let dry = ["1", "true"].contains(query("dry", in: request) ?? "")
            let count = try await library.delete(auids: auids, dry: dry)
            // iOS shows its own confirmation, so Memories can skip its dialog.
            let body = try JSONSerialization.data(withJSONObject: ["message": "ok", "count": count, "confirms": true])
            if !dry, count > 0 {
                await PageState.shared.libraryChanged()
            }
            return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json"], body: body)
        }
        if let allow = number(after: "/api/config/allow_media/", in: path) {
            if allow == 1 {
                _ = await library.requestAccess()
            }
            // Memories reads the permission synchronously right after this returns.
            await PageState.shared.push()
            return HTTPResponse(statusCode: .ok)
        }
        return nil
    }

    /// Memories' `UPLOAD_LOCAL`: uploads a phone photo's original to `filename` in the user's files.
    private static func uploadLocal(_ request: HTTPRequest, proxy: UpstreamProxy, shell: ShellConfig) async throws -> HTTPResponse {
        guard let auid = query("auid", in: request), let filename = query("filename", in: request) else {
            return LocalRequestHandler.plain(HTTPStatusCode(400, phrase: "Bad Request"), "auid and filename are required.")
        }
        guard let user = shell.user else {
            throw ProxyError(reason: "the signed-in user is unknown")
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "uploads/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: folder)
            } catch {
                DiagnosticsLog.record("bridge", "Removing the upload's temporary copy failed: \(error.localizedDescription)")
            }
        }

        let original = try await PhotoLibrary.shared.originalForUpload(auid: auid, into: folder)
        let fileID = try await proxy.upload(
            file: original.file, to: filename, user: user, webRoot: shell.webRoot,
            mtime: original.epoch, contentType: original.mimetype
        )
        await PhotoLibrary.shared.setHasRemote(auids: [auid], buids: [], value: true)
        return try json(["fileid": fileID])
    }

    private static func json(_ value: some Encodable) throws -> HTTPResponse {
        HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json"], body: try JSONEncoder().encode(value))
    }

    private static func jpeg(_ data: Data) -> HTTPResponse {
        HTTPResponse(
            statusCode: .ok,
            headers: [.contentType: "image/jpeg", HTTPHeader("Cache-Control"): "private, max-age=86400"],
            body: data
        )
    }

    /// Byte ranges let the web player seek without loading the whole video.
    static func serveFile(_ file: URL, range: String?) throws -> HTTPResponse {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let total = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let type = file.pathExtension.lowercased() == "mp4" ? "video/mp4" : "video/quicktime"
        guard let range, let bounds = byteRange(range, total: total) else {
            return HTTPResponse(
                statusCode: .ok,
                headers: [.contentType: type, HTTPHeader("Accept-Ranges"): "bytes"],
                body: try HTTPBodySequence(file: file)
            )
        }
        return HTTPResponse(
            statusCode: .partialContent,
            headers: [
                .contentType: type,
                HTTPHeader("Accept-Ranges"): "bytes",
                HTTPHeader("Content-Range"): "bytes \(bounds.lowerBound)-\(bounds.upperBound - 1)/\(total)",
            ],
            body: try HTTPBodySequence(file: file, range: bounds)
        )
    }

    /// Parses a single "bytes=a-b", "bytes=a-" or "bytes=-n" range into a half-open range.
    static func byteRange(_ header: String, total: Int) -> Range<Int>? {
        guard total > 0, header.hasPrefix("bytes="), !header.contains(",") else { return nil }
        let parts = header.dropFirst("bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let start: Int
        let end: Int
        if parts[0].isEmpty {
            guard let suffix = Int(parts[1]), suffix > 0 else { return nil }
            start = max(total - suffix, 0)
            end = total - 1
        } else {
            guard let first = Int(parts[0]) else { return nil }
            start = first
            end = parts[1].isEmpty ? total - 1 : min(Int(parts[1]) ?? total - 1, total - 1)
        }
        guard start >= 0, start <= end, start < total else { return nil }
        return start..<(end + 1)
    }

    private static func number(after prefix: String, in path: String) -> Int? {
        guard path.hasPrefix(prefix) else { return nil }
        let rest = path.dropFirst(prefix.count)
        guard !rest.isEmpty, rest.allSatisfy(\.isNumber) else { return nil }
        return Int(rest)
    }

    private static func query(_ name: String, in request: HTTPRequest) -> String? {
        request.query.first { $0.name == name }?.value
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
}
