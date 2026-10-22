import Foundation

/// Memories' header for the current view, as described by `shell-header.js`.
struct HeaderState: Decodable, Equatable {
    struct Action: Decodable, Equatable, Hashable {
        /// vue-material-design-icons class, e.g. "plus-icon".
        let icon: String
        /// Memories' own, translated label.
        let label: String

        /// SF Symbol for Memories' header icons; unknown icons get a neutral glyph.
        var symbol: String {
            switch icon {
            case "plus-icon": "plus"
            case "share-variant-icon": "square.and.arrow.up"
            case "upload-icon", "cloud-upload-icon": "icloud.and.arrow.up"
            case "download-icon": "arrow.down.circle"
            case "pencil-icon": "pencil"
            case "trash-can-outline-icon": "trash"
            case "delete-empty-icon": "trash.slash"
            case "image-multiple-icon": "photo.on.rectangle"
            case "folder-multiple-icon": "folder"
            case "home-icon": "house"
            case "magnify-icon": "magnifyingglass"
            case _ where icon.hasPrefix("sort-"): "arrow.up.arrow.down"
            default: "circle.grid.2x2"
            }
        }

        /// Upload goes through the native menu, so it anchors under the button.
        var isUpload: Bool { icon == "upload-icon" || icon == "cloud-upload-icon" }
    }

    /// "timeline", "explore", "matter" (a view's title row) or "none".
    let kind: String
    let title: String
    let back: Bool
    let actions: [Action]
    let more: Bool

    static let none = HeaderState(kind: "none", title: "", back: false, actions: [], more: false)

    /// Memories leaves some titles out of its title row (album names sit further down,
    /// folders show a breadcrumb), so they're derived from the route instead.
    static func title(forPath path: String, query: String) -> String {
        let route = path.components(separatedBy: "/apps/memories").last ?? ""
        let parts = route.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        switch parts.first {
        case "albums" where parts.count >= 3, "recognize" where parts.count >= 3, "facerecognition" where parts.count >= 3:
            return parts[2]
        case "places" where parts.count >= 2, "tags" where parts.count >= 2:
            return parts.last ?? ""
        case "folders":
            return parts.count > 1 ? parts.last ?? "" : "Folders"
        case "search":
            let q = URLComponents(string: "?" + query)?.queryItems?.first { $0.name == "q" }?.value
            return q.map { "“\($0)”" } ?? "Search"
        case "favorites": return "Favorites"
        case "videos": return "Videos"
        case "archive": return "Archive"
        case "thisday": return "On this day"
        case "map": return "Map"
        case "trash": return "Trash"
        default: return ""
        }
    }

    /// The Nextcloud folder shown in Folders view, for uploading into it.
    static func folder(forPath path: String) -> String? {
        let route = path.components(separatedBy: "/apps/memories").last ?? ""
        guard route == "/folders" || route.hasPrefix("/folders/") else { return nil }
        let rest = route.dropFirst("/folders".count)
        let decoded = String(rest).removingPercentEncoding ?? String(rest)
        return decoded.isEmpty ? "/" : decoded
    }
}
