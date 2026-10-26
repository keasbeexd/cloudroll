import Foundation
import UIKit

/// Loads images from the local shell for native views, presenting its access cookie.
actor ShellImageLoader {
    static let shared = ShellImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let session = URLSession(configuration: .ephemeral)
    /// Loads in progress, so a prefetch and the viewer asking for the same photo share one.
    private var loading: [URL: Task<UIImage, Error>] = [:]

    init() {
        cache.countLimit = 40
        // Decoded full-size photos are large (a 12 MP photo is ~48 MB), so cap by bytes too.
        cache.totalCostLimit = 300 * 1024 * 1024
    }

    func image(at url: URL, cookie: String) async throws -> UIImage {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let task = loading[url] { return try await task.value }
        let session = session
        let task = Task<UIImage, Error> {
            var request = URLRequest(url: url)
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            let (data, response) = try await session.data(for: request)
            try HTTP.require(200, response, context: "Loading the photo")
            guard let decoded = UIImage(data: data) else {
                throw PhotoLibraryError(reason: "The photo couldn't be decoded.")
            }
            // Decode off the main thread so swiping stays smooth.
            return await decoded.byPreparingForDisplay() ?? decoded
        }
        loading[url] = task
        defer { loading[url] = nil }
        let image = try await task.value
        cache.setObject(image, forKey: url as NSURL, cost: Self.cost(of: image))
        return image
    }

    /// Loads the neighbouring photos' previews first, then their full images, ignoring failures.
    func prefetch(_ media: [ViewerMedia], cookie: String) async {
        for url in media.map(\.preview) + media.map(\.full) {
            guard !Task.isCancelled else { return }
            _ = try? await image(at: url, cookie: cookie)
        }
    }

    private static func cost(of image: UIImage) -> Int {
        let scale = image.scale
        return Int(image.size.width * scale * image.size.height * scale * 4)
    }
}
