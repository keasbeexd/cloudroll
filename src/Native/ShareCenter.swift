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
        guard let blobs = pendingBlobs, !blobs.isEmpty else {
            throw ShareError(reason: "Memories didn't say which files to share.")
        }
        pendingBlobs = nil
        let files = try await download(blobs.map(\.href), using: proxy, localOrigin: localOrigin)
        present(files)
    }

    func download(_ href: String, using proxy: UpstreamProxy, localOrigin: URL) async throws {
        present(try await download([href], using: proxy, localOrigin: localOrigin))
    }

    func shareLink(_ url: URL) {
        present([url])
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
