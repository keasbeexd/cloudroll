import CryptoKit
import Foundation

/// A Memories web asset listed in the signed manifest.
struct WebAsset: Equatable {
    /// File name, safe to use as a path component.
    let name: String
    /// Server-relative URL, e.g. `/apps/memories/js/memories-main.js?v=…`.
    let href: String
    let sha256: String
    let length: Int
}

enum ManifestError: LocalizedError, Equatable {
    case unexpectedPayloadType(String)
    case signatureCount(Int)
    case invalidEncoding(String)
    case signatureMismatch
    case expired(String)
    case unsafeTarget(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedPayloadType(let type):
            "Memories asset manifest has unexpected payload type \(type)."
        case .signatureCount(let count):
            "Memories asset manifest must have exactly one signature, found \(count)."
        case .invalidEncoding(let what):
            "Memories asset manifest has an invalid \(what)."
        case .signatureMismatch:
            "Memories asset manifest signature doesn't match a trusted key."
        case .expired(let date):
            "Memories asset manifest expired on \(date)."
        case .unsafeTarget(let name):
            "Memories asset manifest lists an unsafe file: \(name)."
        }
    }
}

/// Verifies the asset manifest that Memories 9+ serves from `api/describe?manifest=1`:
/// a DSSE envelope (https://github.com/secure-systems-lab/dsse) whose payload is TUF
/// targets metadata. Nothing from the manifest is trusted before this succeeds.
enum SignedManifest {
    static let payloadType = "application/vnd.tuf+json"

    /// Ed25519 key that signs official Memories releases.
    static let releaseKey = Data(base64Encoded: "aA2fpqrrJHTiCkE9ecQNDR5V1qO7oHppjdJQ7Pj5nhQ=")!
    /// Key Memories signs unofficial and development builds with.
    static let developmentKey = Data(base64Encoded: "MIJxGvOr0LMg9Isyfi5S4cHQsP+v4mFzrsmY2AYKOjs=")!

    static var trustedKeys: [Data] {
        #if DEBUG
        [releaseKey, developmentKey]
        #else
        [releaseKey]
        #endif
    }

    struct Envelope: Decodable {
        struct Signature: Decodable {
            let sig: String
        }

        let payload: String
        let payloadType: String
        let signatures: [Signature]
    }

    private struct Targets: Decodable {
        struct Target: Decodable {
            struct Hashes: Decodable { let sha256: String }
            struct Custom: Decodable { let href: String }

            let length: Int
            let hashes: Hashes
            let custom: Custom
        }

        let expires: String
        let targets: [String: Target]
    }

    /// Returns the verified assets sorted by name.
    static func verify(_ envelope: Envelope, trustedKeys: [Data] = trustedKeys, now: Date = .now) throws -> [WebAsset] {
        guard envelope.payloadType == payloadType else {
            throw ManifestError.unexpectedPayloadType(envelope.payloadType)
        }
        guard envelope.signatures.count == 1 else {
            throw ManifestError.signatureCount(envelope.signatures.count)
        }
        guard let payload = Data(base64Encoded: envelope.payload) else {
            throw ManifestError.invalidEncoding("payload")
        }
        guard let signature = Data(base64Encoded: envelope.signatures[0].sig), signature.count == 64 else {
            throw ManifestError.invalidEncoding("signature")
        }

        let message = preAuthEncoding(payload)
        let isTrusted = try trustedKeys.contains { key in
            try Curve25519.Signing.PublicKey(rawRepresentation: key).isValidSignature(signature, for: message)
        }
        guard isTrusted else { throw ManifestError.signatureMismatch }

        let targets: Targets
        do {
            targets = try JSONDecoder().decode(Targets.self, from: payload)
        } catch {
            throw ManifestError.invalidEncoding("targets payload (\(error.localizedDescription))")
        }
        guard let expiry = ISO8601DateFormatter().date(from: targets.expires) else {
            throw ManifestError.invalidEncoding("expiry date \(targets.expires)")
        }
        guard now < expiry else { throw ManifestError.expired(targets.expires) }

        return try targets.targets
            .map { name, target in try asset(name: name, target: target) }
            .sorted { $0.name < $1.name }
    }

    /// DSSE pre-authentication encoding: "DSSEv1 <len(type)> <type> <len(payload)> <payload>".
    static func preAuthEncoding(_ payload: Data) -> Data {
        let type = Data(payloadType.utf8)
        var message = Data("DSSEv1 \(type.count) ".utf8)
        message.append(type)
        message.append(Data(" \(payload.count) ".utf8))
        message.append(payload)
        return message
    }

    /// Names become file names on disk and hrefs are fetched from the user's server,
    /// so both are restricted even though the manifest is signed.
    private static func asset(name: String, target: Targets.Target) throws -> WebAsset {
        let isSafeName = !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\\")
        let isServerRelative = target.custom.href.hasPrefix("/") && !target.custom.href.hasPrefix("//")
        let hash = target.hashes.sha256.lowercased()
        let isHexHash = hash.count == 64 && hash.allSatisfy(\.isHexDigit)
        guard isSafeName, isServerRelative, isHexHash, target.length >= 0 else {
            throw ManifestError.unsafeTarget(name)
        }
        return WebAsset(name: name, href: target.custom.href, sha256: hash, length: target.length)
    }
}
