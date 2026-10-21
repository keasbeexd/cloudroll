import FlyingFox
import FlyingSocks
import Foundation

struct ProxyError: LocalizedError {
    let reason: String

    var errorDescription: String? { "Forwarding to Nextcloud failed: \(reason)." }
}

/// Forwards local-server requests to Nextcloud with the stored app password,
/// streaming response bodies so large videos never sit in memory.
struct UpstreamProxy: Sendable {
    /// Scheme, host and port of the Nextcloud server; local paths map onto it unchanged.
    let origin: URL
    let authorization: String
    private let session: URLSession

    /// `configuration` is replaceable so tests can stub the server with a URLProtocol.
    init(origin: URL, authorization: String, configuration config: URLSessionConfiguration = .ephemeral) {
        self.origin = origin
        self.authorization = authorization
        // An ephemeral session keeps Nextcloud's session cookies in its own in-memory
        // jar, separate from the web view.
        session = URLSession(configuration: config)
    }

    init(credential: Credential) throws {
        guard var components = URLComponents(url: credential.server, resolvingAgainstBaseURL: false) else {
            throw ProxyError(reason: "invalid server address \(credential.server)")
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let origin = components.url else {
            throw ProxyError(reason: "invalid server address \(credential.server)")
        }
        self.init(origin: origin, authorization: credential.authorizationHeader)
    }

    func forward(_ request: HTTPRequest) async throws -> HTTPResponse {
        let upstream = try await upstreamRequest(for: request)
        let (bytes, response) = try await session.bytes(for: upstream, delegate: NoRedirects.shared)
        guard let http = response as? HTTPURLResponse else {
            throw ProxyError(reason: "the server sent a non-HTTP response")
        }

        let headers = ProxyHeaders.returnedResponse(http, upstreamOrigin: origin)
        var responseHeaders = HTTPHeaders()
        for header in headers {
            responseHeaders.addValue(header.value, for: HTTPHeader(header.name))
        }
        let status = HTTPStatusCode(http.statusCode, phrase: HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        let isEncoded = http.value(forHTTPHeaderField: "Content-Encoding") != nil
        let body = isEncoded || http.expectedContentLength < 0
            ? HTTPBodySequence(from: StreamedBytes(bytes))
            : HTTPBodySequence(from: StreamedBytes(bytes), count: Int(http.expectedContentLength))
        return HTTPResponse(statusCode: status, headers: responseHeaders, body: body)
    }

    /// A CSRF token for the shell page, fetched in the proxy's cookie session so it
    /// matches the session later API calls use.
    func requestToken(webRoot: String) async throws -> String {
        guard let url = URL(string: webRoot + "/index.php/csrftoken", relativeTo: origin)?.absoluteURL else {
            throw ProxyError(reason: "invalid web root \(webRoot)")
        }
        var request = URLRequest(url: url)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try HTTP.require(200, response, context: "Fetching a request token")
        struct Token: Decodable { let token: String }
        return try JSONDecoder().decode(Token.self, from: data).token
    }

    func upstreamRequest(for request: HTTPRequest) async throws -> URLRequest {
        // The target is relative; reject anything (e.g. "//host/…") that would leave the server.
        guard let url = URL(string: request.target.rawValue, relativeTo: origin)?.absoluteURL,
              url.scheme == origin.scheme, url.host == origin.host, url.port == origin.port
        else { throw ProxyError(reason: "refused target \(request.target.rawValue)") }

        var upstream = URLRequest(url: url)
        upstream.httpMethod = request.method.rawValue
        let incoming = request.headers.map { (name: $0.key.rawValue, value: $0.value) }
        for header in ProxyHeaders.forwardedRequest(incoming) {
            upstream.addValue(header.value, forHTTPHeaderField: header.name)
        }
        upstream.setValue(authorization, forHTTPHeaderField: "Authorization")
        // Request bodies (API calls, photo uploads) are small enough to buffer.
        let body = try await request.bodyData
        if !body.isEmpty {
            upstream.httpBody = body
        }
        return upstream
    }
}

/// Redirects go back to the web view so its address bar and cookies stay consistent.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    static let shared = NoRedirects()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

/// Adapts URLSession's byte stream to FlyingFox's buffered body sequence.
/// `@unchecked Sendable`: the server iterates each response body exactly once, from one task.
struct StreamedBytes: AsyncBufferedSequence, @unchecked Sendable {
    typealias Element = UInt8

    private let bytes: URLSession.AsyncBytes

    init(_ bytes: URLSession.AsyncBytes) {
        self.bytes = bytes
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(base: bytes.makeAsyncIterator())
    }

    struct Iterator: AsyncBufferedIteratorProtocol {
        var base: URLSession.AsyncBytes.AsyncIterator

        mutating func next() async throws -> UInt8? {
            try await base.next()
        }

        mutating func nextBuffer(suggested count: Int) async throws -> [UInt8]? {
            var buffer: [UInt8] = []
            buffer.reserveCapacity(count)
            while buffer.count < count, let byte = try await base.next() {
                buffer.append(byte)
            }
            return buffer.isEmpty ? nil : buffer
        }
    }
}
