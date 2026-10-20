import Foundation

enum MemoriesURL {
    /// Builds the Memories entry point from a user-entered server address.
    /// Only https is accepted; `/index.php/` works with and without pretty URLs.
    static func make(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty
        else { return nil }

        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path + "/index.php/apps/memories/"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
