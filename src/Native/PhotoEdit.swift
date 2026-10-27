import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Photos

/// A non-destructive edit of a phone photo. It's stored with the photo as PhotoKit
/// adjustment data, so Cloudroll can reopen it from the original and Photos can revert it.
struct PhotoEdit: Codable, Equatable {
    static let formatIdentifier = "app.cloudroll.edit"
    static let formatVersion = "1"

    /// Each from -1 to 1, 0 leaving the photo as it is.
    var exposure: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var warmth: Double = 0
    var filter = Filter.none
    /// Quarter turns anticlockwise, as Photos' rotate button.
    var turns = 0
    /// The part of the rotated photo that's kept, as fractions of its size, from the top left.
    var crop = PhotoEdit.fullCrop

    static let fullCrop = CGRect(x: 0, y: 0, width: 1, height: 1)

    enum Filter: String, Codable, CaseIterable {
        case none, mono, noir, tonal, chrome, fade, instant, process, transfer

        var title: String {
            self == .none ? "Original" : rawValue.capitalized
        }

        /// Core Image's photo effects, the same looks the Camera app used to offer.
        var ciName: String? {
            self == .none ? nil : "CIPhotoEffect\(rawValue.capitalized)"
        }
    }

    var isOriginal: Bool { self == PhotoEdit() }

    /// Changes only the colours, so it suits Live Photo frames of any size as well.
    var changesGeometry: Bool { turns % 4 != 0 || crop != Self.fullCrop }

    // MARK: Rendering

    /// Applies the edit to an image that's already upright.
    func apply(to image: CIImage) -> CIImage {
        var output = image
        if exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = output
            filter.ev = Float(exposure)
            output = filter.outputImage ?? output
        }
        if contrast != 0 || saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.brightness = 0
            filter.contrast = Float(1 + contrast * 0.5)
            filter.saturation = Float(1 + saturation)
            output = filter.outputImage ?? output
        }
        if warmth != 0 {
            // Telling Core Image the light was cooler than daylight makes the photo warmer.
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = output
            filter.neutral = CIVector(x: 6500 - warmth * 2500, y: 0)
            filter.targetNeutral = CIVector(x: 6500, y: 0)
            output = filter.outputImage ?? output
        }
        if let name = filter.ciName, let effect = CIFilter(name: name) {
            effect.setValue(output, forKey: kCIInputImageKey)
            output = effect.outputImage ?? output
        }
        output = Self.rotated(output, turns: turns)
        return Self.cropped(output, to: crop)
    }

    /// Core Image's y axis points up, so a positive angle turns the photo anticlockwise.
    static func rotated(_ image: CIImage, turns: Int) -> CIImage {
        var output = image
        for _ in 0..<((turns % 4) + 4) % 4 {
            output = atOrigin(output.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)))
        }
        return output
    }

    static func cropped(_ image: CIImage, to crop: CGRect) -> CIImage {
        guard crop != fullCrop else { return image }
        let extent = image.extent
        // The crop counts from the top, Core Image from the bottom.
        let rect = CGRect(
            x: extent.minX + crop.minX * extent.width,
            y: extent.minY + (1 - crop.maxY) * extent.height,
            width: crop.width * extent.width,
            height: crop.height * extent.height
        ).integral.intersection(extent)
        return atOrigin(image.cropped(to: rect))
    }

    /// Rotating leaves the extent slightly off zero, which would offset the saved photo.
    private static func atOrigin(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let moved = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        return moved.cropped(to: CGRect(origin: .zero, size: CGSize(width: extent.width.rounded(), height: extent.height.rounded())))
    }

    // MARK: Crop handles

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// The smallest crop, as a fraction of each side.
    static let minimumCropSide: CGFloat = 0.1

    /// Drags one corner of the crop, keeping the opposite one in place and the crop inside the photo.
    static func resized(_ crop: CGRect, corner: Corner, by delta: CGSize) -> CGRect {
        var minX = crop.minX, minY = crop.minY, maxX = crop.maxX, maxY = crop.maxY
        switch corner {
        case .topLeft, .bottomLeft:
            minX = min(max(0, minX + delta.width), maxX - minimumCropSide)
        case .topRight, .bottomRight:
            maxX = max(min(1, maxX + delta.width), minX + minimumCropSide)
        }
        switch corner {
        case .topLeft, .topRight:
            minY = min(max(0, minY + delta.height), maxY - minimumCropSide)
        case .bottomLeft, .bottomRight:
            maxY = max(min(1, maxY + delta.height), minY + minimumCropSide)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Moves the whole crop, stopping at the photo's edges.
    static func moved(_ crop: CGRect, by delta: CGSize) -> CGRect {
        CGRect(
            x: min(max(0, crop.minX + delta.width), 1 - crop.width),
            y: min(max(0, crop.minY + delta.height), 1 - crop.height),
            width: crop.width,
            height: crop.height
        )
    }

    /// The largest centred crop with this width-to-height ratio, on a photo with `imageAspect`.
    static func centredCrop(aspect: CGFloat, imageAspect: CGFloat) -> CGRect {
        if aspect < imageAspect {
            let width = aspect / imageAspect
            return CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        }
        let height = imageAspect / aspect
        return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
    }

    /// Turns the photo a quarter anticlockwise, taking the crop along.
    mutating func rotateLeft() {
        turns = (turns + 1) % 4
        // The left edge becomes the bottom one.
        crop = CGRect(x: crop.minY, y: 1 - crop.maxX, width: crop.height, height: crop.width)
    }

    // MARK: Adjustment data

    func adjustmentData() throws -> PHAdjustmentData {
        PHAdjustmentData(formatIdentifier: Self.formatIdentifier, formatVersion: Self.formatVersion, data: try JSONEncoder().encode(self))
    }

    static func canHandle(_ data: PHAdjustmentData) -> Bool {
        data.formatIdentifier == formatIdentifier && data.formatVersion == formatVersion
    }

    init() {}

    init?(_ data: PHAdjustmentData?) {
        guard let data, Self.canHandle(data),
              let edit = try? JSONDecoder().decode(PhotoEdit.self, from: data.data)
        else { return nil }
        self = edit
    }
}

extension CGImagePropertyOrientation {
    /// The orientation that undoes this one.
    var inverse: CGImagePropertyOrientation {
        switch self {
        case .left: .right
        case .right: .left
        default: self
        }
    }
}
