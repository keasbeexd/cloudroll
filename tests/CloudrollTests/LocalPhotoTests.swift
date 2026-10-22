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
        XCTAssertTrue(isMain("GET", "/index.php/apps/memories/api/days/20747", []))
        XCTAssertFalse(isMain("GET", "/index.php/apps/memories/api/days/20747", ["albums"]))
        XCTAssertFalse(isMain("GET", "/index.php/apps/memories/api/days/", []))
        XCTAssertFalse(isMain("GET", "/index.php/apps/memories/api/daysx", []))
        XCTAssertFalse(isMain("DELETE", "/index.php/apps/memories/api/days", []))
    }
}

final class UploadPathTests: XCTestCase {
    func testUploadPathsStayInsideTheUsersFiles() throws {
        XCTAssertEqual(try UpstreamProxy.validatedSegments("/Photos/2026/IMG_0001.HEIC"), ["Photos", "2026", "IMG_0001.HEIC"])
        XCTAssertEqual(try UpstreamProxy.validatedSegments("/IMG 1.jpg"), ["IMG 1.jpg"])
        for bad in ["Photos/x.jpg", "/../x.jpg", "/Photos/./x.jpg", "/", "/a\\b.jpg", "/a\nb.jpg"] {
            XCTAssertThrowsError(try UpstreamProxy.validatedSegments(bad), bad)
        }
    }
}

