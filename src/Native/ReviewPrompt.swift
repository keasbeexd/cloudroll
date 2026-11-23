import Foundation

/// When to ask for an App Store rating with the system prompt (StoreKit's requestReview).
/// iOS decides whether the prompt actually appears and shows it at most three times a year;
/// Cloudroll only picks a good moment: after real use, once per app version, never in the
/// same session as the tip ask. Nothing is sent anywhere; the counts stay in UserDefaults.
/// See docs/decisions/0010-review-prompt.md.
enum ReviewPrompt {
    /// The App Store page's "Write a Review" sheet, for the row in Settings.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6834525872?action=write-review")!

    private static let firstUseKey = "review.firstUse"
    private static let sessionsKey = "review.sessions"
    private static let askedVersionKey = "review.askedVersion"

    static let minimumDays: Double = 7
    static let minimumSessions = 5

    /// Called each time a signed-in timeline comes to the front.
    static func recordSession(defaults: UserDefaults = .standard, now: Date = .now) {
        if defaults.object(forKey: firstUseKey) == nil {
            defaults.set(now, forKey: firstUseKey)
        }
        defaults.set(defaults.integer(forKey: sessionsKey) + 1, forKey: sessionsKey)
    }

    static func shouldAsk(defaults: UserDefaults = .standard, now: Date = .now, version: String? = appVersion) -> Bool {
        guard let version, defaults.string(forKey: askedVersionKey) != version,
              defaults.integer(forKey: sessionsKey) >= minimumSessions,
              let firstUse = defaults.object(forKey: firstUseKey) as? Date
        else { return false }
        return now.timeIntervalSince(firstUse) >= minimumDays * 24 * 60 * 60
    }

    static func markAsked(defaults: UserDefaults = .standard, version: String? = appVersion) {
        defaults.set(version, forKey: askedVersionKey)
    }

    static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
