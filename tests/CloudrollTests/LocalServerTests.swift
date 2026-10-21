import XCTest
@testable import Cloudroll

/// Stands in for Nextcloud inside the proxy's URLSession and records what it receives.
final class StubUpstream: URLProtocol {
    struct Received {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data
    }

    static var received: [Received] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        Self.received.append(Received(
            method: request.httpMethod ?? "GET",
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body
        ))

        let (status, headers, data): (Int, [String: String], Data) = switch url.path {
        case "/echo": (200, ["Content-Type": "text/plain", "Set-Cookie": "nc_session=abc"], Data("hello".utf8))
        case "/redirect": (302, ["Location": "https://cloud.example.com/target?x=1"], Data())
        case "/index.php/csrftoken": (200, ["Content-Type": "application/json"], Data(#"{"token":"tok123"}"#.utf8))
        default: (404, [:], Data())
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class DoNotFollowRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

final class LocalServerTests: XCTestCase {
    private let authorization = "Basic dGVzdDp0ZXN0"
    private var server: LocalServer!
    private var assets: URL!
    private let client: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    override func setUp() async throws {
        StubUpstream.received = []
        assets = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("console.log(1)".utf8).write(to: assets.appending(path: "memories-main.js"))

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubUpstream.self]
        let proxy = UpstreamProxy(origin: URL(string: "https://cloud.example.com")!, authorization: authorization, configuration: config)
        server = LocalServer(port: UInt16.random(in: 49_152...60_000))
        let shell = ShellConfig(webRoot: "", user: "alice", stylesheets: [["rel": "stylesheet", "href": "/core/css/server.css"]])
        try await server.start(handler: LocalRequestHandler(authGuard: server.authGuard, assetDirectory: assets, proxy: proxy, shell: shell, localOrigin: server.origin))
    }

    override func tearDown() async throws {
        await server.stop()
        try FileManager.default.removeItem(at: assets)
    }

    private func send(
        _ target: String,
        method: String = "GET",
        body: Data? = nil,
        accept: String? = nil,
        withSecret: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: try XCTUnwrap(URL(string: target, relativeTo: server.origin)))
        request.httpMethod = method
        request.httpBody = body
        if let accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        }
        if withSecret {
            request.setValue("other=1; \(LocalAuthGuard.cookieName)=\(server.authGuard.secret)", forHTTPHeaderField: "Cookie")
        }
        let (data, response) = try await client.data(for: request, delegate: DoNotFollowRedirects())
        return (data, try XCTUnwrap(response as? HTTPURLResponse))
    }

    func testRequestWithoutSecretIsForbidden() async throws {
        let (_, response) = try await send("/echo", withSecret: false)

        XCTAssertEqual(response.statusCode, 403)
        XCTAssertTrue(StubUpstream.received.isEmpty)
    }

    func testForwardsWithAppPasswordAndWithoutLocalCookie() async throws {
        let (data, response) = try await send("/echo?a=b%20c")

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hello")
        XCTAssertNil(response.value(forHTTPHeaderField: "Set-Cookie"))
        let received = try XCTUnwrap(StubUpstream.received.first)
        XCTAssertEqual(received.url.absoluteString, "https://cloud.example.com/echo?a=b%20c")
        XCTAssertEqual(received.headers["Authorization"], authorization)
        XCTAssertNil(received.headers["Cookie"])
    }

    func testRedirectStaysOnLocalOrigin() async throws {
        let (_, response) = try await send("/redirect")

        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Location"), "/target?x=1")
    }

    func testForwardsRequestBody() async throws {
        _ = try await send("/echo", method: "POST", body: Data("payload".utf8))

        let received = try XCTUnwrap(StubUpstream.received.first)
        XCTAssertEqual(received.method, "POST")
        XCTAssertEqual(String(decoding: received.body, as: UTF8.self), "payload")
    }

    func testServesVerifiedAsset() async throws {
        let (data, response) = try await send("/local/assets/memories-main.js")

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "text/javascript; charset=utf-8")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "console.log(1)")
    }

    func testLocalPathsAreNeverForwarded() async throws {
        for target in ["/local/assets/missing.js", "/local/assets/..%2Fsecret", "/local/other"] {
            let (_, response) = try await send(target)
            XCTAssertEqual(response.statusCode, 404, target)
        }
        XCTAssertTrue(StubUpstream.received.isEmpty)
    }

    func testServesShellForAppRoutes() async throws {
        let (data, response) = try await send("/index.php/apps/memories/", accept: "text/html,application/xhtml+xml")
        let html = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertNotNil(response.value(forHTTPHeaderField: "Content-Security-Policy"))
        XCTAssertTrue(html.contains("memories-main.js"))
        XCTAssertTrue(html.contains(#"<link rel="stylesheet" href="/core/css/server.css">"#))
        XCTAssertTrue(html.contains(#"data-requesttoken="tok123""#))
        XCTAssertEqual(StubUpstream.received.map(\.url.path), ["/index.php/csrftoken"])
        XCTAssertEqual(StubUpstream.received.first?.headers["Authorization"], authorization)
    }

    func testServesMemoriesChunksFromSnapshot() async throws {
        let (data, response) = try await send("/apps/memories/js/memories-main.js?v=abc")

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "console.log(1)")
        XCTAssertTrue(StubUpstream.received.isEmpty)
    }

    func testOtherDocumentsAreNeverForwarded() async throws {
        let (_, response) = try await send("/apps/files/", accept: "text/html")

        XCTAssertEqual(response.statusCode, 404)
        XCTAssertTrue(StubUpstream.received.isEmpty)
    }

    func testBridgeReportsNoLocalPhotosYet() async throws {
        let (days, daysResponse) = try await send("/api/days")
        let (_, otherResponse) = try await send("/api/image/info/1")

        XCTAssertEqual(daysResponse.statusCode, 200)
        XCTAssertEqual(String(decoding: days, as: UTF8.self), "[]")
        XCTAssertEqual(otherResponse.statusCode, 501)
        XCTAssertTrue(StubUpstream.received.isEmpty)
    }

    func testNextcloudHomeRedirectsToMemoriesEntry() async throws {
        let (_, response) = try await send("/index.php/", accept: "text/html")

        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Location"), "/index.php/apps/memories/")
        XCTAssertTrue(StubUpstream.received.isEmpty)
    }

    /// Albums and public links use WebDAV and OCS; they must reach Nextcloud unchanged.
    func testForwardsWebDAVAndOCSRequests() async throws {
        let xml = Data(#"<?xml version="1.0"?><d:propertyupdate xmlns:d="DAV:"/>"#.utf8)
        var outcomes: [String] = []
        for (method, target, body) in [
            ("MKCOL", "/remote.php/dav/photos/alice/albums/Trip", nil),
            ("PROPPATCH", "/remote.php/dav/photos/alice/albums/Trip", xml),
            ("POST", "/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json", Data("path=/x".utf8)),
        ] as [(String, String, Data?)] {
            let (data, response) = try await send(target, method: method, body: body)
            outcomes.append("\(method) -> \(response.statusCode) \(String(decoding: data.prefix(200), as: UTF8.self))")
        }

        let received = StubUpstream.received
        XCTAssertEqual(received.map(\.method), ["MKCOL", "PROPPATCH", "POST"], "local server answered: \(outcomes)")
        XCTAssertEqual(received.map(\.url.path), [
            "/remote.php/dav/photos/alice/albums/Trip",
            "/remote.php/dav/photos/alice/albums/Trip",
            "/ocs/v2.php/apps/files_sharing/api/v1/shares",
        ])
        XCTAssertEqual(received.dropFirst().first?.body, xml)
    }
}
