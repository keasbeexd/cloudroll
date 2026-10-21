import Foundation

enum NextcloudAPI {
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
