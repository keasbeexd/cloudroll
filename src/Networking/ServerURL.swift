import Foundation

enum ServerURL {
    /// Normalizes a user-entered address to an https server root without a trailing slash.
    static func root(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty
        else { return nil }

        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// `/index.php/` works with and without pretty URLs enabled on the server.
    static func memories(root: URL) -> URL {
        root.appending(path: "index.php/apps/memories/")
    }
}
