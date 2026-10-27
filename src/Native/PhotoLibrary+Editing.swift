import CoreImage
import Foundation
import ImageIO
import Photos

/// A phone photo opened for editing. PhotoKit hands over the original when the photo's last
/// edit was Cloudroll's, so that edit can be changed instead of stacked.
final class PhotoEditSession: @unchecked Sendable {
    let asset: PHAsset
    let input: PHContentEditingInput
    /// Cloudroll's earlier edit, if the photo has one.
    let previous: PhotoEdit?
    /// Edited anywhere (Photos, another app or Cloudroll), so it can be reverted.
    let hasAdjustments: Bool
    let isLive: Bool
    /// The photo upright and scaled down, for the editor's preview.
    let preview: CIImage

    init(asset: PHAsset, input: PHContentEditingInput, previous: PhotoEdit?, hasAdjustments: Bool, isLive: Bool, preview: CIImage) {
        self.asset = asset
        self.input = input
        self.previous = previous
        self.hasAdjustments = hasAdjustments
        self.isLive = isLive
        self.preview = preview
    }
}

/// The user declined iOS's "Allow Cloudroll to modify this photo?" prompt.
struct EditCancelled: Error {}

extension PhotoLibrary {
    static let previewLongEdge = 2048

    func editSession(fileID: Int) async throws -> PhotoEditSession {
        let asset = try asset(forFileID: fileID)
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        options.canHandleAdjustmentData = { PhotoEdit.canHandle($0) }
        let input: PHContentEditingInput = try await withCheckedThrowingContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, info in
                if let input {
                    continuation.resume(returning: input)
                } else {
                    let error = info[PHContentEditingInputErrorKey] as? Error
                    continuation.resume(throwing: PhotoLibraryError(
                        reason: "Couldn't open the photo for editing: \(error?.localizedDescription ?? "no photo returned")"
                    ))
                }
            }
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.previewLongEdge,
            // Orientation is applied below, the same way as for the full-size photo.
            kCGImageSourceCreateThumbnailWithTransform: false,
        ]
        guard let url = input.fullSizeImageURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        else { throw PhotoLibraryError(reason: "The photo couldn't be read for editing.") }

        let resources = PHAssetResource.assetResources(for: asset)
        return PhotoEditSession(
            asset: asset,
            input: input,
            previous: PhotoEdit(input.adjustmentData),
            hasAdjustments: resources.contains { $0.type == .adjustmentData },
            isLive: asset.mediaSubtypes.contains(.photoLive),
            preview: CIImage(cgImage: thumbnail).oriented(Self.orientation(of: input))
        )
    }

    /// Saves the edit with the photo; iOS asks the user first. Live Photos stay live, with
    /// every frame of the motion edited too.
    func save(_ edit: PhotoEdit, in session: PhotoEditSession) async throws {
        let input = session.input
        let output = PHContentEditingOutput(contentEditingInput: input)
        output.adjustmentData = try edit.adjustmentData()
        if session.isLive {
            try await renderLive(edit, input: input, into: output)
        } else {
            try renderStill(edit, input: input, into: output)
        }
        try await commit(session.asset) { PHAssetChangeRequest(for: $0).contentEditingOutput = output }
    }

    /// Back to the photo as it was taken, undoing edits made anywhere.
    func revert(_ session: PhotoEditSession) async throws {
        try await commit(session.asset) { PHAssetChangeRequest(for: $0).revertAssetContentToOriginal() }
    }

    private func commit(_ asset: PHAsset, _ change: @escaping (PHAsset) -> Void) async throws {
        do {
            try await PHPhotoLibrary.shared().performChanges { change(asset) }
        } catch let error as PHPhotosError where error.code == .userCancelled {
            throw EditCancelled()
        }
        invalidate()
    }

    private func renderStill(_ edit: PhotoEdit, input: PHContentEditingInput, into output: PHContentEditingOutput) throws {
        guard let url = input.fullSizeImageURL, let original = CIImage(contentsOf: url) else {
            throw PhotoLibraryError(reason: "The photo couldn't be read for editing.")
        }
        let edited = edit.apply(to: original.oriented(Self.orientation(of: input)))
            .settingProperties(Self.uprightProperties(original.properties))
        let colorSpace = original.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3)!
        try CIContext().writeJPEGRepresentation(
            of: edited,
            to: output.renderedContentURL,
            colorSpace: colorSpace,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.92]
        )
    }

    /// Frames arrive as stored, so geometry is applied upright and then turned back; the
    /// Live Photo keeps its orientation.
    private func renderLive(_ edit: PhotoEdit, input: PHContentEditingInput, into output: PHContentEditingOutput) async throws {
        guard let context = PHLivePhotoEditingContext(livePhotoEditingInput: input) else {
            throw PhotoLibraryError(reason: "The Live Photo couldn't be opened for editing.")
        }
        let orientation = context.orientation
        context.frameProcessor = { frame, _ in
            guard edit.changesGeometry else { return edit.apply(to: frame.image) }
            return edit.apply(to: frame.image.oriented(orientation)).oriented(orientation.inverse)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.saveLivePhoto(to: output, options: nil) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoLibraryError(
                        reason: "Couldn't save the Live Photo: \(error?.localizedDescription ?? "unknown error")"
                    ))
                }
            }
        }
    }

    private static func orientation(of input: PHContentEditingInput) -> CGImagePropertyOrientation {
        CGImagePropertyOrientation(rawValue: UInt32(input.fullSizeImageOrientation)) ?? .up
    }

    /// The original's metadata, minus what no longer holds for the rendered photo: it's
    /// upright now, and cropping changes its size.
    static func uprightProperties(_ properties: [String: Any]) -> [String: Any] {
        var properties = properties
        properties[kCGImagePropertyOrientation as String] = 1
        properties[kCGImagePropertyPixelWidth as String] = nil
        properties[kCGImagePropertyPixelHeight as String] = nil
        if var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            properties[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        if var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = nil
            exif[kCGImagePropertyExifPixelYDimension as String] = nil
            properties[kCGImagePropertyExifDictionary as String] = exif
        }
        return properties
    }
}
