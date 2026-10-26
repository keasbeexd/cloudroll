import Foundation

/// The details Memories loads for a photo (its `imageInfo`), as `shell-viewer.js` hands them
/// over. Phone photos get theirs from the bridge's `/api/image/info`, so the shape is the same.
struct PhotoInfo: Decodable, Equatable {
    let fileid: Int
    let basename: String
    var filename: String?
    var mimetype: String?
    var size: Double?
    var w: Double?
    var h: Double?
    /// Seconds since 1970 of the local time the photo was taken, as if that time were UTC.
    var datetaken: Double?
    /// e.g. "+02:00", when the photo recorded its time zone.
    var offset: String?
    var title: String?
    var description: String?
    var make: String?
    var model: String?
    var lens: String?
    var fNumber: Double?
    /// Seconds.
    var exposure: Double?
    var focalLength: Double?
    var iso: Double?
    var megapixels: Double?
    var latitude: Double?
    var longitude: Double?
    var address: String?
    var tags: [String] = []
    var albums: [String] = []
    var people: [String] = []

    var date: Date? {
        datetaken.map { Date(timeIntervalSince1970: $0) }
    }

    /// Long date, e.g. "12 October 2026".
    var dateText: String? {
        date?.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: Self.utc))
    }

    /// Weekday and time, with the recorded zone, e.g. "Monday 14:03 (UTC+02:00)".
    var timeText: String? {
        guard let date else { return nil }
        var style = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: Self.utc)
        style = style.weekday(.wide)
        let text = date.formatted(style)
        return offset.map { "\(text) (UTC\($0))" } ?? text
    }

    /// "Apple iPhone 15 Pro", without repeating the make when the model already has it.
    var camera: String? {
        switch (make, model) {
        case let (make?, model?):
            model.lowercased().hasPrefix(make.lowercased()) ? model : "\(make) \(model)"
        case let (nil, model?):
            model
        case let (make?, nil):
            make
        case (nil, nil):
            nil
        }
    }

    /// "f/1.8 · 1/120 s · 6.9 mm · ISO 50"
    var exposureText: String? {
        var parts: [String] = []
        if let fNumber { parts.append("f/\(Self.trimmed(fNumber))") }
        if let exposure, exposure > 0 {
            parts.append(exposure < 1 ? "1/\(Int((1 / exposure).rounded())) s" : "\(Self.trimmed(exposure)) s")
        }
        if let focalLength { parts.append("\(Self.trimmed(focalLength)) mm") }
        if let iso { parts.append("ISO \(Int(iso))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "12.2 MP · 4032 × 3024 · 3.1 MB"
    var fileText: String? {
        var parts: [String] = []
        let pixels = (w ?? 0) * (h ?? 0)
        if let mp = megapixels ?? (pixels > 0 ? pixels / 1_000_000 : nil) {
            parts.append(String(format: "%.1f MP", mp))
        }
        if let w, let h, w > 0, h > 0 { parts.append("\(Int(w)) × \(Int(h))") }
        if let size, size > 0 { parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// GPS (0, 0) is what broken cameras write, so it counts as no location.
    var hasLocation: Bool {
        guard let latitude, let longitude else { return false }
        return (latitude != 0 || longitude != 0) && abs(latitude) <= 90 && abs(longitude) <= 180
    }

    private static let utc = TimeZone(identifier: "UTC")!

    /// 1.8 -> "1.8", 50.0 -> "50", 6.86 -> "6.9".
    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}
