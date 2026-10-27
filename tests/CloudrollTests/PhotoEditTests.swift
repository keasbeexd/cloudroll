import CoreImage
import ImageIO
import Photos
import XCTest
@testable import Cloudroll

final class PhotoEditTests: XCTestCase {
    private let context = CIContext()

    /// 200 × 100, red on the left half and blue on the right.
    private var halves: CIImage {
        let red = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let blue = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
        return red.composited(over: blue)
    }

    /// RGBA of one pixel, counting from Core Image's bottom left.
    private func pixel(_ image: CIImage, x: CGFloat, y: CGFloat) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return bytes
    }

    func testOriginalEditLeavesThePhotoAlone() {
        let output = PhotoEdit().apply(to: halves)
        XCTAssertEqual(output.extent, CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertTrue(PhotoEdit().isOriginal)
        XCTAssertFalse(PhotoEdit().changesGeometry)
    }

    func testRotatingLeftTurnsAnticlockwise() {
        var edit = PhotoEdit()
        edit.rotateLeft()
        let output = edit.apply(to: halves)
        XCTAssertEqual(output.extent, CGRect(x: 0, y: 0, width: 100, height: 200))
        // Turned anticlockwise, the left (red) half ends up at the bottom.
        XCTAssertGreaterThan(pixel(output, x: 50, y: 20)[0], 200)
        XCTAssertGreaterThan(pixel(output, x: 50, y: 180)[2], 200)
    }

    func testFourTurnsAreNone() {
        var edit = PhotoEdit()
        for _ in 0..<4 { edit.rotateLeft() }
        XCTAssertEqual(edit, PhotoEdit())
    }

    func testCropCountsFromTheTop() {
        // Top half of a photo whose top is red and bottom blue.
        let red = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 50, width: 100, height: 50))
        let blue = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        var edit = PhotoEdit()
        edit.crop = CGRect(x: 0, y: 0, width: 1, height: 0.5)
        let output = edit.apply(to: red.composited(over: blue))
        XCTAssertEqual(output.extent, CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertGreaterThan(pixel(output, x: 50, y: 25)[0], 200)
    }

    func testRotatingTakesTheCropAlong() {
        var edit = PhotoEdit()
        // The left quarter, full height.
        edit.crop = CGRect(x: 0, y: 0, width: 0.25, height: 1)
        edit.rotateLeft()
        // Now the bottom quarter, full width.
        XCTAssertEqual(edit.crop, CGRect(x: 0, y: 0.75, width: 1, height: 0.25))
    }

    func testWarmthWarmsAndExposureBrightens() {
        let grey = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 10, height: 10))
        var warm = PhotoEdit()
        warm.warmth = 1
        let warmed = pixel(warm.apply(to: grey), x: 5, y: 5)
        XCTAssertGreaterThan(Int(warmed[0]), Int(warmed[2]) + 10, "\(warmed)")

        var bright = PhotoEdit()
        bright.exposure = 1
        XCTAssertGreaterThan(pixel(bright.apply(to: grey), x: 5, y: 5)[1], pixel(grey, x: 5, y: 5)[1])
    }

    func testMonoRemovesColour() {
        var edit = PhotoEdit()
        edit.filter = .mono
        let output = pixel(edit.apply(to: halves), x: 50, y: 50)
        XCTAssertLessThan(abs(Int(output[0]) - Int(output[2])), 6, "\(output)")
    }

    func testCornerDragsStayInsideThePhoto() {
        let full = PhotoEdit.fullCrop
        XCTAssertEqual(PhotoEdit.resized(full, corner: .topLeft, by: CGSize(width: -0.2, height: 0.3)),
                       CGRect(x: 0, y: 0.3, width: 1, height: 0.7))
        let tiny = PhotoEdit.resized(full, corner: .bottomRight, by: CGSize(width: -2, height: -2))
        XCTAssertEqual(tiny.width, PhotoEdit.minimumCropSide, accuracy: 0.0001)
        XCTAssertEqual(tiny.height, PhotoEdit.minimumCropSide, accuracy: 0.0001)
        let half = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        XCTAssertEqual(PhotoEdit.moved(half, by: CGSize(width: 1, height: -1)), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
    }

    func testCentredCropMatchesTheAspect() {
        // A square crop of a 4:3 photo keeps the full height.
        let square = PhotoEdit.centredCrop(aspect: 1, imageAspect: 4.0 / 3)
        XCTAssertEqual(square.height, 1)
        XCTAssertEqual(square.width, 0.75, accuracy: 0.0001)
        XCTAssertEqual(square.minX, 0.125, accuracy: 0.0001)
        let wide = PhotoEdit.centredCrop(aspect: 16.0 / 9, imageAspect: 4.0 / 3)
        XCTAssertEqual(wide.width, 1)
        XCTAssertEqual(wide.height, 0.75, accuracy: 0.0001)
    }

    func testAdjustmentDataRoundTrips() throws {
        var edit = PhotoEdit()
        edit.exposure = 0.4
        edit.filter = .noir
        edit.rotateLeft()
        XCTAssertEqual(PhotoEdit(try edit.adjustmentData()), edit)
        let foreign = PHAdjustmentData(formatIdentifier: "com.apple.photo", formatVersion: "1", data: Data())
        XCTAssertNil(PhotoEdit(foreign))
    }

    func testRenderedPhotoIsMarkedUpright() {
        let properties: [String: Any] = [
            kCGImagePropertyOrientation as String: 6,
            kCGImagePropertyTIFFDictionary as String: [kCGImagePropertyTIFFOrientation as String: 6, "Model": "iPhone"],
        ]
        let upright = PhotoLibrary.uprightProperties(properties)
        XCTAssertEqual(upright[kCGImagePropertyOrientation as String] as? Int, 1)
        let tiff = upright[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFOrientation as String] as? Int, 1)
        XCTAssertEqual(tiff?["Model"] as? String, "iPhone")
    }

    func testSaveSummary() {
        XCTAssertEqual(ShareCenter.saveSummary(saved: 1, skipped: 0, failed: 0), "Saved 1 item to Photos.")
        XCTAssertEqual(ShareCenter.saveSummary(saved: 3, skipped: 2, failed: 1),
                       "Saved 3 items to Photos, 2 already on this iPhone, 1 couldn't be downloaded.")
    }
}
