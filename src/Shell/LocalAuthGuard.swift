import Foundation

/// Any app on the device can connect to 127.0.0.1, so every request to the local
/// server must carry a per-launch secret cookie that only our web view knows.
struct LocalAuthGuard: Sendable {
    static let cookieName = "cloudroll_local"

    let secret: String

    init(secret: String = LocalAuthGuard.randomSecret()) {
        self.secret = secret
    }

    /// 32 bytes from the system CSPRNG, hex-encoded.
    static func randomSecret() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
    }

    /// `cookieHeader` is every Cookie header value joined with "; ".
    func isAuthorized(cookieHeader: String) -> Bool {
        for pair in cookieHeader.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == Self.cookieName else { continue }
            return Self.constantTimeEquals(Array(parts[1].utf8), Array(secret.utf8))
        }
        return false
    }

    private static func constantTimeEquals(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
