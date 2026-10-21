import Foundation

struct Credential: Codable, Equatable {
    let server: URL
    let loginName: String
    let appPassword: String

    var authorizationHeader: String {
        "Basic " + Data("\(loginName):\(appPassword)".utf8).base64EncodedString()
    }
}
