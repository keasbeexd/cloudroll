import Foundation
import Observation
import OSLog
import WebKit

/// The photo Memories' (hidden) viewer is showing, as reported by `shell-viewer.js`.
struct ViewerPhoto: Decodable, Equatable, Hashable {
    let fileid: Int
    let auid: String
    let etag: String
    /// Memories' Live Photo ID: the MOV's content identifier, or `self__…` for motion photos
    /// with the video inside the image. Empty for other photos.
    var liveid: String?
    let basename: String
    let dayid: Int
    let w: Int
    let h: Int
    let video: Bool
    let favorite: Bool
    let local: Bool
    /// Memories offers its editor for this photo.
    var editable: Bool?
}

struct ViewerState: Decodable, Equatable {
    let open: Bool
    /// Memories' editor is open; the native viewer steps aside for it.
    var editing: Bool?
    var photo: ViewerPhoto?
    /// The photos either side of the current one, shown while swiping.
    var previous: ViewerPhoto?
    var next: ViewerPhoto?

    static let closed = ViewerState(open: false, photo: nil)
}

/// Where the native viewer loads a photo from: the local shell serves both server
/// photos (proxied Memories API) and phone photos (native bridge).
struct ViewerMedia: Equatable, Hashable {
    let preview: URL
    let full: URL
    let video: URL?
    /// The motion part of a server Live Photo. Phone Live Photos come from PhotoKit instead.
    let live: URL?

    init?(photo: ViewerPhoto, origin: URL, webRoot: String) {
        let o = origin.absoluteString
        let preview: String
        let full: String
        let video: String
        var live: String?
        if photo.local {
            // The etag (the modification date) changes when the photo is edited.
            let etag = Self.encode(photo.etag)
            preview = "\(o)/image/preview/\(photo.fileid)?c=\(etag)&x=1024&y=1024"
            full = "\(o)/image/full/\(Self.encode(photo.auid))?size=2560&c=\(etag)"
            video = "\(o)/video/full/\(photo.fileid)"
        } else {
            let api = "\(o)\(webRoot)/index.php/apps/memories/api"
            let etag = Self.encode(photo.etag)
            preview = "\(api)/image/preview/\(photo.fileid)?c=\(etag)&x=1024&y=1024&a=0"
            full = "\(api)/image/decodable/\(photo.fileid)?etag=\(etag)"
            video = "\(api)/stream/\(photo.fileid)"
            if let liveid = photo.liveid, !liveid.isEmpty, !photo.video {
                live = "\(api)/video/livephoto/\(photo.fileid)?etag=\(etag)&liveid=\(Self.encode(liveid))"
            }
        }
        guard let previewURL = URL(string: preview), let fullURL = URL(string: full) else { return nil }
        self.preview = previewURL
        self.full = fullURL
        self.video = photo.video ? URL(string: video) : nil
        self.live = live.flatMap(URL.init(string:))
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?/+"))) ?? value
    }
}

/// Drives Memories' hidden viewer (next/previous, close, actions) for the native one.
@MainActor
@Observable
final class ViewerController {
    enum Action {
        case share
        case favorite
        case addToAlbum
        case delete
        case edit

        /// Icon classes of Memories' viewer actions, tried in order.
        var icons: [String] {
            switch self {
            case .share: ["share-variant-icon"]
            case .favorite: ["star-outline-icon", "star-icon"]
            case .addToAlbum: ["image-album-icon"]
            case .delete: ["trash-can-outline-icon", "book-remove-icon"]
            case .edit: ["tune-icon"]
            }
        }
    }

    private static let log = Logger(subsystem: "io.github.keasbeexd.cloudroll", category: "viewer")

    private(set) var state = ViewerState.closed
    @ObservationIgnored weak var webView: WKWebView?

    func update(_ state: ViewerState) {
        self.state = state
    }

    func next() async { _ = await call("return window.__cloudrollViewer.next()") }
    func previous() async { _ = await call("return window.__cloudrollViewer.previous()") }
    func close() async { _ = await call("return window.__cloudrollViewer.close()") }

    /// The current photo's details, once Memories has loaded them; nil if it can't.
    func info() async -> PhotoInfo? {
        guard let webView else { return nil }
        do {
            let json = try await webView.callAsyncJavaScript(
                "return await window.__cloudrollViewer.info()", arguments: [:], contentWorld: .page
            ) as? String
            return try json.map { try JSONDecoder().decode(PhotoInfo.self, from: Data($0.utf8)) }
        } catch {
            DiagnosticsLog.shared.add("native", "Photo info failed: \(error.localizedDescription)")
            return nil
        }
    }

    func perform(_ action: Action) async -> Bool {
        if action == .share {
            return await call("return await window.__cloudrollViewer.shareOriginal()")
        }
        if action == .edit {
            return await call("return await window.__cloudrollViewer.edit()")
        }
        return await call("return await window.__cloudrollViewer.run(icons)", ["icons": action.icons])
    }

    private func call(_ body: String, _ arguments: [String: Any] = [:]) async -> Bool {
        guard let webView else { return false }
        do {
            return try await webView.callAsyncJavaScript(body, arguments: arguments, contentWorld: .page) as? Bool ?? false
        } catch {
            Self.log.error("Viewer action failed: \(error.localizedDescription, privacy: .public)")
            DiagnosticsLog.shared.add("native", "Viewer action failed: \(error.localizedDescription)")
            return false
        }
    }
}