final class SelectionTests: XCTestCase {
    func testBridgeParsesSelectionState() {
        XCTAssertEqual(
            BridgeMessage(body: ["method": "selection", "args": [#"{"active":true,"label":"3 selected"}"#]]),
            .selection(SelectionState(active: true, label: "3 selected"))
        )
        XCTAssertNil(BridgeMessage(body: ["method": "selection", "args": ["{}"]]))
    }

    func testDeleteFallsBackToRemoveFromAlbum() {
        XCTAssertEqual(SelectionController.Action.delete.icons, ["trash-can-outline-icon", "book-remove-icon"])
    }

    @MainActor
    func testDeleteChoiceResolvesTheWaitingRequest() async {
        let center = DeleteChoiceCenter()
        async let choice = center.ask(count: 2)
        await Task.yield()
        while center.pendingCount == nil { await Task.yield() }
        XCTAssertEqual(center.pendingCount, 2)
        center.answer(.cloudOnly)
        let result = await choice
        XCTAssertEqual(result, .cloudOnly)
        XCTAssertNil(center.pendingCount)
    }
}

final class OverlayTests: XCTestCase {
    func testOverlayDetectionIgnoresSelectionAndDays() {
        func state(_ hash: String) -> NavState { NavState(enabled: true, tabs: [], path: "/", hash: hash) }

        XCTAssertFalse(state("").overlayOpen)
        XCTAssertFalse(state("#s").overlayOpen)
        XCTAssertFalse(state("#day/1&s").overlayOpen)
        XCTAssertTrue(state("#s&m").overlayOpen)
        XCTAssertTrue(state("#v/1/2").overlayOpen)
    }

    func testSelectionStateFavoriteIsOptional() {
        XCTAssertEqual(
            BridgeMessage(body: ["method": "selection", "args": [#"{"active":true,"label":"1 selected","allFavorite":true}"#]]),
            .selection(SelectionState(active: true, label: "1 selected", allFavorite: true))
        )
    }
}

final class ViewerTests: XCTestCase {
    private let origin = URL(string: "http://127.0.0.1:47811")!

    private func photo(local: Bool, video: Bool = false) -> ViewerPhoto {
        ViewerPhoto(fileid: 80, auid: "abc", etag: "e/1", basename: "x.jpg", dayid: 20747, w: 10, h: 10,
                    video: video, favorite: false, local: local)
    }

    func testServerPhotoURLsGoThroughTheProxiedMemoriesAPI() throws {
        let media = try XCTUnwrap(ViewerMedia(photo: photo(local: false), origin: origin, webRoot: "/nc"))
        XCTAssertEqual(media.preview.absoluteString, "http://127.0.0.1:47811/nc/index.php/apps/memories/api/image/preview/80?c=e%2F1&x=1024&y=1024&a=0")
        XCTAssertEqual(media.full.absoluteString, "http://127.0.0.1:47811/nc/index.php/apps/memories/api/image/decodable/80?etag=e%2F1")
        XCTAssertNil(media.video)
    }

    func testPhonePhotoURLsUseTheBridge() throws {
        let media = try XCTUnwrap(ViewerMedia(photo: photo(local: true, video: true), origin: origin, webRoot: ""))
        XCTAssertEqual(media.full.absoluteString, "http://127.0.0.1:47811/image/full/abc?size=2560")
        XCTAssertEqual(media.video?.absoluteString, "http://127.0.0.1:47811/video/full/80")
    }

    func testTitleUsesTheDayIDsCalendarDay() {
        let title = NativeViewer.title(for: photo(local: false))
        XCTAssertTrue(title.contains("2026"), title)
    }

    func testBridgeParsesViewerState() {
        let json = #"{"open":true,"photo":{"fileid":1,"auid":"a","etag":"e","basename":"b","dayid":2,"w":3,"h":4,"video":false,"favorite":true,"local":false}}"#
        guard case .viewer(let state)? = BridgeMessage(body: ["method": "viewer", "args": [json]]) else {
            return XCTFail("not parsed")
        }
        XCTAssertTrue(state.open)
        XCTAssertEqual(state.photo?.favorite, true)
        XCTAssertEqual(BridgeMessage(body: ["method": "viewer", "args": [#"{"open":false}"#]]), .viewer(.closed))
    }
}

final class DialogTests: XCTestCase {
    func testDialogsWithoutAFragmentStillCountAsOverlays() {
        let tabs = [NavState.Tab(href: "/a/", label: "Photos")]
        let searching = NavState(enabled: true, tabs: tabs, path: "/a/", hash: "", dialog: true)
        XCTAssertTrue(searching.overlayOpen)
        XCTAssertFalse(searching.showsTabBar)
        XCTAssertTrue(NavState(enabled: true, tabs: tabs, path: "/a/", hash: "", dialog: false).showsTabBar)
    }
}

final class HeaderTests: XCTestCase {
    func testTitlesFromRoutes() {
        let base = "/index.php/apps/memories"
        XCTAssertEqual(HeaderState.title(forPath: base + "/albums/admin/My%20Trip", query: ""), "My Trip")
        XCTAssertEqual(HeaderState.title(forPath: base + "/folders", query: ""), "Folders")
        XCTAssertEqual(HeaderState.title(forPath: base + "/folders/Photos/2026", query: ""), "2026")
        XCTAssertEqual(HeaderState.title(forPath: base + "/search", query: "q=frog"), "“frog”")
        XCTAssertEqual(HeaderState.title(forPath: base + "/", query: ""), "")
    }

    func testUploadFolderOnlyInFoldersView() {
        let base = "/nc/index.php/apps/memories"
        XCTAssertEqual(HeaderState.folder(forPath: base + "/folders/Photos/Trip%201"), "/Photos/Trip 1")
        XCTAssertEqual(HeaderState.folder(forPath: base + "/folders"), "/")
        XCTAssertNil(HeaderState.folder(forPath: base + "/albums"))
    }

    func testIconSymbolsAndUploadDetection() {
        XCTAssertEqual(HeaderState.Action(icon: "plus-icon", label: "Create").symbol, "plus")
        XCTAssertEqual(HeaderState.Action(icon: "sort-calendar-ascending-icon", label: "Sort").symbol, "arrow.up.arrow.down")
        XCTAssertEqual(HeaderState.Action(icon: "mystery-icon", label: "?").symbol, "circle.grid.2x2")
        XCTAssertTrue(HeaderState.Action(icon: "upload-icon", label: "Upload files").isUpload)
    }

    func testBridgeParsesHeaderState() {
        let json = #"{"kind":"matter","title":"Albums","back":false,"actions":[{"icon":"plus-icon","label":"Create new album"}],"more":true}"#
        XCTAssertEqual(
            BridgeMessage(body: ["method": "header", "args": [json]]),
            .header(HeaderState(kind: "matter", title: "Albums", back: false, actions: [.init(icon: "plus-icon", label: "Create new album")], more: true))
        )
    }
}
