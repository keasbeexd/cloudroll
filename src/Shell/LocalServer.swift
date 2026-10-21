import FlyingFox
import FlyingSocks
import Foundation
import OSLog

/// Serves the Memories shell from 127.0.0.1 and forwards everything else to Nextcloud,
/// so the web UI and its native bridge share one origin (see docs/decisions/0001).
actor LocalServer {
    /// Fixed so the web view origin, and with it local storage, stays the same across launches.
    static let defaultPort: UInt16 = 47811

    nonisolated let port: UInt16
    nonisolated let authGuard = LocalAuthGuard()
    private var server: HTTPServer?
    private(set) var lastError: Error?

    /// HTTP plus the WebDAV and CalDAV/CardDAV-style methods Nextcloud serves.
    static let methods: [HTTPMethod] = [
        "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS",
        "PROPFIND", "PROPPATCH", "MKCOL", "COPY", "MOVE", "LOCK", "UNLOCK", "REPORT", "SEARCH",
    ].map { HTTPMethod($0) }

    init(port: UInt16 = LocalServer.defaultPort) {
        self.port = port
    }

    nonisolated var origin: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    var isRunning: Bool { server != nil }

    /// iOS closes the listening socket while the app is suspended, so this is called
    /// again whenever the app returns to the foreground.
    func start(handler: some HTTPHandler) async throws {
        guard server == nil else { return }
        let server = HTTPServer(address: try .inet(ip4: "127.0.0.1", port: port))
        // FlyingFox's catch-all route only matches its nine standard methods; Nextcloud's
        // WebDAV methods (albums, sharing, moves) would get a 404 without this list.
        await server.appendRoute(HTTPRoute(methods: Self.methods, path: "*"), to: handler)
        self.server = server
        Task { [weak self] in
            do {
                try await server.run()
            } catch {
                await self?.didStop(server, error: error)
            }
        }
        try await server.waitUntilListening()
    }

    func stop() async {
        guard let server else { return }
        self.server = nil
        await server.stop()
    }

    private func didStop(_ stopped: HTTPServer, error: Error) {
        guard server === stopped else { return }
        server = nil
        lastError = error
    }
}

struct LocalRequestHandler: HTTPHandler {
    private static let log = Logger(subsystem: "app.cloudroll", category: "shell")

    let authGuard: LocalAuthGuard
    /// Verified asset snapshot from `AssetStore`.
    let assetDirectory: URL
    let proxy: UpstreamProxy
    let shell: ShellConfig
    /// This server's own origin; Memories hands it back in download and share URLs.
    let localOrigin: URL

    func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        let cookies = request.headers.values(for: .cookie).joined(separator: "; ")
        guard authGuard.isAuthorized(cookieHeader: cookies) else {
            return HTTPResponse(statusCode: .forbidden)
        }

        let accept = request.headers[HTTPHeader("Accept")] ?? ""
        let wantsDocument = accept.contains("text/html") || request.headers[HTTPHeader("Sec-Fetch-Dest")] == "document"
        let router = LocalRouter(webRoot: shell.webRoot)
        switch router.route(method: request.method.rawValue, path: request.path, wantsDocument: wantsDocument) {
        case .shell:
            return await serveShell()
        case .redirectToEntry:
            return HTTPResponse(statusCode: HTTPStatusCode(302, phrase: "Found"), headers: [.location: router.entryPath])
        case .asset(let name):
            return try serveAsset(name)
        case .bridge:
            return await BridgeEndpoints.respond(to: request, proxy: proxy, localOrigin: localOrigin, shell: shell)
        case .notFound:
            DiagnosticsLog.record("local", "\(request.method.rawValue) \(request.path) -> 404 (not served locally)")
            return HTTPResponse(statusCode: .notFound)
        case .proxy:
            if TimelineSource.current == .phone, TimelineSource.isMainTimelineDays(
                method: request.method.rawValue, path: request.path,
                queryNames: request.query.map(\.name), webRoot: shell.webRoot
            ) {
                return HTTPResponse(statusCode: .ok, headers: [.contentType: "application/json"], body: Data("[]".utf8))
            }
            let response = await forward(request)
            if response.statusCode.code >= 400 {
                DiagnosticsLog.record("proxy", "\(request.method.rawValue) \(request.path) -> \(response.statusCode.code)")
            }
            return response
        }
    }

    private func serveShell() async -> HTTPResponse {
        let nonce = ShellPage.randomNonce()
        let token: String?
        do {
            token = try await proxy.requestToken(webRoot: shell.webRoot)
        } catch {
            // The page still renders from the snapshot; Memories fetches a token itself later.
            Self.log.notice("Shell rendered without a request token: \(error.localizedDescription, privacy: .public)")
            token = nil
        }
        return HTTPResponse(
            statusCode: .ok,
            headers: [
                .contentType: "text/html; charset=utf-8",
                HTTPHeader("Content-Security-Policy"): ShellPage.contentSecurityPolicy(nonce: nonce),
                HTTPHeader("Cache-Control"): "no-store",
            ],
            body: Data(ShellPage.html(shell, nonce: nonce, requestToken: token).utf8)
        )
    }

    private func serveAsset(_ name: String) throws -> HTTPResponse {
        let file = assetDirectory.appending(path: name)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return HTTPResponse(statusCode: .notFound)
        }
        return HTTPResponse(
            statusCode: .ok,
            headers: [.contentType: Self.contentType(for: file.pathExtension)],
            body: try HTTPBodySequence(file: file)
        )
    }

    /// Memories treats 504 as "offline", so unreachable servers map to it.
    private func forward(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            return try await proxy.forward(request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            return Self.plain(HTTPStatusCode(504, phrase: "Gateway Timeout"), error.localizedDescription)
        } catch {
            return Self.plain(.badGateway, error.localizedDescription)
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .timedOut, .cannotConnectToHost, .cannotFindHost,
        .networkConnectionLost, .dnsLookupFailed, .dataNotAllowed,
    ]

    static func plain(_ status: HTTPStatusCode, _ message: String) -> HTTPResponse {
        HTTPResponse(statusCode: status, headers: [.contentType: "text/plain; charset=utf-8"], body: Data(message.utf8))
    }

    static func contentType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "json", "map": "application/json"
        case "svg": "image/svg+xml"
        case "wasm": "application/wasm"
        default: "application/octet-stream"
        }
    }
}
