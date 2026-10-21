import Foundation
import Observation

/// Recent page and local-server problems, kept in memory only, for the user to share
/// when reporting a bug (long press on the tab bar). Entries carry paths, never query
/// strings or credentials.
@MainActor
@Observable
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()
    private static let capacity = 300

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let source: String
        let message: String
    }

    private(set) var entries: [Entry] = []

    func add(_ source: String, _ message: String) {
        entries.append(Entry(date: .now, source: source, message: message))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    /// Callable from the local server's threads.
    nonisolated static func record(_ source: String, _ message: String) {
        Task { @MainActor in shared.add(source, message) }
    }

    func report(appVersion: String, source: MemoriesSource?) -> String {
        let mode = switch source {
        case .shell: "shell"
        case .direct: "direct"
        case nil: "loading"
        }
        let formatter = ISO8601DateFormatter()
        let lines = entries.map { "\(formatter.string(from: $0.date)) [\($0.source)] \($0.message)" }
        return (["Cloudroll \(appVersion), mode: \(mode), \(entries.count) entries"] + lines).joined(separator: "\n")
    }
}
