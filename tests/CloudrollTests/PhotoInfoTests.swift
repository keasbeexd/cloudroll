import XCTest
@testable import Cloudroll

final class PhotoInfoTests: XCTestCase {
    /// What shell-viewer.js returned for a photo on the test server.
    func testDecodesWhatTheViewerScriptReturns() throws {
        let json = """
        {"fileid":18,"basename":"Nextcloud community.jpg","filename":"/Photos/Nextcloud community.jpg","mimetype":"image/jpeg","size":797325,"w":3000,"h":2000,"datetaken":1792542571,"offset":null,"title":null,"description":null,"make":null,"model":null,"lens":null,"fNumber":null,"exposure":null,"focalLength":null,"iso":null,"megapixels":6,"latitude":null,"longitude":null,"address":null,"tags":[],"albums":[],"people":[]}
        """
        let info = try JSONDecoder().decode(PhotoInfo.self, from: Data(json.utf8))

        XCTAssertEqual(info.fileid, 18)
        XCTAssertNil(info.camera)
        XCTAssertNil(info.exposureText)
        XCTAssertFalse(info.hasLocation)
        XCTAssertTrue(try XCTUnwrap(info.fileText).hasPrefix("6.0 MP · 3000 × 2000 · "))
    }

    func testCameraDoesNotRepeatTheMake() {
        var info = PhotoInfo(fileid: 1, basename: "a.jpg")
        info.make = "Apple"
        info.model = "iPhone 15 Pro"
        XCTAssertEqual(info.camera, "Apple iPhone 15 Pro")
        info.make = "Canon"
        info.model = "Canon EOS R6"
        XCTAssertEqual(info.camera, "Canon EOS R6")
        info.make = nil
        XCTAssertEqual(info.camera, "Canon EOS R6")
    }

    func testExposureLine() {
        var info = PhotoInfo(fileid: 1, basename: "a.jpg")
        info.fNumber = 1.78
        info.exposure = 1.0 / 120
        info.focalLength = 6.86
        info.iso = 50
        XCTAssertEqual(info.exposureText, "f/1.8 · 1/120 s · 6.9 mm · ISO 50")
        info.fNumber = nil
        info.exposure = 2
        info.focalLength = 24
        info.iso = nil
        XCTAssertEqual(info.exposureText, "2 s · 24 mm")
    }

    func testMegapixelsFromDimensionsWhenMissing() {
        var info = PhotoInfo(fileid: 1, basename: "a.jpg")
        info.w = 4032
        info.h = 3024
        XCTAssertEqual(info.fileText, "12.2 MP · 4032 × 3024")
    }

    func testZeroCoordinatesAreNoLocation() {
        var info = PhotoInfo(fileid: 1, basename: "a.jpg")
        info.latitude = 0
        info.longitude = 0
        XCTAssertFalse(info.hasLocation)
        info.latitude = 46.2
        info.longitude = 6.1
        XCTAssertTrue(info.hasLocation)
    }

    func testTimeUsesTheTakenLocalTimeAndShowsTheZone() throws {
        var info = PhotoInfo(fileid: 1, basename: "a.jpg")
        // 2026-10-12 14:03 local time, stored as if it were UTC.
        info.datetaken = 1_791_813_780
        info.offset = "+02:00"
        let time = try XCTUnwrap(info.timeText)
        XCTAssertTrue(time.hasSuffix("(UTC+02:00)"), time)
        // 24- or 12-hour clock, depending on the simulator's locale.
        XCTAssertTrue(time.contains("14:03") || time.contains("2:03"), time)
    }
}
