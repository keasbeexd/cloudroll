import XCTest
@testable import Cloudroll

final class ReviewPromptTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "ReviewPromptTests"
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func sessions(_ count: Int, at date: Date) {
        for _ in 0..<count {
            ReviewPrompt.recordSession(defaults: defaults, now: date)
        }
    }

    func testWaitsForEnoughSessionsAndDays() {
        sessions(ReviewPrompt.minimumSessions - 1, at: start)
        let later = start.addingTimeInterval(30 * 24 * 60 * 60)
        XCTAssertFalse(ReviewPrompt.shouldAsk(defaults: defaults, now: later, version: "1.1"))

        sessions(1, at: later)
        XCTAssertTrue(ReviewPrompt.shouldAsk(defaults: defaults, now: later, version: "1.1"))
    }

    func testWaitsAWeekAfterFirstUse() {
        sessions(ReviewPrompt.minimumSessions, at: start)
        XCTAssertFalse(ReviewPrompt.shouldAsk(defaults: defaults, now: start.addingTimeInterval(6 * 24 * 60 * 60), version: "1.1"))
        XCTAssertTrue(ReviewPrompt.shouldAsk(defaults: defaults, now: start.addingTimeInterval(7 * 24 * 60 * 60), version: "1.1"))
    }

    func testAsksOncePerVersion() {
        sessions(ReviewPrompt.minimumSessions, at: start)
        let later = start.addingTimeInterval(8 * 24 * 60 * 60)
        ReviewPrompt.markAsked(defaults: defaults, version: "1.1")
        XCTAssertFalse(ReviewPrompt.shouldAsk(defaults: defaults, now: later, version: "1.1"))
        XCTAssertTrue(ReviewPrompt.shouldAsk(defaults: defaults, now: later, version: "1.2"))
    }

    func testNeverAsksWithoutAVersion() {
        sessions(ReviewPrompt.minimumSessions, at: start)
        XCTAssertFalse(ReviewPrompt.shouldAsk(defaults: defaults, now: start.addingTimeInterval(8 * 24 * 60 * 60), version: nil))
    }
}
