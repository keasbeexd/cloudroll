import Foundation

/// Inputs for the generated Memories page, taken from `api/describe`.
struct ShellConfig: Sendable {
    let webRoot: String
    let user: String?
    let stylesheets: [[String: String]]

    init(info: MemoriesInfo) {
        webRoot = info.webRoot
        user = info.uid
        // Null attributes (e.g. "media": null) are simply left out.
        stylesheets = (info.cssManifest ?? []).map { $0.compactMapValues { $0 } }
    }

    init(webRoot: String, user: String?, stylesheets: [[String: String]]) {
        self.webRoot = webRoot
        self.user = user
        self.stylesheets = stylesheets
    }
}

/// Stands in for the page Nextcloud would render around Memories. Memories' native
/// mode needs only a few globals plus its own scripts; stylesheets load through the proxy.
enum ShellPage {
    /// Without `requestToken` Memories still works: its first API call fails the CSRF
    /// check and it fetches a token itself, costing one round trip.
    static func html(_ config: ShellConfig, nonce: String, requestToken: String? = nil) -> String {
        let userAttribute = config.user.map { " data-user=\"\(escapeHTML($0))\"" } ?? ""
        let tokenAttribute = requestToken.map { " data-requesttoken=\"\(escapeHTML($0))\"" } ?? ""
        let stylesheets = config.stylesheets.compactMap(linkTag).joined(separator: "\n    ")
        let webRoot = jsString(config.webRoot)
        return """
        <!DOCTYPE html>
        <html>
        <head\(userAttribute)\(tokenAttribute)>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
            <title>Memories</title>
            \(stylesheets)
            <script src="\(LocalRouter.assetPrefix)memories-l10n.js"></script>
        </head>
        <body>
            <div id="skip-actions"></div>
            <div id="content"></div>
            <script nonce="\(nonce)">
                window._oc_webroot = \(webRoot);
                window._oc_appswebroots = { memories: \(webRoot) + '/apps/memories' };
                window._oc_capabilities = { files: {
                    forbidden_filename_characters: ['/', '\\\\'],
                    forbidden_filenames: ['.htaccess'],
                    forbidden_filename_basenames: [],
                    forbidden_filename_extensions: ['.part', '.filepart']
                } };
            </script>
            <script defer src="\(LocalRouter.assetPrefix)memories-main.js"></script>
        </body>
        </html>
        """
    }

    /// Only our nonce'd inline script runs; everything else must come from the local origin.
    static func contentSecurityPolicy(nonce: String) -> String {
        [
            "default-src 'self'",
            "script-src 'self' blob: 'nonce-\(nonce)'",
            "worker-src 'self' blob:",
            "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data: blob: https:",
            "media-src 'self' blob: data:",
            "connect-src 'self' https: data: blob:",
            "font-src 'self' data:",
            "frame-src 'self' https://www.openstreetmap.org",
            "object-src 'none'",
            "base-uri 'self'",
            "form-action 'self'",
            "frame-ancestors 'none'",
        ].joined(separator: "; ")
    }

    static func randomNonce() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
    }

    /// Stylesheets must be server-relative so they load through the proxy, never from elsewhere.
    private static func linkTag(_ attributes: [String: String]) -> String? {
        guard let href = attributes["href"], href.hasPrefix("/"), !href.hasPrefix("//") else { return nil }
        var parts = ["rel=\"\(escapeHTML(attributes["rel"] ?? "stylesheet"))\""]
        for (name, value) in attributes.sorted(by: { $0.key < $1.key }) where name != "rel" {
            guard name.allSatisfy({ $0.isLetter || $0 == "-" }) else { continue }
            parts.append("\(name)=\"\(escapeHTML(value))\"")
        }
        return "<link \(parts.joined(separator: " "))>"
    }

    static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Double-quoted JS string literal. `<`, `>` and `&` become \u escapes so the value
    /// can't close the surrounding script tag.
    static func jsString(_ value: String) -> String {
        var literal = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": literal += "\\\\"
            case "\"": literal += "\\\""
            case "\n": literal += "\\n"
            case "\r": literal += "\\r"
            case "<", ">", "&", "\u{2028}", "\u{2029}":
                literal += String(format: "\\u%04x", scalar.value)
            case _ where scalar.value < 0x20:
                literal += String(format: "\\u%04x", scalar.value)
            default:
                literal.unicodeScalars.append(scalar)
            }
        }
        return literal + "\""
    }
}
