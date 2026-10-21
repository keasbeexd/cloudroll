import Foundation

/// Which photos the main timeline shows. Albums, folders and other views are unaffected.
enum TimelineSource: String, CaseIterable, Identifiable {
    case all
    case cloud
    case phone

    static let storageKey = "timelineSource"

    /// Read from UserDefaults (thread-safe) so the local server can check it per request.
    static var current: TimelineSource {
        UserDefaults.standard.string(forKey: storageKey).flatMap(TimelineSource.init(rawValue:)) ?? .all
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All photos"
        case .cloud: "Nextcloud only"
        case .phone: "This iPhone only"
        }
    }

    var symbol: String {
        switch self {
        case .all: "photo.on.rectangle.angled"
        case .cloud: "cloud"
        case .phone: "iphone"
        }
    }

    /// The main timeline's day requests carry only layout parameters; any filter parameter
    /// (albums, folder, archive, …) means another view, which is never hidden.
    static func isMainTimelineDays(method: String, path: String, queryNames: [String], webRoot: String) -> Bool {
        let layoutOnly: Set<String> = ["monthView", "reverse"]
        let isDaysPath = [webRoot + "/index.php/apps/memories/api/days", webRoot + "/apps/memories/api/days"].contains(path)
        return isDaysPath && ["GET", "POST"].contains(method.uppercased()) && Set(queryNames).isSubset(of: layoutOnly)
    }
}
