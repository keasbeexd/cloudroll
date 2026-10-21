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

    func testMemoriesEntryPoint() throws {
        let root = try XCTUnwrap(ServerURL.root(from: "https://cloud.example.com/nc"))
        XCTAssertEqual(ServerURL.memories(root: root).absoluteString, "https://cloud.example.com/nc/index.php/apps/memories/")
    }
}
