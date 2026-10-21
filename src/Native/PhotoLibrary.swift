import AVFoundation
import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

struct PhotoLibraryError: LocalizedError {
    let reason: String

    var errorDescription: String? { reason }
}

/// A day with phone photos, as Memories' `NAPI.DAYS` expects.
struct LocalDay: Encodable, Equatable {
    let dayid: Int
    let count: Int
}

/// A phone photo, with the field names of Memories' `IPhoto`.
struct LocalPhoto: Encodable {
    let fileid: Int
    let basename: String
    let mimetype: String
    let w: Int
    let h: Int
    let size: Int64
    let etag: String
    let epoch: Int
    let auid: String
    let buid: String
    let dayid: Int
    let isvideo: Bool
    let video_duration: Int
    let local_has_remote: Bool
}

/// A choice in Memories' "folders on this device" list; on iPhone these are albums.
struct LocalFolder: Codable, Equatable {
    let id: String
    let name: String
    var enabled: Bool
}

/// Phone photos for Memories' native API, read through PhotoKit.
actor PhotoLibrary {
    static let shared = PhotoLibrary()
    static let recentsID = "recents"

    private let enabledKey = "localFolders.enabled"
    private let remoteKey = "localPhotos.hasRemote"

    private var index: [Int: [String]]?
    private var identifiers: [Int: String] = [:]
    private var fileIDs: [String: Int] = [:]
    private var auids: [String: String] = [:]
    private lazy var hasRemote = Set(UserDefaults.standard.stringArray(forKey: remoteKey) ?? [])

    // MARK: Access

    nonisolated static var hasAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    nonisolated static var isUndetermined: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined
    }

    /// `.readWrite` now so deleting phone photos (step 4c) needs no second prompt.
    func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        invalidate()
        return status == .authorized || status == .limited
    }

    func invalidate() {
        index = nil
    }

    // MARK: Folders

    func folders() -> [LocalFolder] {
        guard Self.hasAccess else { return [] }
        let enabled = enabledFolderIDs()
        var folders = [LocalFolder(id: Self.recentsID, name: "Recents", enabled: enabled.contains(Self.recentsID))]
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        albums.enumerateObjects { album, _, _ in
            folders.append(LocalFolder(
                id: album.localIdentifier,
                name: album.localizedTitle ?? "Album",
                enabled: enabled.contains(album.localIdentifier)
            ))
        }
        return folders
    }

    func setFolders(_ folders: [LocalFolder]) {
        UserDefaults.standard.set(folders.filter(\.enabled).map(\.id), forKey: enabledKey)
        invalidate()
    }

    /// Everything on the phone is shown until the user picks albums.
    private func enabledFolderIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: enabledKey) ?? [Self.recentsID])
    }

    // MARK: Timeline

    func days() -> [LocalDay] {
        buildIndex()
            .map { LocalDay(dayid: $0.key, count: $0.value.count) }
            .sorted { $0.dayid > $1.dayid }
    }

    func photos(onDay dayID: Int) -> [LocalPhoto] {
        let ids = buildIndex()[dayID] ?? []
        guard !ids.isEmpty else { return [] }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var photos: [LocalPhoto] = []
        assets.enumerateObjects { asset, _, _ in
            if let photo = self.describe(asset, dayID: dayID) {
                photos.append(photo)
            }
        }
        for photo in photos {
            auids[photo.auid] = identifiers[photo.fileid]
        }
        return photos.sorted { $0.epoch > $1.epoch }
    }

    func setHasRemote(auids: [String], buids: [String], value: Bool) {
        let keys = auids + buids
        if value {
            hasRemote.formUnion(keys)
        } else {
            hasRemote.subtract(keys)
        }
        UserDefaults.standard.set(Array(hasRemote), forKey: remoteKey)
    }

    private func buildIndex() -> [Int: [String]] {
        if let index { return index }
        guard Self.hasAccess else { return [:] }

        var built: [Int: [String]] = [:]
        var seen = Set<String>()
        for result in assetFetches() {
            result.enumerateObjects { asset, _, _ in
                guard let date = asset.creationDate, seen.insert(asset.localIdentifier).inserted else { return }
                built[LocalPhotoIDs.dayID(for: date), default: []].append(asset.localIdentifier)
                self.register(asset.localIdentifier)
            }
        }
        index = built
        return built
    }

    private func assetFetches() -> [PHFetchResult<PHAsset>] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
        )
        let enabled = enabledFolderIDs()
        if enabled.contains(Self.recentsID) {
            return [PHAsset.fetchAssets(with: options)]
        }
        let albums = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: Array(enabled), options: nil)
        var results: [PHFetchResult<PHAsset>] = []
        albums.enumerateObjects { album, _, _ in
            results.append(PHAsset.fetchAssets(in: album, options: options))
        }
        return results
    }

    /// File IDs are derived from the identifier; on the rare collision the next free ID is used.
    @discardableResult
    private func register(_ identifier: String) -> Int? {
        if let known = fileIDs[identifier] { return known }
        guard var id = LocalPhotoIDs.fileID(forLocalIdentifier: identifier) else { return nil }
        while identifiers[id] != nil {
            id += 1
        }
        identifiers[id] = identifier
        fileIDs[identifier] = id
        return id
    }

    private func fileID(for identifier: String) -> Int? {
        register(identifier)
    }

    private func describe(_ asset: PHAsset, dayID: Int) -> LocalPhoto? {
        guard let date = asset.creationDate,
              let fileID = fileID(for: asset.localIdentifier),
              let resource = Self.originalResource(of: asset)
        else { return nil }

        let epoch = LocalPhotoIDs.epoch(for: date)
        let size = Self.fileSize(of: resource)
        let basename = resource.originalFilename
        // Without a size the AUID can't match the server; it must still be unique here.
        let auid = size > 0 ? LocalPhotoIDs.auid(epoch: epoch, size: size) : LocalPhotoIDs.md5Hex(asset.localIdentifier)
        let buid = LocalPhotoIDs.buid(basename: basename, size: size)
        let modified = asset.modificationDate ?? date
        return LocalPhoto(
            fileid: fileID,
            basename: basename,
            mimetype: UTType(resource.uniformTypeIdentifier)?.preferredMIMEType ?? "application/octet-stream",
            w: asset.pixelWidth,
            h: asset.pixelHeight,
            size: size,
            etag: String(Int(modified.timeIntervalSince1970)),
            epoch: epoch,
            auid: auid,
            buid: buid,
            dayid: dayID,
            isvideo: asset.mediaType == .video,
            video_duration: Int(asset.duration.rounded()),
            local_has_remote: hasRemote.contains(auid) || hasRemote.contains(buid)
        )
    }

    private static func originalResource(of asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        let wanted: [PHAssetResourceType] = asset.mediaType == .video ? [.video, .fullSizeVideo] : [.photo, .fullSizePhoto]
        return resources.first { wanted.contains($0.type) } ?? resources.first
    }

    /// PhotoKit exposes the original's byte size only through this undocumented key; reading
    /// the file instead would be far too slow for whole libraries. 0 when unavailable.
    private static func fileSize(of resource: PHAssetResource) -> Int64 {
        (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
    }

    // MARK: Media

    private func asset(forFileID fileID: Int) throws -> PHAsset {
        _ = buildIndex()
        guard let identifier = identifiers[fileID],
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
        else { throw PhotoLibraryError(reason: "No phone photo with ID \(fileID).") }
        return asset
    }

    private func asset(forAUID auid: String) throws -> PHAsset {
        guard let identifier = auids[auid],
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
        else { throw PhotoLibraryError(reason: "No phone photo with AUID \(auid).") }
        return asset
    }

    func previewJPEG(fileID: Int, width: Int, height: Int) async throws -> Data {
        let asset = try asset(forFileID: fileID)
        return try await Self.jpeg(of: asset, size: CGSize(width: max(width, 64), height: max(height, 64)), mode: .aspectFill)
    }

    func fullJPEG(auid: String, longEdge: Int?) async throws -> Data {
        let asset = try asset(forAUID: auid)
        let size = longEdge.map { CGSize(width: $0, height: $0) } ?? PHImageManagerMaximumSize
        return try await Self.jpeg(of: asset, size: size, mode: .aspectFit)
    }

    /// iCloud originals are downloaded when needed.
    private static func jpeg(of asset: PHAsset, size: CGSize, mode: PHImageContentMode) async throws -> Data {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let image: UIImage = try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: mode, options: options) { image, info in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    let error = info?[PHImageErrorKey] as? Error
                    continuation.resume(throwing: PhotoLibraryError(
                        reason: "Couldn't load the photo: \(error?.localizedDescription ?? "no image returned")"
                    ))
                }
            }
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw PhotoLibraryError(reason: "Couldn't encode the photo as JPEG.")
        }
        return data
    }

    /// Deletes phone photos by AUID; iOS asks the user to confirm. A dry run only counts
    /// which of them are on this phone (Memories' `IMAGE_DELETE`).
    func delete(auids requested: [String], dry: Bool) async throws -> Int {
        let identifiers = requested.compactMap { auids[$0] }
        guard !identifiers.isEmpty else { return 0 }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard !dry else { return assets.count }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
        invalidate()
        return assets.count
    }

    /// Writes a phone photo's original file into `folder` for sharing; nil when the AUID
    /// isn't a phone photo.
    func exportOriginal(auid: String, into folder: URL) async throws -> URL? {
        guard let identifier = auids[auid],
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
              let resource = Self.originalResource(of: asset)
        else { return nil }
        let file = UpstreamProxy.uniqueDestination(in: folder, for: resource.originalFilename)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: file, options: options)
        return file
    }

    /// The original file, its MIME type and capture time, for uploading to Nextcloud.
    func originalForUpload(auid: String, into folder: URL) async throws -> (file: URL, mimetype: String, epoch: Int) {
        guard let identifier = auids[auid],
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
              let date = asset.creationDate,
              let resource = Self.originalResource(of: asset),
              let file = try await exportOriginal(auid: auid, into: folder)
        else { throw PhotoLibraryError(reason: "No phone photo with AUID \(auid).") }
        let mimetype = UTType(resource.uniformTypeIdentifier)?.preferredMIMEType ?? "application/octet-stream"
        return (file, mimetype, LocalPhotoIDs.epoch(for: date))
    }

    /// Videos are served from a cached copy of the original so byte ranges work.
    func videoFile(fileID: Int) async throws -> URL {
        let asset = try asset(forFileID: fileID)
        guard let resource = Self.originalResource(of: asset) else {
            throw PhotoLibraryError(reason: "The video has no original file.")
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "local-videos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = (resource.originalFilename as NSString).pathExtension
        let file = folder.appending(path: "\(fileID).\(ext.isEmpty ? "mov" : ext)")
        if FileManager.default.fileExists(atPath: file.path) { return file }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        let partial = file.appendingPathExtension("partial")
        if FileManager.default.fileExists(atPath: partial.path) {
            try FileManager.default.removeItem(at: partial)
        }
        try await PHAssetResourceManager.default().writeData(for: resource, toFile: partial, options: options)
        try FileManager.default.moveItem(at: partial, to: file)
        return file
    }

    /// Memories' `IImageInfo` for the viewer's details panel.
    func info(fileID: Int) throws -> [String: Any] {
        let asset = try asset(forFileID: fileID)
        guard let date = asset.creationDate,
              let photo = describe(asset, dayID: LocalPhotoIDs.dayID(for: date))
        else { throw PhotoLibraryError(reason: "The phone photo has no date.") }

        let local = date.addingTimeInterval(Double(TimeZone.current.secondsFromGMT(for: date)))
        var exif: [String: Any] = ["DateTimeOriginal": Self.exifDate(local)]
        if let location = asset.location {
            exif["GPSLatitude"] = location.coordinate.latitude
            exif["GPSLongitude"] = location.coordinate.longitude
        }
        return [
            "fileid": photo.fileid,
            "basename": photo.basename,
            "mimetype": photo.mimetype,
            "w": photo.w,
            "h": photo.h,
            "size": photo.size,
            "etag": photo.etag,
            "dayid": photo.dayid,
            "datetaken": Int(local.timeIntervalSince1970),
            // D: Memories offers deleting, which iOS confirms itself.
            "permissions": "D",
            "exif": exif,
        ]
    }

    private static func exifDate(_ localAsUTC: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: localAsUTC)
    }
}
