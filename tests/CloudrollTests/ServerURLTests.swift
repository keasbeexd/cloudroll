import XCTest
@testable import Cloudroll

final class ServerURLTests: XCTestCase {
    func testNormalizesTrailingSlashesQueryAndWhitespace() {
        XCTAssertEqual(
            ServerURL.root(from: "  https://cloud.example.com/nextcloud//?x=1#top \n")?.absoluteString,
            "https://cloud.example.com/nextcloud"
        )
    }

    func testKeepsPort() {
        XCTAssertEqual(ServerURL.root(from: "https://192.168.1.16:8443")?.absoluteString, "https://192.168.1.16:8443")
    }

    func testRejectsHTTPAndMissingHost() {
        XCTAssertNil(ServerURL.root(from: "http://cloud.example.com"))
        XCTAssertNil(ServerURL.root(from: "cloud.example.com"))
        XCTAssertNil(ServerURL.root(from: "https://"))
    }

    func testMemoriesDescribeEndpoint() throws {
        let root = try XCTUnwrap(ServerURL.root(from: "https://cloud.example.com/nc"))
        XCTAssertEqual(
            ServerURL.memoriesDescribe(root: root).absoluteString,
            "https://cloud.example.com/nc/index.php/apps/memories/api/describe"
        )
    }

    /// Pretty-URL servers report `/apps/memories/`; the router breaks under `/index.php/`.
    func testEntryUsesServerReportedBaseURL() throws {
        let server = try XCTUnwrap(URL(string: "https://cloud.example.com"))
        let info = try JSONDecoder().decode(
            MemoriesInfo.self,
            from: Data(#"{"version":"8.1.0","baseUrl":"https://cloud.example.com/apps/memories/"}"#.utf8)
        )
        XCTAssertEqual(try info.entry(for: server).absoluteString, "https://cloud.example.com/apps/memories/")
    }

    func testEntryOnOtherHostOrPortIsRejected() throws {
        let server = try XCTUnwrap(URL(string: "https://cloud.example.com:8443"))
        for base in ["https://evil.example/apps/memories/", "https://cloud.example.com/apps/memories/", "http://cloud.example.com:8443/apps/memories/"] {
            let info = try JSONDecoder().decode(MemoriesInfo.self, from: Data(#"{"version":"10.1.0","baseUrl":"\#(base)"}"#.utf8))
            XCTAssertThrowsError(try info.entry(for: server)) {
                XCTAssertEqual($0 as? MemoriesError, .unexpectedBaseURL(base))
            }
        }
    }
}
