import Foundation
import Observation
import OSLog
import WebKit

/// Navigation state reported by `shell-navigation.js`.
struct NavState: Decodable, Equatable {
    struct Tab: Decodable, Equatable, Identifiable {
        let href: String
        let label: String

        var id: String { href }

        /// The root tab ends in "/"; others also match their sub-pages (e.g. a single album).
        func matches(_ path: String) -> Bool {
            path == href || (!href.hasSuffix("/") && path.hasPrefix(href + "/"))
        }

        var symbol: String {
            if href.hasSuffix("/") { return "photo.on.rectangle.angled" }
            if href.hasSuffix("/explore") { return "magnifyingglass" }
            if href.hasSuffix("/albums") { return "rectangle.stack" }
            return "square.grid.2x2"
        }
    }

    let enabled: Bool
    let tabs: [Tab]
    let path: String
    let hash: String

    static let empty = NavState(enabled: false, tabs: [], path: "", hash: "")

    var selectedTab: Tab? { tabs.first { $0.matches(path) } }

    /// Memories encodes overlays in the fragment (`#v/…` viewer, `#s` selection, `#e` editor,
    /// `#m` modal, `#ss` settings, …). Only `#day` keeps the page itself in front.
    var showsTabBar: Bool {
        guard enabled, !tabs.isEmpty else { return false }
        let fragments = hash.dropFirst().split(separator: "&").map { $0.split(separator: "/").first ?? "" }
        return fragments.allSatisfy { $0 == "day" }
    }
}

/// Connects the native tab bar to the shell page.
@MainActor
@Observable
final class WebNavigation {
    private(set) var state = NavState.empty
    @ObservationIgnored weak var webView: WKWebView?

    func update(_ state: NavState) {
        self.state = state
    }

    private nonisolated static let log = Logger(subsystem: "app.cloudroll", category: "navigation")

    func select(_ tab: NavState.Tab) {
        guard tab != state.selectedTab, let webView else { return }
        webView.evaluateJavaScript("window.__cloudrollSelectTab(\(ShellPage.jsString(tab.href)))") { result, error in
            if let error {
                Self.log.error("Selecting tab \(tab.href, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            } else if result as? Bool != true {
                Self.log.error("Memories has no tab link for \(tab.href, privacy: .public)")
            }
        }
    }

    /// The script that hides Memories' bar and reports navigation, from the app bundle.
    static func script() throws -> String {
        guard let url = Bundle.main.url(forResource: "shell-navigation", withExtension: "js") else {
            throw ProxyError(reason: "shell-navigation.js is missing from the app bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
