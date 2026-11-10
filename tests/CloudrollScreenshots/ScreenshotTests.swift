import XCTest

/// Captures the App Store screenshots against the App Review demo account.
/// Run by .github/workflows/screenshots.yml, which passes the account in through
/// TEST_RUNNER_ variables and builds the app with the SCREENSHOTS flag.
/// Each step saves a PNG and the accessibility tree, and a missing element skips that
/// shot instead of failing the run, so one run shows everything that went wrong.
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

    func testCaptureScreenshots() throws {
        app.launch()
        allowPhotoAccessIfAsked()

        guard app.buttons["Cloudroll Settings"].waitForExistence(timeout: 180) else {
            save("00-not-loaded")
            XCTFail("The timeline never loaded")
            return
        }
        allowPhotoAccessIfAsked()
        pause(10) // thumbnails
        save("01-timeline")

        // A server photo with a location, so the info panel shows the map.
        if openPhoto(named: "IMG_1006") {
            pause(4)
            save("02-viewer")
            if tap(app.buttons["Info"], "Info") {
                pause(4)
                save("03-info")
                app.swipeDown(velocity: .fast)
                pause(1)
            }
            closeViewer()
        }

        if openPhoto(named: "IMG_2074") {
            pause(5)
            save("04-live-photo")
            closeViewer()
        }

        // Phone photos open Cloudroll's own editor.
        if openPhoto(named: nil) {
            pause(3)
            save("05-phone-photo")
            if tap(app.buttons["Edit"], "Edit") {
                pause(4)
                save("06-editor")
                let cancel = app.buttons["Cancel"]
                if cancel.exists { cancel.tap() }
                pause(2)
            }
            closeViewer()
        }

        if tap(app.buttons["Cloudroll Settings"], "Cloudroll Settings") {
            pause(3)
            save("07-settings")
        }

        try problems.joined(separator: "\n").write(to: outputDir.appending(path: "problems.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: - Steps

    /// Opens a timeline photo whose web element label contains `name`, or the first one.
    private func openPhoto(named name: String?) -> Bool {
        let images = app.webViews.firstMatch.images
        let match: XCUIElement
        if let name {
            match = images.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
        } else {
            match = images.firstMatch
        }
        guard match.waitForExistence(timeout: 10), match.isHittable else {
            problems.append("No hittable photo for \(name ?? "first photo")")
            save("missing-\(name ?? "first")")
            return false
        }
        match.tap()
        return app.buttons["Info"].waitForExistence(timeout: 15)
    }

    private func closeViewer() {
        let close = app.buttons["Close"]
        if close.exists { close.tap() }
        pause(2)
    }

    private func allowPhotoAccessIfAsked() {
        let ownPrompt = app.buttons["Allow access"]
        if ownPrompt.waitForExistence(timeout: 5) { ownPrompt.tap() }
        for label in ["Allow Full Access", "Allow Access to All Photos", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                break
            }
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
