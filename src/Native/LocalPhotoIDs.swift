import CryptoKit
import Foundation

/// Identifiers Memories uses to place phone photos on the timeline and to match them
/// with their uploaded copies. They must equal what the server computes:
/// - day: `floor(local time as UTC / 86400)` (lib/Db/TimelineWrite.php)
/// - AUID: `md5("<epoch><size>")` (src/services/utils/photo.ts `applyAuids`)
/// - BUID: `md5("<basename>size=<size>")` (lib/Exif.php `getBUID`, without ImageUniqueID)
enum LocalPhotoIDs {
    static func dayID(for date: Date, in timeZone: TimeZone = .current) -> Int {
        let local = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        return Int((local / 86400).rounded(.down))
    }

    static func epoch(for date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }

    static func auid(epoch: Int, size: Int64) -> String {
        md5Hex("\(epoch)\(size)")
    }

    static func buid(basename: String, size: Int64) -> String {
        md5Hex("\(basename)size=\(size)")
    }

    /// A numeric file ID for Memories (it must fit a JavaScript number), from the first
    /// 48 bits of the PhotoKit identifier's UUID ("XXXXXXXX-XXXX-…/L0/001").
    static func fileID(forLocalIdentifier identifier: String) -> Int? {
        let hex = identifier.prefix(while: { $0 != "/" }).filter(\.isHexDigit)
        guard hex.count >= 12 else { return nil }
        return Int(hex.prefix(12), radix: 16)
    }

    static func md5Hex(_ string: String) -> String {
        Insecure.MD5.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
