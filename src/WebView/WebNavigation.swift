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
    /// The user is scrolling down a list; absent from older script versions.
    var collapsed: Bool? = nil
    /// The page has Memories' mobile header (timeline-style views).
    var header: Bool? = nil
    /// A Memories dialog or the search field is on screen.
    var dialog: Bool? = nil
    /// The URL query without "?", e.g. "q=frog" on the search page.
    var query: String? = nil

    static let empty = NavState(enabled: false, tabs: [], path: "", hash: "")

    var selectedTab: Tab? { tabs.first { $0.matches(path) } }

    /// A dialog, the viewer, the editor or settings is open (anything but selection and days).
    var overlayOpen: Bool {
        dialog == true || hash.dropFirst().split(separator: "&").map { $0.split(separator: "/").first ?? "" }
            .contains { $0 != "day" && $0 != "s" }
    }

    /// Memories encodes overlays in the fragment (`#v/…` viewer, `#s` selection, `#e` editor,
    /// `#m` modal, `#ss` settings, …). Only `#day` keeps the page itself in front.
    var showsTabBar: Bool {
        guard enabled, !tabs.isEmpty, dialog != true else { return false }
        let fragments = hash.dropFirst().split(separator: "&").map { $0.split(separator: "/").first ?? "" }
        return fragments.allSatisfy { $0 == "day" }
    }
}

/// Connects the native tab bar to the shell page.
@MainActor
@Observable
final class WebNavigation {
    private(set) var state = NavState.empty
    private(set) var header = HeaderState.none
    /// Highlighted on tap, before Memories reports the new route, so the bar reacts instantly.
    private var pendingTab: NavState.Tab?
    @ObservationIgnored weak var webView: WKWebView?

    var highlightedTab: NavState.Tab? { pendingTab ?? state.selectedTab }

    func update(_ header: HeaderState) {
        self.header = header
    }

    func update(_ state: NavState) {
        self.state = state
        pendingTab = nil
    }

    private nonisolated static let log = Logger(subsystem: "io.github.keasbeexd.cloudroll", category: "navigation")

    /// Title for the native header: Memories' own, else derived from the route.
    var headerTitle: String {
        if !header.title.isEmpty { return header.title }
        if header.kind == "timeline", let tab = highlightedTab { return tab.label }
        let derived = HeaderState.title(forPath: state.path, query: state.query ?? "")
        return derived.isEmpty ? (highlightedTab?.label ?? "Memories") : derived
    }

    /// Clicks one of Memories' (hidden) header buttons by icon class.
    func headerAction(_ icon: String) { evaluate("window.__cloudrollHeader.action(\(ShellPage.jsString(icon)))") }
    func headerBack() { evaluate("window.__cloudrollHeader.back()") }
    func headerMore() { evaluate("window.__cloudrollHeader.more()") }
    func search(_ query: String) { evaluate("window.__cloudrollHeader.search(\(ShellPage.jsString(query)))") }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script) { result, error in
            if let error {
                Self.log.error("Header action failed: \(error.localizedDescription, privacy: .public)")
            } else if result as? Bool != true {
                Self.log.error("Memories has no matching header button")
            }
        }
    }

    func expand() {
        webView?.evaluateJavaScript("window.__cloudrollExpandBar()") { _, error in
            if let error {
                Self.log.error("Expanding the tab bar failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func select(_ tab: NavState.Tab) {
        guard tab != state.selectedTab, let webView else { return }
        pendingTab = tab
        webView.evaluateJavaScript("window.__cloudrollSelectTab(\(ShellPage.jsString(tab.href)))") { result, error in
            if let error {
                Self.log.error("Selecting tab \(tab.href, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            } else if result as? Bool != true {
                Self.log.error("Memories has no tab link for \(tab.href, privacy: .public)")
            }
        }
    }

    /// A script shipped in the app bundle (`shell-navigation`, `shell-diagnostics`).
    static func bundledScript(_ name: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js") else {
            throw ProxyError(reason: "\(name).js is missing from the app bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
