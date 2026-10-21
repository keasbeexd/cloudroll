import XCTest
@testable import Cloudroll

final class LocalPhotoTests: XCTestCase {
    func testIDsMatchTheServerFormulas() {
        // Expected values computed independently with Python's hashlib.
        XCTAssertEqual(LocalPhotoIDs.auid(epoch: 1_792_548_068, size: 4217), "a83243813d37de33fc8ce23488baa81e")
        XCTAssertEqual(LocalPhotoIDs.buid(basename: "IMG_0001.HEIC", size: 42172), "0757432a399644949586275e9f17c71c")
    }

    func testDayIDUsesLocalTime() throws {
        let date = Date(timeIntervalSince1970: 86400 * 20000 + 23 * 3600) // 23:00 UTC
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))

        XCTAssertEqual(LocalPhotoIDs.dayID(for: date, in: utc), 20000)
        XCTAssertEqual(LocalPhotoIDs.dayID(for: date, in: berlin), 20001)
    }

    func testFileIDFromPhotoKitIdentifier() {
        XCTAssertEqual(LocalPhotoIDs.fileID(forLocalIdentifier: "6FB3A8F5-C0D1-4E2A-9B7C-123456789ABC/L0/001"), 0x6FB3A8F5C0D1)
        XCTAssertNil(LocalPhotoIDs.fileID(forLocalIdentifier: "short/L0/001"))
    }

    func testByteRanges() {
        XCTAssertEqual(BridgeEndpoints.byteRange("bytes=0-99", total: 1000), 0..<100)
        XCTAssertEqual(BridgeEndpoints.byteRange("bytes=900-", total: 1000), 900..<1000)
        XCTAssertEqual(BridgeEndpoints.byteRange("bytes=-100", total: 1000), 900..<1000)
        XCTAssertEqual(BridgeEndpoints.byteRange("bytes=0-5000", total: 1000), 0..<1000)
        XCTAssertNil(BridgeEndpoints.byteRange("bytes=1000-", total: 1000))
        XCTAssertNil(BridgeEndpoints.byteRange("bytes=0-1,5-9", total: 1000))
        XCTAssertNil(BridgeEndpoints.byteRange("items=0-1", total: 1000))
    }

    func testBridgeParsesFolderAndRemoteMessages() {
        XCTAssertEqual(BridgeMessage(body: ["method": "setLocalFolders", "args": ["[]"]]), .setLocalFolders("[]"))
        XCTAssertEqual(
            BridgeMessage(body: ["method": "setHasRemote", "args": ["[\"a\"]", "[]", true]]),
            .setHasRemote(auids: "[\"a\"]", buids: "[]", value: true)
        )
        XCTAssertNil(BridgeMessage(body: ["method": "setHasRemote", "args": ["[]", "[]"]]))
    }

    func testPlayStoreLinkBecomesAppStore() throws {
        let play = try XCTUnwrap(URL(string: "https://play.google.com/store/apps/details?id=com.nextcloud.client"))
        let other = try XCTUnwrap(URL(string: "https://example.com/x"))

        XCTAssertEqual(MemoriesWebView.Coordinator.iOSEquivalent(of: play).host, "apps.apple.com")
        XCTAssertEqual(MemoriesWebView.Coordinator.iOSEquivalent(of: other), other)
    }
}

final class TimelineSourceTests: XCTestCase {
    func testOnlyUnfilteredDayRequestsAreTheMainTimeline() {
        func isMain(_ method: String, _ path: String, _ query: [String], webRoot: String = "") -> Bool {
            TimelineSource.isMainTimelineDays(method: method, path: path, queryNames: query, webRoot: webRoot)
        }

        XCTAssertTrue(isMain("GET", "/index.php/apps/memories/api/days", []))
        XCTAssertTrue(isMain("POST", "/index.php/apps/memories/api/days", ["monthView"]))
        XCTAssertTrue(isMain("GET", "/nc/apps/memories/api/days", ["reverse"], webRoot: "/nc"))
        XCTAssertFalse(isMain("GET", "/index.php/apps/memories/api/days", ["albums", "monthView"]))
        XCTAssertFalse(isMain("GET", "/index.php/apps/memories/api/days", ["archive"]))
        XCTAssertFalse(isMain("GET", "/index.php/apps/memories/api/days/123", []))
        XCTAssertFalse(isMain("DELETE", "/index.php/apps/memories/api/days", []))
    }
}
