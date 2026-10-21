import CryptoKit
import Foundation

struct AssetIntegrityError: LocalizedError {
    let name: String
    let reason: String

    var errorDescription: String? {
        "Downloaded Memories file \(name) failed verification: \(reason)."
    }
}

/// Downloads the verified Memories web assets into a snapshot directory per manifest.
/// A snapshot is only used once every file in it has matched its signed hash.
struct AssetStore {
    private static let completeMarker = ".complete"
    private static let maxConcurrentDownloads = 4

    let root: URL

    static func appDefault() throws -> AssetStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return AssetStore(root: support.appending(path: "web-assets", directoryHint: .isDirectory))
    }

    /// Snapshots are keyed by the hash of the asset list, so a Memories update gets a new one.
    static func snapshotID(for assets: [WebAsset]) -> String {
        let listing = assets.map { "\($0.name) \($0.sha256)" }.joined(separator: "\n")
        return SHA256.hash(data: Data(listing.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the directory holding every asset, downloading the snapshot if needed.
    func snapshot(for assets: [WebAsset], scriptBase: URL) async throws -> URL {
        let id = Self.snapshotID(for: assets)
        let final = root.appending(path: id, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: final.appending(path: Self.completeMarker).path) {
            return final
        }

        let staging = root.appending(path: "\(id).partial", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        try await download(assets, from: scriptBase, into: staging)
        try Data().write(to: staging.appending(path: Self.completeMarker))
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: staging, to: final)
        try removeSnapshots(except: id)
        return final
    }

    private func download(_ assets: [WebAsset], from scriptBase: URL, into directory: URL) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            var pending = assets[...]
            for _ in 0..<Self.maxConcurrentDownloads {
                guard let asset = pending.popFirst() else { break }
                group.addTask { try await Self.fetch(asset, from: scriptBase, into: directory) }
            }
            for try await _ in group {
                guard let asset = pending.popFirst() else { continue }
                group.addTask { try await Self.fetch(asset, from: scriptBase, into: directory) }
            }
        }
    }

    /// Fetched by name from the folder the server really uses; the signed hash, not the
    /// location, is what makes the file trustworthy.
    private static func fetch(_ asset: WebAsset, from scriptBase: URL, into directory: URL) async throws {
        var request = URLRequest(url: scriptBase.appending(path: asset.name))
        request.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.require(200, response, context: "Downloading \(asset.name)")

        guard data.count == asset.length else {
            throw AssetIntegrityError(name: asset.name, reason: "expected \(asset.length) bytes, got \(data.count)")
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == asset.sha256 else {
            throw AssetIntegrityError(name: asset.name, reason: "SHA-256 mismatch")
        }
        try data.write(to: directory.appending(path: asset.name), options: .atomic)
    }

    private func removeSnapshots(except id: String) throws {
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for entry in entries where entry.lastPathComponent != id {
            try FileManager.default.removeItem(at: entry)
        }
    }
}
