import Foundation

enum NextcloudAPI {
    /// Authenticated so the response includes the user id; `manifest=1` asks Memories 9+
    /// for the signed asset manifest (older versions ignore it).
    static func describeMemories(_ credential: Credential) async throws -> MemoriesInfo {
        var components = URLComponents(url: ServerURL.memoriesDescribe(root: credential.server), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "manifest", value: "1")]
        guard let url = components?.url else {
            throw ProxyError(reason: "invalid server address \(credential.server)")
        }
        var request = URLRequest(url: url)
        request.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if HTTP.status(of: response) == 404 { throw MemoriesError.notInstalled }
        try HTTP.require(200, response, context: "Checking Memories")
        return try JSONDecoder().decode(MemoriesInfo.self, from: data)
    }

    /// Reads the folder Memories' scripts are served from out of the server's Memories page.
    static func memoriesScriptBase(_ credential: Credential, page: URL) async throws -> URL {
        var request = URLRequest(url: page)
        request.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.require(200, response, context: "Loading the Memories page")
        guard let base = MemoriesScripts.base(inPage: String(decoding: data, as: UTF8.self), server: credential.server) else {
            throw MemoriesError.scriptsNotFound
        }
        return base
    }

    /// The user's display name, for the account list. Nil if the server doesn't say.
    static func displayName(_ credential: Credential) async throws -> String? {
        struct Response: Decodable {
            struct OCS: Decodable {
                struct User: Decodable { let displayname: String? }
                let data: User
            }
            let ocs: OCS
        }
        var request = URLRequest(url: credential.server.appending(path: "ocs/v2.php/cloud/user"))
        request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.require(200, response, context: "Reading the account name")
        let name = try JSONDecoder().decode(Response.self, from: data).ocs.data.displayname
        return name?.isEmpty == false ? name : nil
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
