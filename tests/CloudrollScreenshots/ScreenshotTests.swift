import XCTest

/// Captures the App Store screenshots against the App Review demo account.
/// Run by .github/workflows/screenshots.yml, which passes the account in through
/// TEST_RUNNER_ variables and builds the app with the SCREENSHOTS flag.
/// Each step saves a PNG and the accessibility tree, and a missing element skips that
/// shot instead of failing the run, so one run shows everything that went wrong.
///
/// The timeline is a web view whose thumbnails aren't in the accessibility tree, so the
/// test opens the newest photo by position and then swipes through the native viewer,
/// whose controls it can read: "Play Live Photo" marks the Live Photo, and the info
/// sheet shows a map for photos with a location.
final class ScreenshotTests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var outputDir: URL!
    private var problems: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        outputDir = URL(fileURLWithPath: env["SCREENSHOT_DIR"] ?? NSTemporaryDirectory())
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        for key in ["CLOUDROLL_DEMO_SERVER", "CLOUDROLL_DEMO_LOGIN", "CLOUDROLL_DEMO_APP_PASSWORD", "CLOUDROLL_DEMO_NAME"] {
            app.launchEnvironment[key] = env[key]
        }
    }

    override func tearDownWithError() throws {
        try problems.joined(separator: "\n").write(to: outputDir.appending(path: "problems.txt"), atomically: true, encoding: .utf8)
    }

    func testCaptureScreenshots() throws {
        app.launch()
        guard waitForTimeline() else {
            save("00-not-loaded")
            XCTFail("The timeline never loaded")
            return
        }
        allowPhotoAccess()
        pause(12) // the phone photos join the timeline, then thumbnails load
        save("01-timeline")

        guard openNewestPhoto() else { return }

        // The newest photos are the phone's, which open Cloudroll's own editor.
        if app.buttons["Edit"].exists {
            pause(3)
            save("02-phone-photo")
            app.buttons["Edit"].tap()
            pause(4)
            save("03-editor")
            let cancel = app.buttons["Cancel"]
            if cancel.waitForExistence(timeout: 5) { cancel.tap() }
            let discard = app.buttons["Discard Changes"]
            if discard.waitForExistence(timeout: 2) { discard.tap() }
            pause(2)
        } else {
            problems.append("The newest photo had no Edit button")
        }

        var gotLive = false
        var gotLocation = false
        for index in 0..<30 where !(gotLive && gotLocation) {
            if index > 0 {
                app.swipeLeft()
                pause(3)
            }
            if !gotLive, app.buttons["Play Live Photo"].exists {
                pause(2)
                save("04-live-photo")
                gotLive = true
            }
            if !gotLocation, app.buttons["Info"].exists {
                app.buttons["Info"].tap()
                pause(4)
                if app.maps.firstMatch.exists {
                    save("05-info")
                    gotLocation = true
                }
                dismissInfo()
            }
        }
        if !gotLive { problems.append("No Live Photo found in 30 photos") }
        if !gotLocation { problems.append("No photo with a location found in 30 photos") }

        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        pause(2)
        if tap(app.buttons["Cloudroll Settings"], "Cloudroll Settings") {
            pause(3)
            save("06-settings")
        }
    }

    // MARK: - Steps

    /// Taps "Retry" once if the first load times out, as it occasionally does on CI.
    private func waitForTimeline() -> Bool {
        let settings = app.buttons["Cloudroll Settings"]
        let deadline = Date().addingTimeInterval(240)
        var retried = false
        while Date() < deadline {
            if settings.exists { return true }
            if !retried, app.buttons["Retry"].exists {
                save("00-retry")
                app.buttons["Retry"].tap()
                retried = true
            }
            allowPhotoAccess(wait: 0)
            pause(2)
        }
        return false
    }

    /// Cloudroll's own prompt comes first, then the system's, a little after the timeline loads.
    private func allowPhotoAccess(wait: TimeInterval = 20) {
        let deadline = Date().addingTimeInterval(wait)
        repeat {
            if app.buttons["Allow access"].exists { app.buttons["Allow access"].tap() }
            for label in ["Allow Full Access", "Allow Access to All Photos"] where springboard.buttons[label].exists {
                springboard.buttons[label].tap()
                return
            }
            if wait > 0 { pause(1) }
        } while Date() < deadline
    }

    /// The first thumbnail sits under the header and the first day's title.
    private func openNewestPhoto() -> Bool {
        let window = app.windows.firstMatch
        for y in [0.22, 0.26, 0.30] {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: y)).tap()
            if app.buttons["Info"].waitForExistence(timeout: 8) { return true }
        }
        problems.append("Couldn't open the newest photo")
        save("missing-viewer")
        return false
    }

    private func dismissInfo() {
        let sheet = app.sheets.firstMatch
        if sheet.exists {
            sheet.swipeDown(velocity: .fast)
        } else {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        }
        pause(2)
    }

    @discardableResult
    private func tap(_ element: XCUIElement, _ what: String) -> Bool {
        guard element.waitForExistence(timeout: 10), element.isHittable else {
            problems.append("Couldn't tap \(what)")
            return false
        }
        element.tap()
        return true
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? shot.pngRepresentation.write(to: outputDir.appending(path: "\(name).png"))
        try? app.debugDescription.write(to: outputDir.appending(path: "\(name).txt"), atomically: true, encoding: .utf8)
    }
}
