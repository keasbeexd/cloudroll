import SwiftUI
import XCTest
@testable import Cloudroll

final class ShellPageTests: XCTestCase {
    private func info(_ json: String) throws -> MemoriesInfo {
        try JSONDecoder().decode(MemoriesInfo.self, from: Data(json.utf8))
    }

    func testWebRootFromBaseURL() throws {
        XCTAssertEqual(try info(#"{"version":"10","baseUrl":"https://a.example/apps/memories/"}"#).webRoot, "")
        XCTAssertEqual(try info(#"{"version":"10","baseUrl":"https://a.example/index.php/apps/memories/"}"#).webRoot, "")
        XCTAssertEqual(try info(#"{"version":"10","baseUrl":"https://a.example/nc/index.php/apps/memories/"}"#).webRoot, "/nc")
        XCTAssertEqual(try info(#"{"version":"10","baseUrl":"https://a.example/nc/apps/memories"}"#).webRoot, "/nc")
    }

    func testConfigDropsNullStylesheetAttributes() throws {
        let decoded = try info(#"""
        {"version":"10","baseUrl":"https://a.example/apps/memories/","uid":"alice",
         "cssManifest":[{"rel":"stylesheet","media":null,"href":"/core/css/server.css"}]}
        """#)
        let config = ShellConfig(info: decoded)

        XCTAssertEqual(config.user, "alice")
        XCTAssertEqual(config.stylesheets, [["rel": "stylesheet", "href": "/core/css/server.css"]])
    }

    func testPageContainsNonceGlobalsAndEntryScripts() {
        let html = ShellPage.html(ShellConfig(webRoot: "/nc", user: "alice", stylesheets: []), nonce: "N0NCE")

        XCTAssertTrue(html.contains(#"<head data-user="alice">"#))
        XCTAssertTrue(html.contains(#"<script nonce="N0NCE">"#))
        XCTAssertTrue(html.contains(#"window._oc_webroot = "/nc";"#))
        XCTAssertTrue(html.contains(#"<script src="/local/assets/memories-l10n.js"></script>"#))
        XCTAssertTrue(html.contains(#"<script defer src="/local/assets/memories-main.js"></script>"#))
        XCTAssertTrue(html.contains("user-scalable=no"))
        XCTAssertTrue(html.contains("-webkit-user-select: none"))
        XCTAssertTrue(ShellPage.contentSecurityPolicy(nonce: "N0NCE").contains("script-src 'self' blob: 'nonce-N0NCE'"))
    }

    func testUntrustedValuesAreEscaped() {
        let html = ShellPage.html(
            ShellConfig(
                webRoot: "</script><script>alert(1)</script>",
                user: "\"><img src=x onerror=alert(1)>",
                stylesheets: [
                    ["href": "/a.css", "class": "\"><script>"],
                    ["href": "https://evil.example/x.css"],
                    ["href": "//evil.example/x.css"],
                    ["href": "/b.css", "on load": "x"],
                ]
            ),
            nonce: "n"
        )

        XCTAssertFalse(html.contains("</script><script>alert(1)"))
        XCTAssertFalse(html.contains("<img src=x"))
        XCTAssertFalse(html.contains("evil.example"))
        XCTAssertFalse(html.contains("on load"))
        XCTAssertTrue(html.contains(#"class="&quot;&gt;&lt;script&gt;""#))
    }

    func testJSStringEscapesQuotesAndTags() {
        XCTAssertEqual(ShellPage.jsString(#"a"b\c</x>"#), #""a\"b\\c\u003c/x\u003e""#)
    }

    func testBridgeMessageParsing() {
        XCTAssertEqual(BridgeMessage(body: ["method": "setThemeColor", "args": ["#123456", true]]), .setThemeColor("#123456", isDark: true))
        XCTAssertEqual(BridgeMessage(body: ["method": "toast", "args": ["hi"]]), .toast("hi"))
        XCTAssertEqual(BridgeMessage(body: ["method": "logout"]), .logout)
        XCTAssertNil(BridgeMessage(body: ["method": "toast", "args": [1]]))
        XCTAssertNil(BridgeMessage(body: ["method": "eval", "args": ["x"]]))
        XCTAssertNil(BridgeMessage(body: "logout"))
    }

    func testCSSHexColors() {
        XCTAssertNotNil(Color(cssHex: " #171717"))
        XCTAssertNotNil(Color(cssHex: "#fff"))
        XCTAssertNil(Color(cssHex: "rgb(0, 0, 0)"))
        XCTAssertNil(Color(cssHex: "#12345"))
    }

    func testScriptBaseFromServerPage() throws {
        let server = try XCTUnwrap(URL(string: "https://a.example/nc"))
        let page = #"<script nonce="x" defer src="/nc/custom_apps/memories/js/memories-main.js?v=ee40aaf9-0"></script>"#

        XCTAssertEqual(MemoriesScripts.base(inPage: page, server: server)?.absoluteString, "https://a.example/nc/custom_apps/memories/js/")
        XCTAssertNil(MemoriesScripts.base(inPage: #"<script src="//evil.example/memories-main.js">"#, server: server))
        XCTAssertNil(MemoriesScripts.base(inPage: "<html></html>", server: server))
    }
}


final class NavStateTests: XCTestCase {
    private let tabs = [
        NavState.Tab(href: "/index.php/apps/memories/", label: "Photos"),
        NavState.Tab(href: "/index.php/apps/memories/explore", label: "Explore"),
        NavState.Tab(href: "/index.php/apps/memories/albums", label: "Albums"),
    ]

    private func state(_ path: String, hash: String = "", enabled: Bool = true) -> NavState {
        NavState(enabled: enabled, tabs: tabs, path: path, hash: hash)
    }

    func testSelectedTabMatchesRootExactlyAndOthersByPrefix() {
        XCTAssertEqual(state("/index.php/apps/memories/").selectedTab?.label, "Photos")
        XCTAssertEqual(state("/index.php/apps/memories/albums/admin/Trip").selectedTab?.label, "Albums")
        XCTAssertNil(state("/index.php/apps/memories/favorites").selectedTab)
        XCTAssertNil(state("/index.php/apps/memories/albumsx").selectedTab)
    }

    func testTabBarHidesForOverlays() {
        XCTAssertTrue(state("/index.php/apps/memories/").showsTabBar)
        XCTAssertTrue(state("/index.php/apps/memories/", hash: "#day/20747").showsTabBar)
        XCTAssertFalse(state("/index.php/apps/memories/", hash: "#v/20747/80").showsTabBar)
        XCTAssertFalse(state("/index.php/apps/memories/", hash: "#s").showsTabBar)
        XCTAssertFalse(state("/index.php/apps/memories/", hash: "#day/1&ss").showsTabBar)
        XCTAssertFalse(state("/index.php/apps/memories/", enabled: false).showsTabBar)
    }

    func testBridgeParsesNavState() {
        let json = #"{"enabled":true,"tabs":[{"href":"/a/","label":"Photos"}],"path":"/a/","hash":""}"#
        XCTAssertEqual(
            BridgeMessage(body: ["method": "navState", "args": [json]]),
            .navState(NavState(enabled: true, tabs: [NavState.Tab(href: "/a/", label: "Photos")], path: "/a/", hash: ""))
        )
        XCTAssertNil(BridgeMessage(body: ["method": "navState", "args": ["{"]]))
    }
}

final class NavStateCollapseTests: XCTestCase {
    func testCollapsedIsOptionalForOlderScripts() throws {
        let old = try JSONDecoder().decode(NavState.self, from: Data(#"{"enabled":true,"tabs":[],"path":"/","hash":""}"#.utf8))
        let new = try JSONDecoder().decode(NavState.self, from: Data(#"{"enabled":true,"tabs":[],"path":"/","hash":"","collapsed":true}"#.utf8))

        XCTAssertNil(old.collapsed)
        XCTAssertEqual(new.collapsed, true)
    }
}

final class ShareTests: XCTestCase {
    private let local = URL(string: "http://127.0.0.1:47811")!

    func testUpstreamTargetOnlyFromLocalOrigin() throws {
        XCTAssertEqual(
            try ShareCenter.upstreamTarget(for: "http://127.0.0.1:47811/index.php/apps/memories/api/download/abc?x=1#f", localOrigin: local),
            "/index.php/apps/memories/api/download/abc?x=1"
        )
        XCTAssertThrowsError(try ShareCenter.upstreamTarget(for: "https://evil.example/x", localOrigin: local))
        XCTAssertThrowsError(try ShareCenter.upstreamTarget(for: "http://127.0.0.1:9999/x", localOrigin: local))
    }

    func testSharedLinkIsDoubleDecodedAndWebOnly() {
        let link = "https://cloud.example.com/s/AbC?x=1"
        let once = link.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let twice = once.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

        XCTAssertEqual(BridgeEndpoints.sharedLink(fromPath: "/api/share/url/" + twice)?.absoluteString, link)
        let script = "javascript:alert(1)".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        XCTAssertNil(BridgeEndpoints.sharedLink(fromPath: "/api/share/url/" + script))
    }

    func testSafeFilenames() {
        XCTAssertEqual(UpstreamProxy.safeFilename("IMG_0001.HEIC"), "IMG_0001.HEIC")
        XCTAssertEqual(UpstreamProxy.safeFilename("../../etc/passwd"), "_.._etc_passwd")
        XCTAssertEqual(UpstreamProxy.safeFilename(".hidden"), "hidden")
        XCTAssertEqual(UpstreamProxy.safeFilename(nil), "download")
    }

    func testBridgeParsesDownloadAndShareMessages() {
        XCTAssertEqual(BridgeMessage(body: ["method": "download", "args": ["http://127.0.0.1/x"]]), .download("http://127.0.0.1/x"))
        XCTAssertEqual(BridgeMessage(body: ["method": "setShareBlobs", "args": ["[]"]]), .setShareBlobs("[]"))
    }
}
