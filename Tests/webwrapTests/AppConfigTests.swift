import XCTest
import Foundation
@testable import webwrap

// Tests for AppConfig: parsing an existing app's Info.plist and the override-merge
// logic used by `webwrap update`. Pure — no filesystem.

final class AppConfigParseTests: XCTestCase {
    private func plist(_ pairs: [String: String]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: pairs, format: .xml, options: 0)
    }

    func testParsesFullConfig() {
        let data = plist([
            "WebWrapURL": "https://outlook.office.com",
            "CFBundleName": "Outlook",
            "CFBundleIdentifier": "dk.yepz.webwrap.outlook",
            "WebWrapWidth": "1000",
            "WebWrapHeight": "700",
        ])
        XCTAssertEqual(AppConfig.parse(plistData: data),
                       AppConfig(url: "https://outlook.office.com", name: "Outlook",
                                 bundleId: "dk.yepz.webwrap.outlook", width: 1000, height: 700))
    }

    func testNilForNonWebwrapPlist() {
        // No WebWrapURL marker → not a webwrap app.
        XCTAssertNil(AppConfig.parse(plistData: plist(["CFBundleName": "Safari"])))
    }

    func testNilForMalformed() {
        XCTAssertNil(AppConfig.parse(plistData: Data("not a plist".utf8)))
    }

    func testDefaultsWhenDimensionsMissing() {
        let cfg = AppConfig.parse(plistData: plist(["WebWrapURL": "https://x.test"]))
        XCTAssertEqual(cfg?.width, 1200)
        XCTAssertEqual(cfg?.height, 800)
    }
}

final class AppConfigApplyTests: XCTestCase {
    private let base = AppConfig(url: "https://old.test", name: "Old",
                                 bundleId: "dk.yepz.webwrap.old", width: 1200, height: 800)

    func testNoOverridesCarriesEverything() {
        XCTAssertEqual(base.applying(), base)
    }

    func testOverridesOnlyGivenFields() {
        let updated = base.applying(url: "https://new.test", height: 900)
        XCTAssertEqual(updated.url, "https://new.test")
        XCTAssertEqual(updated.height, 900)
        // Carried over:
        XCTAssertEqual(updated.name, "Old")
        XCTAssertEqual(updated.width, 1200)
    }

    func testBundleIdNeverChanges() {
        // Even when the name changes, the bundle id must stay (preserves the session).
        let renamed = base.applying(name: "BrandNew")
        XCTAssertEqual(renamed.name, "BrandNew")
        XCTAssertEqual(renamed.bundleId, "dk.yepz.webwrap.old")
    }
}
