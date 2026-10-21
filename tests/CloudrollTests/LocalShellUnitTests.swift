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
        XCTAssertEqual(LocalRouter.route(path: "/local/assets/memories-main.js"), .asset("memories-main.js"))
        XCTAssertEqual(LocalRouter.route(path: "/local/assets/.hidden"), .notFound)
        XCTAssertEqual(LocalRouter.route(path: "/local/assets/a%2Fb"), .notFound)
        XCTAssertEqual(LocalRouter.route(path: "/local"), .notFound)
        XCTAssertEqual(LocalRouter.route(path: "/localhost/x"), .proxy)
        XCTAssertEqual(LocalRouter.route(path: "/apps/memories/api/days"), .proxy)
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
