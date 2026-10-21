import Foundation

enum NextcloudAPI {
    static func describeMemories(server: URL) async throws -> MemoriesInfo {
        var request = URLRequest(url: ServerURL.memoriesDescribe(root: server))
        request.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if HTTP.status(of: response) == 404 { throw MemoriesError.notInstalled }
        try HTTP.require(200, response, context: "Checking Memories")
        return try JSONDecoder().decode(MemoriesInfo.self, from: data)
    }

    /// Deletes the app password on the server so it no longer appears under "Devices & sessions".
    static func revokeAppPassword(_ credential: Credential) async throws {
        var request = URLRequest(url: credential.server.appending(path: "ocs/v2.php/core/apppassword"))
        request.httpMethod = "DELETE"
        request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")

        let (_, response) = try await URLSession.shared.data(for: request)
        try HTTP.require(200, response, context: "Revoking the app password")
    }
}
