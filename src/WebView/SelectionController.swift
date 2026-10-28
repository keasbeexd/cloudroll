import Foundation
import Observation
import OSLog
import WebKit

/// Selection mode as reported by `shell-selection.js`.
struct SelectionState: Decodable, Equatable {
    let active: Bool
    /// Memories' own, translated "N selected" text.
    let label: String
    /// Every selected photo on screen is already a favorite; absent from older scripts.
    var allFavorite: Bool? = nil

    static let inactive = SelectionState(active: false, label: "")
}

/// Runs Memories' selection actions from the native toolbar, identified by icon class.
@MainActor
@Observable
final class SelectionController {
    enum Action: String, CaseIterable {
        case share
        case save
        case addToAlbum
        case favorite
        case delete

        var title: String {
            switch self {
            case .share: "Share"
            case .save: "Save to Photos"
            case .addToAlbum: "Add to Album"
            case .favorite: "Favorite"
            case .delete: "Delete"
            }
        }

        var symbol: String {
            switch self {
            case .share: "square.and.arrow.up"
            case .save: "square.and.arrow.down"
            case .addToAlbum: "rectangle.stack.badge.plus"
            case .favorite: "star"
            case .delete: "trash"
            }
        }

        /// Icon classes of Memories' matching actions, tried in order (albums offer
        /// "Remove from album" instead of "Delete").
        var icons: [String] {
            switch self {
            case .share, .save: ["share-variant-icon"]
            case .addToAlbum: ["image-album-icon"]
            case .favorite: ["star-icon"]
            case .delete: ["trash-can-outline-icon", "book-remove-icon"]
            }
        }
    }

    private static let log = Logger(subsystem: "io.github.keasbeexd.cloudroll", category: "selection")

    private(set) var state = SelectionState.inactive
    @ObservationIgnored weak var webView: WKWebView?

    func update(_ state: SelectionState) {
        self.state = state
    }

    /// Returns false when Memories offers no such action here.
    func perform(_ action: Action) async -> Bool {
        if action == .share {
            return await call("return await window.__cloudrollSelection.shareOriginal()")
        }
        // Memories' share of the originals, with the files going to Photos instead.
        if action == .save {
            ShareCenter.shared.nextDestination = .photos
            defer { ShareCenter.shared.nextDestination = .shareSheet }
            return await call("return await window.__cloudrollSelection.shareOriginal()")
        }
        for icon in action.icons where await call("return await window.__cloudrollSelection.run(icon)", ["icon": icon]) {
            return true
        }
        return false
    }

    func showMore() async {
        _ = await call("return window.__cloudrollSelection.more()")
    }

    func cancel() async {
        _ = await call("return window.__cloudrollSelection.cancel()")
    }

    private func call(_ body: String, _ arguments: [String: Any] = [:]) async -> Bool {
        guard let webView else { return false }
        do {
            return try await webView.callAsyncJavaScript(body, arguments: arguments, contentWorld: .page) as? Bool ?? false
        } catch {
            Self.log.error("Selection action failed: \(error.localizedDescription, privacy: .public)")
            DiagnosticsLog.shared.add("native", "Selection action failed: \(error.localizedDescription)")
            return false
        }
    }
}
