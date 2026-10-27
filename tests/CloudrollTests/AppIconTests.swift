import UIKit
import XCTest
@testable import Cloudroll

final class AppIconTests: XCTestCase {
    func testEveryIconHasAPreview() {
        for icon in AppIcon.allCases {
            XCTAssertNotNil(UIImage(named: icon.previewName), icon.previewName)
        }
    }

    /// The asset catalog compiler lists alternate icons in Info.plist only when the build
    /// setting names them, and iOS refuses names that aren't listed.
    func testEveryAlternateIsRegistered() throws {
        let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any])
        for icon in AppIcon.allCases {
            guard let name = icon.alternateName else { continue }
            XCTAssertNotNil(alternates[name], name)
        }
    }
}
