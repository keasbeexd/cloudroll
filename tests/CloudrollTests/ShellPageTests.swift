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
        XCTAssertEqual(ShellPage.jsString(#"a"b\c</x>"#), #""a\"b\\c</x>""#)
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
}
