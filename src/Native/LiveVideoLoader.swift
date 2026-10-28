import CryptoKit
import Foundation

/// Downloads the motion part of server Live Photos to files. Memories serves Android motion
/// photos' embedded videos without byte-range support, which AVPlayer needs for streaming,
/// so the clips (a few MB) are played from disk instead.
actor LiveVideoLoader {
    static let shared = LiveVideoLoader()

    private let session: URLSession
    private var loading: [URL: Task<URL, Error>] = [:]
    private let folder = FileManager.default.temporaryDirectory.appending(path: "live-videos", directoryHint: .isDirectory)

    init() {
        // Apple Live Photos answer with a redirect to the MOV; a cookie store (rather than a
        // Cookie header) keeps the shell's access cookie on the redirected request.
        session = URLSession(configuration: .ephemeral)
    }

    func file(at url: URL, cookie: String) async throws -> URL {
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        if let existing = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .first(where: { $0.deletingPathExtension().lastPathComponent == name }) {
            return existing
        }
        if let task = loading[url] { return try await task.value }

        setCookie(cookie, for: url)
        let session = session
        let folder = folder
        let task = Task<URL, Error> {
            let (download, response) = try await session.download(from: url)
            try HTTP.require(200, response, context: "Loading the Live Photo")
            // AVPlayer picks the format from the extension.
            let ext = response.mimeType == "video/quicktime" ? "mov" : "mp4"
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: "\(name).\(ext)")
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: download, to: file)
            return file
        }
        loading[url] = task
        defer { loading[url] = nil }
        return try await task.value
    }

    /// Files are named after the shell's URLs, which repeat across accounts.
    func forgetAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// `cookie` is "name=value", as the viewer sends it.
    private func setCookie(_ cookie: String, for url: URL) {
        let parts = cookie.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, let host = url.host(),
              let httpCookie = HTTPCookie(properties: [.domain: host, .path: "/", .name: parts[0], .value: parts[1]])
        else { return }
        session.configuration.httpCookieStorage?.setCookie(httpCookie)
    }
}
