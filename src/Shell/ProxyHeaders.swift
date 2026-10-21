import Foundation

/// Header rules for forwarding between the web view and Nextcloud.
enum ProxyHeaders {
    /// Connection-level headers (RFC 9110 §7.6.1) that never pass through a proxy.
    private static let hopByHop: Set<String> = [
        "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
        "te", "trailer", "transfer-encoding", "upgrade", "host",
    ]

    /// Dropped from requests: the Cookie header carries the local secret, URLSession
    /// negotiates compression itself, and the proxy supplies its own Authorization.
    private static let requestOnly: Set<String> = [
        "cookie", "accept-encoding", "authorization", "origin", "referer", "content-length",
    ]

    /// Dropped from responses: upstream cookies stay in the proxy's own cookie jar.
    private static let responseOnly: Set<String> = ["set-cookie", "strict-transport-security"]

    static func forwardedRequest(_ headers: [(name: String, value: String)]) -> [(name: String, value: String)] {
        headers.filter { header in
            let name = header.name.lowercased()
            return !hopByHop.contains(name) && !requestOnly.contains(name)
        }
    }

    /// URLSession hands back decompressed bytes but keeps the original Content-Encoding
    /// and Content-Length, so both go when the body was encoded.
    static func returnedResponse(_ response: HTTPURLResponse, upstreamOrigin: URL) -> [(name: String, value: String)] {
        let wasEncoded = response.value(forHTTPHeaderField: "Content-Encoding") != nil
        return response.allHeaderFields.compactMap { key, value -> (name: String, value: String)? in
            guard let name = key as? String, let value = value as? String else { return nil }
            let lower = name.lowercased()
            if hopByHop.contains(lower) || responseOnly.contains(lower) { return nil }
            if wasEncoded, lower == "content-encoding" || lower == "content-length" { return nil }
            if lower == "location" { return (name, localLocation(value, upstreamOrigin: upstreamOrigin)) }
            return (name, value)
        }
    }

    /// Keeps the web view on the local origin when Nextcloud redirects to its own absolute URL.
    static func localLocation(_ location: String, upstreamOrigin: URL) -> String {
        guard let url = URL(string: location),
              url.scheme == upstreamOrigin.scheme,
              url.host == upstreamOrigin.host,
              url.port == upstreamOrigin.port,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return location }
        components.scheme = nil
        components.host = nil
        components.port = nil
        components.user = nil
        components.password = nil
        return components.string ?? location
    }
}
