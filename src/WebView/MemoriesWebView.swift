import SwiftUI
import WebKit

struct MemoriesWebView: UIViewRepresentable {
    let url: URL
    let onLoadError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(host: url.host, onLoadError: onLoadError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let host: String?
        private let onLoadError: (Error) -> Void

        init(host: String?, onLoadError: @escaping (Error) -> Void) {
            self.host = host
            self.onLoadError = onLoadError
        }

        /// Links the user taps to other sites open in Safari; redirects (e.g. SSO login) stay in-app.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated,
                  let target = action.request.url,
                  target.host != host
            else { return .allow }
            await UIApplication.shared.open(target)
            return .cancel
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            report(error)
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
