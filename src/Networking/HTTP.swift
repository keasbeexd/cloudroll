import Foundation

struct HTTPStatusError: LocalizedError {
    let context: String
    let status: Int

    var errorDescription: String? {
        "\(context) failed: the server answered with HTTP \(status)."
    }
}

enum HTTP {
    /// Identifies the app in Nextcloud's "Devices & sessions" list.
    static let userAgent = "Cloudroll (iOS)"

    static func status(of response: URLResponse) -> Int {
        (response as? HTTPURLResponse)?.statusCode ?? -1
    }

    static func require(_ expected: Int, _ response: URLResponse, context: String) throws {
        let status = status(of: response)
        guard status == expected else { throw HTTPStatusError(context: context, status: status) }
    }
}
