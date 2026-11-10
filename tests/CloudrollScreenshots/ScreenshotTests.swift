import XCTest

/// Captures the App Store screenshots against the App Review demo account.
/// Run by .github/workflows/screenshots.yml, which passes the account in through
/// TEST_RUNNER_ variables and builds the app with the SCREENSHOTS flag.
/// Each step saves a PNG and the accessibility tree, and a missing element skips that
/// shot instead of failing the run, so one run shows everything that went wrong.
///
/// The timeline is a web view whose thumbnails aren't in the accessibility tree, so the
/// test opens photos by their place on screen and then checks the native viewer's
/// controls, which it can read: "Play Live Photo" for the Live Photo, a map in the info.
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

        // The newest photos are the phone's, which open Cloudroll's own editor.
        if openPhoto(at: CGVector(dx: 0.3, dy: 0.3), "newest phone photo") {
            pause(3)
            save("02-viewer")
            if tap(app.buttons["Edit"], "Edit") {
                waitForLoading(timeout: 90)
                save("03-editor")
                if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
                let discard = app.buttons["Discard Changes"]
                if discard.waitForExistence(timeout: 2) { discard.tap() }
                pause(2)
            }
            closeViewer()
        }

        // The demo timeline is the same every run: the aquarium Live Photo is the only
        // photo of Aug 1, and the San Clemente railway photo (with a location) leads Jul 4.
        if openPhoto(at: CGVector(dx: 0.16, dy: 0.58), "Live Photo") {
            // The motion part downloads after the photo; the button appears once it's ready.
            if app.buttons["Play Live Photo"].waitForExistence(timeout: 45) {
                pause(2)
                save("04-live-photo")
            } else {
                problems.append("The Aug 1 photo isn't a Live Photo")
                save("dbg-live")
            }
            closeViewer()
        }

        if openPhoto(at: CGVector(dx: 0.5, dy: 0.76), "photo with a location") {
            pause(3)
            if tap(app.buttons["Info"], "Info") {
                pause(12) // map tiles
                if app.maps.firstMatch.exists {
                    save("05-info")
                } else {
                    problems.append("The Jul 4 photo's info has no map")
                    save("dbg-info")
                }
                dismissInfo()
            }
            closeViewer()
        }

        if tap(app.buttons["Cloudroll Settings"], "Cloudroll Settings") {
            pause(3)
            save("06-settings")
        } else {
            save("dbg-settings")
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

    /// Taps a thumbnail by its place on screen; the web timeline's photos aren't in the
    /// accessibility tree.
    private func openPhoto(at point: CGVector, _ what: String) -> Bool {
        app.windows.firstMatch.coordinate(withNormalizedOffset: point).tap()
        if app.buttons["Info"].waitForExistence(timeout: 10) { return true }
        problems.append("Couldn't open the \(what)")
        save("dbg-open-\(what.replacingOccurrences(of: " ", with: "-"))")
        return false
    }

    /// Waits for spinners to go, e.g. while the editor renders its first preview.
    private func waitForLoading(timeout: TimeInterval = 30) {
        let deadline = Date().addingTimeInterval(timeout)
        pause(2)
        while Date() < deadline, app.activityIndicators.firstMatch.exists { pause(1) }
        pause(2)
    }

    private func closeViewer() {
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        if !app.buttons["Cloudroll Settings"].waitForExistence(timeout: 8) {
            problems.append("The viewer didn't close")
            save("dbg-close")
        }
        pause(2)
    }

    private func dismissInfo() {
        // Drag the sheet down by its grabber, which sits near the middle of the screen
        // at the medium detent.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        pause(2)
        if !app.buttons["Close"].exists {
            problems.append("The info sheet didn't close")
            save("dbg-info-close")
        }
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
