import Foundation
import Observation
import UIKit

struct ShareError: LocalizedError {
    let reason: String

    var errorDescription: String? { reason }
}

/// Native downloads and sharing for Memories (`downloadFromUrl`, `SHARE_URL`, `SHARE_BLOBS`).
/// iOS has no downloads folder, so every download ends in the share sheet, where the
/// user picks Save Image, Save to Files, AirDrop and so on.
@MainActor
@Observable
final class ShareCenter {
    static let shared = ShareCenter()

    /// Shown while files are downloading.
    private(set) var busyMessage: String?
    /// A result to show briefly, e.g. how many photos were saved.
    private(set) var notice: String?
    /// Where Memories' next share goes; set for one share by Save to Photos.
    @ObservationIgnored var nextDestination = Destination.shareSheet

    enum Destination {
        case shareSheet
        case photos
    }
    /// Objects from `setShareBlobs`, waiting for the matching `SHARE_BLOBS` request.
    @ObservationIgnored private var pendingBlobs: [BlobObject]?

    struct BlobObject: Decodable, Equatable {
        let auid: String
        let href: String
    }

    func setPendingBlobs(_ json: String) throws {
        do {
            pendingBlobs = try JSONDecoder().decode([BlobObject].self, from: Data(json.utf8))
        } catch {
            pendingBlobs = nil
            throw ShareError(reason: "Memories sent an unreadable share list: \(error.localizedDescription)")
        }
    }

    /// `setShareBlobs` arrives as a script message while `SHARE_BLOBS` arrives over HTTP,
    /// so the request may get here first; it waits briefly for the list.
    func sharePendingBlobs(using proxy: UpstreamProxy, localOrigin: URL) async throws {
        var waited = 0
        while pendingBlobs == nil, waited < 60 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        let destination = nextDestination
        nextDestination = .shareSheet
        guard let blobs = pendingBlobs, !blobs.isEmpty else {
            throw ShareError(reason: "Memories didn't say which files to share.")
        }
        pendingBlobs = nil
        switch destination {
        case .shareSheet:
            present(try await collect(blobs, using: proxy, localOrigin: localOrigin))
        case .photos:
            // Shown natively; Memories would only say that sharing failed.
            do {
                try await saveToPhotos(blobs, using: proxy, localOrigin: localOrigin)
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    func clearNotice() {
        notice = nil
    }

    /// Downloads the originals from Nextcloud and adds them to the photo library. Photos
    /// that are already on this iPhone are skipped.
    private func saveToPhotos(_ blobs: [BlobObject], using proxy: UpstreamProxy, localOrigin: URL) async throws {
        var remote: [BlobObject] = []
        for blob in blobs {
            if !(await PhotoLibrary.shared.isOnPhone(auid: blob.auid)) {
                remote.append(blob)
            }
        }
        let skipped = blobs.count - remote.count
        guard !remote.isEmpty else {
            notice = blobs.count == 1 ? "This photo is already on this iPhone." : "These photos are already on this iPhone."
            return
        }
        guard await PhotoLibrary.requestAddAccess() else {
            throw ShareError(reason: "Cloudroll isn't allowed to add photos. Allow it under Settings → Cloudroll → Photos.")
        }

        busyMessage = remote.count == 1 ? "Saving…" : "Saving \(remote.count) files…"
        defer { busyMessage = nil }
        let folder = try Self.freshShareFolder()
        var files: [URL] = []
        var failed = 0
        for blob in remote {
            do {
                let target = try Self.upstreamTarget(for: blob.href, localOrigin: localOrigin)
                files.append(try await proxy.download(target: target, into: folder))
            } catch {
                failed += 1
                DiagnosticsLog.shared.add("native", "Saving \(blob.href) failed: \(error.localizedDescription)")
            }
        }
        if !files.isEmpty {
            try await PhotoLibrary.shared.addToLibrary(files)
        }
        notice = Self.saveSummary(saved: files.count, skipped: skipped, failed: failed)
    }

    nonisolated static func saveSummary(saved: Int, skipped: Int, failed: Int) -> String {
        var parts = [saved == 1 ? "Saved 1 item to Photos" : "Saved \(saved) items to Photos"]
        if skipped > 0 {
            parts.append("\(skipped) already on this iPhone")
        }
        if failed > 0 {
            parts.append("\(failed) couldn't be downloaded")
        }
        return parts.joined(separator: ", ") + "."
    }

    func download(_ href: String, using proxy: UpstreamProxy, localOrigin: URL) async throws {
        present(try await download([href], using: proxy, localOrigin: localOrigin))
    }

    func shareLink(_ url: URL) {
        present([url])
    }

    /// Phone photos are shared from their originals; everything else downloads from Nextcloud.
    private func collect(_ blobs: [BlobObject], using proxy: UpstreamProxy, localOrigin: URL) async throws -> [URL] {
        busyMessage = blobs.count == 1 ? "Preparing…" : "Preparing \(blobs.count) files…"
        defer { busyMessage = nil }

        let folder = try Self.freshShareFolder()
        var files: [URL] = []
        for blob in blobs {
            if let local = try await PhotoLibrary.shared.exportOriginal(auid: blob.auid, into: folder) {
                files.append(local)
            } else {
                let target = try Self.upstreamTarget(for: blob.href, localOrigin: localOrigin)
                files.append(try await proxy.download(target: target, into: folder))
            }
        }
        return files
    }

    private func download(_ hrefs: [String], using proxy: UpstreamProxy, localOrigin: URL) async throws -> [URL] {
        busyMessage = hrefs.count == 1 ? "Downloading…" : "Downloading \(hrefs.count) files…"
        defer { busyMessage = nil }

        let folder = try Self.freshShareFolder()
        var files: [URL] = []
        for href in hrefs {
            let target = try Self.upstreamTarget(for: href, localOrigin: localOrigin)
            files.append(try await proxy.download(target: target, into: folder))
        }
        return files
    }

    private func present(_ items: [Any]) {
        guard let presenter = Self.topViewController() else { return }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad presents share sheets as popovers, which need an anchor.
        sheet.popoverPresentationController?.sourceView = presenter.view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 80, width: 0, height: 0
        )
        presenter.present(sheet, animated: true)
    }

    /// Memories hands over absolute local URLs (`http://127.0.0.1:<port>/…`); only those
    /// are accepted, as their path maps onto the Nextcloud server.
    nonisolated static func upstreamTarget(for href: String, localOrigin: URL) throws -> String {
        guard let url = URL(string: href),
              url.scheme == localOrigin.scheme, url.host == localOrigin.host, url.port == localOrigin.port,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw ShareError(reason: "Refused to download \(href).") }
        components.scheme = nil
        components.host = nil
        components.port = nil
        components.fragment = nil
        guard let target = components.string, target.hasPrefix("/") else {
            throw ShareError(reason: "Refused to download \(href).")
        }
        return target
    }

    /// Previous shares are removed first so temporary files don't pile up.
    private static func freshShareFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "shares", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
