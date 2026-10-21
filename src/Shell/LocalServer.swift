import FlyingFox
import FlyingSocks
import Foundation

/// Serves the Memories shell from 127.0.0.1 and forwards everything else to Nextcloud,
/// so the web UI and its native bridge share one origin (see docs/decisions/0001).
actor LocalServer {
    /// Fixed so the web view origin, and with it local storage, stays the same across launches.
    static let defaultPort: UInt16 = 47811

    nonisolated let port: UInt16
    nonisolated let authGuard = LocalAuthGuard()
    private var server: HTTPServer?
    private(set) var lastError: Error?

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
        let server = HTTPServer(address: try .inet(ip4: "127.0.0.1", port: port), handler: handler)
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
    let authGuard: LocalAuthGuard
    /// Verified asset snapshot from `AssetStore`.
    let assetDirectory: URL
    let proxy: UpstreamProxy
    let shell: ShellConfig

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
            return serveShell()
        case .asset(let name):
            return try serveAsset(name)
        case .bridge:
            return BridgeEndpoints.respond(to: request)
        case .notFound:
            return HTTPResponse(statusCode: .notFound)
        case .proxy:
            return await forward(request)
        }
    }

    private func serveShell() -> HTTPResponse {
        let nonce = ShellPage.randomNonce()
        return HTTPResponse(
            statusCode: .ok,
            headers: [
                .contentType: "text/html; charset=utf-8",
                HTTPHeader("Content-Security-Policy"): ShellPage.contentSecurityPolicy(nonce: nonce),
                HTTPHeader("Cache-Control"): "no-store",
            ],
            body: Data(ShellPage.html(shell, nonce: nonce).utf8)
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
