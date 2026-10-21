import CryptoKit
import XCTest
@testable import Cloudroll

final class SignedManifestTests: XCTestCase {
    /// Real manifest from Memories 10.1.0 (App Store release), signed with the release key.
    private func releaseEnvelope() throws -> SignedManifest.Envelope {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "describe-memories-10.1.0", withExtension: "json"))
        struct Describe: Decodable { let jsManifest: SignedManifest.Envelope }
        return try JSONDecoder().decode(Describe.self, from: Data(contentsOf: url)).jsManifest
    }

    private func signed(_ payload: String, with key: Curve25519.Signing.PrivateKey) throws -> SignedManifest.Envelope {
        let data = Data(payload.utf8)
        let signature = try key.signature(for: SignedManifest.preAuthEncoding(data))
        return SignedManifest.Envelope(
            payload: data.base64EncodedString(),
            payloadType: SignedManifest.payloadType,
            signatures: [.init(sig: signature.base64EncodedString())]
        )
    }

    private func payload(name: String = "main.js", href: String = "/apps/memories/js/main.js", expires: String = "2099-01-01T00:00:00Z") -> String {
        """
        {"expires":"\(expires)","targets":{"\(name)":{"length":3,"hashes":{"sha256":"\(String(repeating: "a", count: 64))"},"custom":{"href":"\(href)"}}}}
        """
    }

    func testReleaseManifestVerifiesWithReleaseKey() throws {
        let assets = try SignedManifest.verify(releaseEnvelope(), trustedKeys: [SignedManifest.releaseKey])

        XCTAssertEqual(assets.count, 78)
        let admin = try XCTUnwrap(assets.first { $0.name == "memories-admin.js" })
        XCTAssertEqual(admin.sha256, "9f307cf4f17a8eb11f5a44eac09bc2a2b2901b1fa3624e740574d800186f65f2")
        XCTAssertEqual(admin.length, 643_228)
        XCTAssertTrue(admin.href.hasPrefix("/apps/memories/js/memories-admin.js"))
    }

    func testReleaseManifestRejectedByDevelopmentKey() throws {
        XCTAssertThrowsError(try SignedManifest.verify(releaseEnvelope(), trustedKeys: [SignedManifest.developmentKey])) {
            XCTAssertEqual($0 as? ManifestError, .signatureMismatch)
        }
    }

    func testTamperedPayloadIsRejected() throws {
        var envelope = try releaseEnvelope()
        var payload = try XCTUnwrap(Data(base64Encoded: envelope.payload))
        payload[payload.count / 2] ^= 0x01
        envelope = .init(payload: payload.base64EncodedString(), payloadType: envelope.payloadType, signatures: envelope.signatures)

        XCTAssertThrowsError(try SignedManifest.verify(envelope, trustedKeys: [SignedManifest.releaseKey])) {
            XCTAssertEqual($0 as? ManifestError, .signatureMismatch)
        }
    }

    func testExpiredManifestIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try signed(payload(expires: "2020-01-01T00:00:00Z"), with: key)

        XCTAssertThrowsError(try SignedManifest.verify(envelope, trustedKeys: [key.publicKey.rawRepresentation])) {
            XCTAssertEqual($0 as? ManifestError, .expired("2020-01-01T00:00:00Z"))
        }
    }

    func testPathTraversalNameIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try signed(payload(name: "../evil.js"), with: key)

        XCTAssertThrowsError(try SignedManifest.verify(envelope, trustedKeys: [key.publicKey.rawRepresentation])) {
            XCTAssertEqual($0 as? ManifestError, .unsafeTarget("../evil.js"))
        }
    }

    func testOtherHostHrefIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try signed(payload(href: "//evil.example/main.js"), with: key)

        XCTAssertThrowsError(try SignedManifest.verify(envelope, trustedKeys: [key.publicKey.rawRepresentation])) {
            XCTAssertEqual($0 as? ManifestError, .unsafeTarget("main.js"))
        }
    }

    func testWrongPayloadTypeIsRejected() throws {
        let envelope = try releaseEnvelope()
        let wrongType = SignedManifest.Envelope(payload: envelope.payload, payloadType: "text/plain", signatures: envelope.signatures)

        XCTAssertThrowsError(try SignedManifest.verify(wrongType, trustedKeys: [SignedManifest.releaseKey])) {
            XCTAssertEqual($0 as? ManifestError, .unexpectedPayloadType("text/plain"))
        }
    }

    func testSnapshotIDChangesWithAssets() {
        let a = WebAsset(name: "a.js", href: "/a.js", sha256: String(repeating: "a", count: 64), length: 1)
        let b = WebAsset(name: "a.js", href: "/a.js", sha256: String(repeating: "b", count: 64), length: 1)

        XCTAssertEqual(AssetStore.snapshotID(for: [a]), AssetStore.snapshotID(for: [a]))
        XCTAssertNotEqual(AssetStore.snapshotID(for: [a]), AssetStore.snapshotID(for: [b]))
    }
}
