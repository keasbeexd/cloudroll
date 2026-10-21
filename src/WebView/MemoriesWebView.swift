import SwiftUI
import WebKit

enum SessionError: LocalizedError {
    case appPasswordRejected

    var errorDescription: String? {
        "Nextcloud didn't accept the saved app password. It may have been revoked; sign out and sign in again."
    }
}

struct MemoriesWebView: UIViewRepresentable {
    let entry: URL
    let credential: Credential
    let onLoadError: (Error) -> Void
    let onSignOut: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(entry: entry, credential: credential, onLoadError: onLoadError, onSignOut: onSignOut)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.applicationNameForUserAgent = HTTP.userAgent
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.loadMemories(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        /// A login redirect this soon after sending the app password means it was rejected.
        private static let rejectionWindow: TimeInterval = 10

        private let entry: URL
        private let credential: Credential
        private let onLoadError: (Error) -> Void
        private let onSignOut: () -> Void
        private var lastAuthenticatedLoad: Date?

        init(entry: URL, credential: Credential, onLoadError: @escaping (Error) -> Void, onSignOut: @escaping () -> Void) {
            self.entry = entry
            self.credential = credential
            self.onLoadError = onLoadError
            self.onSignOut = onSignOut
        }

        /// Sends the app password once; Nextcloud answers with a session cookie that
        /// authenticates every later request from the web view.
        func loadMemories(in webView: WKWebView) {
            lastAuthenticatedLoad = .now
            var request = URLRequest(url: entry)
            request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
            webView.load(request)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let target = action.request.url else { return .allow }

            if target.host != credential.server.host {
                // Links the user taps to other sites open in Safari; redirects (e.g. SSO) stay in-app.
                guard action.navigationType == .linkActivated else { return .allow }
                await UIApplication.shared.open(target)
                return .cancel
            }
            guard action.targetFrame?.isMainFrame == true else { return .allow }

            if target.path.hasSuffix("/logout") {
                onSignOut()
                return .cancel
            }
            if target.path.hasSuffix("/login") {
                handleLoginRedirect(in: webView)
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            report(error)
        }

        /// The web session expired: sign in again silently, unless that just failed.
        private func handleLoginRedirect(in webView: WKWebView) {
            if let last = lastAuthenticatedLoad, Date.now.timeIntervalSince(last) < Self.rejectionWindow {
                onLoadError(SessionError.appPasswordRejected)
                return
            }
            loadMemories(in: webView)
        }

        private func report(_ error: Error) {
            guard !Self.isExpectedCancellation(error) else { return }
            onLoadError(error)
        }

        /// Cancellations caused by our own policy decisions or by a newer navigation are not failures.
        private static func isExpectedCancellation(_ error: Error) -> Bool {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
            return nsError.domain == WKErrorDomain && nsError.code == 102 // frame load interrupted by policy change
        }
    }
}
