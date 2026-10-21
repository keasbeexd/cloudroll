import Foundation

enum LoginError: LocalizedError {
    case insecureURL(String)
    case browserUnavailable

    var errorDescription: String? {
        switch self {
        case .insecureURL(let what):
            "The server returned a non-https \(what), so sign-in was stopped."
        case .browserUnavailable:
            "Couldn't open the sign-in page."
        }
    }
}

/// Nextcloud Login Flow v2: https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html
struct LoginFlow {
    struct Start: Decodable {
        struct Poll: Decodable {
            let token: String
            let endpoint: URL
        }

        let poll: Poll
        let login: URL
    }

    private struct PollResult: Decodable {
        let server: String
        let loginName: String
        let appPassword: String
    }

    func start(server: URL) async throws -> Start {
        var request = URLRequest(url: server.appending(path: "index.php/login/v2"))
        request.httpMethod = "POST"
        request.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.require(200, response, context: "Starting sign-in")
        let start = try JSONDecoder().decode(Start.self, from: data)
        try Self.requireHTTPS(start.login, "sign-in page")
        try Self.requireHTTPS(start.poll.endpoint, "sign-in endpoint")
        return start
    }

    /// Polls until the user approves in the browser. Nextcloud answers 404 until then;
    /// cancelling the task stops polling.
    func waitForCredential(_ poll: Start.Poll) async throws -> Credential {
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "token", value: poll.token)]
        var request = URLRequest(url: poll.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)

        while true {
            try await Task.sleep(for: .seconds(2))
            let (data, response) = try await URLSession.shared.data(for: request)
            if HTTP.status(of: response) == 404 { continue }
            try HTTP.require(200, response, context: "Finishing sign-in")

            let result = try JSONDecoder().decode(PollResult.self, from: data)
            guard let server = ServerURL.root(from: result.server) else {
                throw LoginError.insecureURL("server address")
            }
            return Credential(server: server, loginName: result.loginName, appPassword: result.appPassword)
        }
    }

    private static func requireHTTPS(_ url: URL, _ what: String) throws {
        guard url.scheme?.lowercased() == "https" else { throw LoginError.insecureURL(what) }
    }
}
