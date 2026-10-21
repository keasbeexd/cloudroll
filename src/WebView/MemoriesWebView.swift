import SwiftUI
import WebKit

enum SessionError: LocalizedError {
    case appPasswordRejected

    var errorDescription: String? {
        "Nextcloud didn't accept the saved app password. It may have been revoked; sign out and sign in again."
    }
}

struct MemoriesWebView: UIViewRepresentable {
    let source: MemoriesSource
    let credential: Credential
    let navigation: WebNavigation
    let onLoadError: (Error) -> Void
    let onSignOut: () -> Void
    let onBridgeMessage: (BridgeMessage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(source: source, credential: credential, onLoadError: onLoadError, onSignOut: onSignOut, onBridgeMessage: onBridgeMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.applicationNameForUserAgent = HTTP.userAgent
        if case .shell = source {
            config.userContentController.addUserScript(WKUserScript(
                source: NativeBridgeScript.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
            do {
                config.userContentController.addUserScript(WKUserScript(
                    source: try WebNavigation.script(),
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                ))
            } catch {
                // Memories keeps its own navigation. Reported after this view update,
                // since state can't change while SwiftUI builds the view.
                let onLoadError = onLoadError
                Task { @MainActor in onLoadError(error) }
            }
            config.userContentController.add(WeakMessageHandler(context.coordinator), name: NativeBridgeScript.handlerName)
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        navigation.webView = webView
        context.coordinator.load(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: NativeBridgeScript.handlerName)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        /// A login redirect this soon after sending the app password means it was rejected.
        private static let rejectionWindow: TimeInterval = 10

        private let source: MemoriesSource
        private let credential: Credential
        private let onLoadError: (Error) -> Void
        private let onSignOut: () -> Void
        private let onBridgeMessage: (BridgeMessage) -> Void
        private var lastAuthenticatedLoad: Date?

        init(
            source: MemoriesSource,
            credential: Credential,
            onLoadError: @escaping (Error) -> Void,
            onSignOut: @escaping () -> Void,
            onBridgeMessage: @escaping (BridgeMessage) -> Void
        ) {
            self.source = source
            self.credential = credential
            self.onLoadError = onLoadError
            self.onSignOut = onSignOut
            self.onBridgeMessage = onBridgeMessage
        }

        private var entry: URL {
            switch source {
            case .direct(let url), .shell(let url, _): url
            }
        }

        func load(in webView: WKWebView) {
            switch source {
            case .direct:
                loadDirect(in: webView)
            case .shell(let url, _):
                guard let cookie = ShellHost.shared.authCookie else {
                    onLoadError(ProxyError(reason: "couldn't create the local session cookie"))
                    return
                }
                Task {
                    await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                    webView.load(URLRequest(url: url))
                }
            }
        }

        /// Direct mode sends the app password once; Nextcloud answers with a session
        /// cookie that authenticates every later request from the web view.
        private func loadDirect(in webView: WKWebView) {
            lastAuthenticatedLoad = .now
            var request = URLRequest(url: entry)
            request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
            webView.load(request)
        }

        func receive(_ message: WKScriptMessage) {
            // Only the shell page itself may drive native code.
            guard message.frameInfo.isMainFrame,
                  message.frameInfo.securityOrigin.host == "127.0.0.1",
                  let bridgeMessage = BridgeMessage(body: message.body)
            else { return }
            if bridgeMessage == .logout {
                onSignOut()
                return
            }
            onBridgeMessage(bridgeMessage)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            // about:, blob: and data: documents belong to the page itself.
            guard let target = action.request.url, ["http", "https"].contains(target.scheme?.lowercased() ?? "") else {
                return .allow
            }
            let isHome = target.host == entry.host && target.port == entry.port

            if !isHome {
                guard action.targetFrame?.isMainFrame == true else { return .allow }
                if case .shell = source {
                    // The shell never leaves the local origin; other pages open in Safari.
                    await UIApplication.shared.open(target)
                    return .cancel
                }
                // Links the user taps to other sites open in Safari; redirects (e.g. SSO) stay in-app.
                guard action.navigationType == .linkActivated else { return .allow }
                await UIApplication.shared.open(target)
                return .cancel
            }
            if case .shell(_, let webRoot) = source {
                guard action.targetFrame?.isMainFrame == true else { return .allow }
                return await shellPolicy(for: target, webRoot: webRoot)
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

        /// Pages the local server would refuse (other Nextcloud apps, settings) open on
        /// the real server in Safari, so the shell never shows a dead end.
        private func shellPolicy(for target: URL, webRoot: String) async -> WKNavigationActionPolicy {
            switch LocalRouter(webRoot: webRoot).route(method: "GET", path: target.path, wantsDocument: true) {
            case .shell, .redirectToEntry:
                return .allow
            case .asset, .bridge, .proxy, .notFound:
                guard var components = URLComponents(url: credential.server, resolvingAgainstBaseURL: false) else {
                    return .cancel
                }
                components.path = target.path
                components.query = target.query
                if let serverPage = components.url {
                    await UIApplication.shared.open(serverPage)
                }
                return .cancel
            }
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
            loadDirect(in: webView)
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

/// WKUserContentController retains its handlers; this breaks the cycle with the coordinator.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var coordinator: MemoriesWebView.Coordinator?

    init(_ coordinator: MemoriesWebView.Coordinator) {
        self.coordinator = coordinator
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            coordinator?.receive(message)
        }
    }
}
