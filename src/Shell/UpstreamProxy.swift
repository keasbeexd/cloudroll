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

    /// Downloads straight to a file (videos can be large) named after the server's
    /// Content-Disposition, inside `folder`.
    func download(target: String, into folder: URL) async throws -> URL {
        guard let url = URL(string: target, relativeTo: origin)?.absoluteURL,
              url.scheme == origin.scheme, url.host == origin.host, url.port == origin.port
        else { throw ProxyError(reason: "refused target \(target)") }
        var request = URLRequest(url: url)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (temporary, response) = try await session.download(for: request)
        try HTTP.require(200, response, context: "Downloading")
        let destination = Self.uniqueDestination(in: folder, for: response.suggestedFilename)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    /// Several files may share a name (e.g. IMG_0001.JPG in two folders), so later ones get a number.
    static func uniqueDestination(in folder: URL, for suggested: String?) -> URL {
        let name = safeFilename(suggested)
        var destination = folder.appending(path: name)
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            counter += 1
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            destination = folder.appending(path: ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
        }
        return destination
    }

    /// Uploads a file to the user's Nextcloud files, creating missing folders and never
    /// overwriting: if the name is taken, " 2", " 3", … is added. Returns the new file ID.
    func upload(file: URL, to path: String, user: String, webRoot: String, mtime: Int, contentType: String) async throws -> Int {
        let segments = try Self.validatedSegments(path)
        let root = "\(webRoot)/remote.php/dav/files/\(Self.encode(user))"
        var folder = root
        for segment in segments.dropLast() {
            folder += "/" + Self.encode(segment)
            let status = try await send("MKCOL", folder)
            guard [201, 405].contains(status) else {
                throw ProxyError(reason: "creating the folder \(segment) returned HTTP \(status)")
            }
        }

        let name = segments[segments.count - 1]
        var candidate = name
        var counter = 1
        while try await send("PROPFIND", folder + "/" + Self.encode(candidate), headers: ["Depth": "0"]) == 207 {
            counter += 1
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
        }

        var request = try upstream(folder + "/" + Self.encode(candidate), method: "PUT")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(mtime), forHTTPHeaderField: "X-OC-MTime")
        let (_, response) = try await session.upload(for: request, fromFile: file)
        let status = HTTP.status(of: response)
        guard [201, 204].contains(status) else {
            throw ProxyError(reason: "uploading \(candidate) returned HTTP \(status)")
        }
        // OC-FileId is the numeric ID followed by the instance ID, e.g. "00000123ocabc".
        let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "OC-FileId") ?? ""
        guard let fileID = Int(header.prefix(while: \.isNumber)), fileID > 0 else {
            throw ProxyError(reason: "the server didn't return a file ID for \(candidate)")
        }
        return fileID
    }

    /// The destination Memories asks for must stay inside the user's files.
    static func validatedSegments(_ path: String) throws -> [String] {
        let segments = path.split(separator: "/").map(String.init)
        let isClean = path.hasPrefix("/") && !segments.isEmpty && segments.allSatisfy { segment in
            segment != "." && segment != ".." && !segment.unicodeScalars.contains { $0.value < 0x20 || $0 == "\\" }
        }
        guard isClean else { throw ProxyError(reason: "refused upload path \(path)") }
        return segments
    }

    private static func encode(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? segment
    }

    private func upstream(_ path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: origin)?.absoluteURL else {
            throw ProxyError(reason: "invalid path \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ method: String, _ path: String, headers: [String: String] = [:]) async throws -> Int {
        var request = try upstream(path, method: method)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (_, response) = try await session.data(for: request)
        return HTTP.status(of: response)
    }

    /// Server-provided names become file names, so path separators and leading dots go.
    static func safeFilename(_ suggested: String?) -> String {
        let cleaned = (suggested ?? "")
            .components(separatedBy: CharacterSet(charactersIn: "/\\:\0"))
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        return cleaned.isEmpty ? "download" : cleaned
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
