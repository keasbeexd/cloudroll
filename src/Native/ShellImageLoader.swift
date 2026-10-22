import Foundation
import UIKit

/// Loads images from the local shell for native views, presenting its access cookie.
actor ShellImageLoader {
    static let shared = ShellImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let session = URLSession(configuration: .ephemeral)

    init() {
        cache.countLimit = 40
    }

    func image(at url: URL, cookie: String) async throws -> UIImage {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        try HTTP.require(200, response, context: "Loading the photo")
        guard let decoded = UIImage(data: data) else {
            throw PhotoLibraryError(reason: "The photo couldn't be decoded.")
        }
        // Decode off the main thread so swiping stays smooth.
        let image = await decoded.byPreparingForDisplay() ?? decoded
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
