import XCTest
@testable import Cloudroll

final class LocalShellUnitTests: XCTestCase {
    func testGuardAcceptsOnlyTheExactSecret() {
        let authGuard = LocalAuthGuard(secret: "abc123")

        XCTAssertTrue(authGuard.isAuthorized(cookieHeader: "a=1; cloudroll_local=abc123"))
        XCTAssertFalse(authGuard.isAuthorized(cookieHeader: "cloudroll_local=abc12"))
        XCTAssertFalse(authGuard.isAuthorized(cookieHeader: "cloudroll_local=abc1234"))
        XCTAssertFalse(authGuard.isAuthorized(cookieHeader: "xcloudroll_local=abc123"))
        XCTAssertFalse(authGuard.isAuthorized(cookieHeader: ""))
    }

    func testRandomSecretsAreLongAndDistinct() {
        let a = LocalAuthGuard.randomSecret()
        XCTAssertEqual(a.count, 64)
        XCTAssertNotEqual(a, LocalAuthGuard.randomSecret())
    }

    func testRoutes() {
        let router = LocalRouter(webRoot: "")
        func route(_ path: String, _ method: String = "GET", document: Bool = false) -> LocalRoute {
            router.route(method: method, path: path, wantsDocument: document)
        }

        XCTAssertEqual(route("/local/assets/memories-main.js"), .asset("memories-main.js"))
        XCTAssertEqual(route("/local/assets/.hidden"), .notFound)
        XCTAssertEqual(route("/local/assets/a%2Fb"), .notFound)
        XCTAssertEqual(route("/local"), .notFound)
        XCTAssertEqual(route("/localhost/x"), .proxy)
        XCTAssertEqual(route("/apps/memories/api/days"), .proxy)
        XCTAssertEqual(route("/index.php/apps/memories/", document: true), .shell)
        XCTAssertEqual(route("/index.php/apps/memories/albums/x", document: true), .shell)
        XCTAssertEqual(route("/apps/memories/js/memories-chunk.js"), .asset("memories-chunk.js"))
        XCTAssertEqual(route("/index.php/apps/memories/js/memories-chunk.js"), .asset("memories-chunk.js"))
        XCTAssertEqual(route("/apps/memories/js/memories-chunk.js", "POST"), .proxy)
        XCTAssertEqual(route("/apps/files/", document: true), .notFound)
        XCTAssertEqual(route("/api/days"), .bridge)
        XCTAssertEqual(route("/image/preview/1"), .bridge)
        XCTAssertEqual(route("/apis/x"), .proxy)
    }

    func testRoutesUnderSubfolderWebRoot() {
        let router = LocalRouter(webRoot: "/nc")

        XCTAssertEqual(router.entryPath, "/nc/index.php/apps/memories/")
        XCTAssertEqual(router.route(method: "GET", path: "/nc/index.php/apps/memories/", wantsDocument: true), .shell)
        XCTAssertEqual(router.route(method: "GET", path: "/index.php/apps/memories/", wantsDocument: true), .notFound)
        XCTAssertEqual(router.route(method: "GET", path: "/nc/apps/memories/js/a.js", wantsDocument: false), .asset("a.js"))
    }

    func testLocationRewriteOnlyForUpstreamOrigin() throws {
        let origin = try XCTUnwrap(URL(string: "https://cloud.example.com:8443"))

        XCTAssertEqual(ProxyHeaders.localLocation("https://cloud.example.com:8443/apps/x?y=1#z", upstreamOrigin: origin), "/apps/x?y=1#z")
        XCTAssertEqual(ProxyHeaders.localLocation("https://cloud.example.com/apps/x", upstreamOrigin: origin), "https://cloud.example.com/apps/x")
        XCTAssertEqual(ProxyHeaders.localLocation("https://sso.example.com/login", upstreamOrigin: origin), "https://sso.example.com/login")
        XCTAssertEqual(ProxyHeaders.localLocation("/relative", upstreamOrigin: origin), "/relative")
    }

    func testRequestHeadersDropSecretsAndHopByHop() {
        let forwarded = ProxyHeaders.forwardedRequest([
            (name: "Cookie", value: "cloudroll_local=secret"),
            (name: "Connection", value: "keep-alive"),
            (name: "Authorization", value: "Basic spoofed"),
            (name: "requesttoken", value: "abc"),
            (name: "Range", value: "bytes=0-99"),
        ])

        XCTAssertEqual(forwarded.map(\.name), ["requesttoken", "Range"])
    }

    func testProxyOriginDropsServerPath() throws {
        let credential = Credential(server: try XCTUnwrap(URL(string: "https://cloud.example.com:8443/nextcloud")), loginName: "u", appPassword: "p")
        XCTAssertEqual(try UpstreamProxy(credential: credential).origin.absoluteString, "https://cloud.example.com:8443")
    }
}
