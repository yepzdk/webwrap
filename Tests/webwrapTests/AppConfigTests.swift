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
            "WebWrapToolbar": "1",
            "WebWrapBackgroundColor": "#1a73e8",
            "WebWrapHandleURLs": "1",
            "WebWrapOpenAnyURL": "1",
        ])
        XCTAssertEqual(AppConfig.parse(plistData: data),
                       AppConfig(url: "https://outlook.office.com", name: "Outlook",
                                 bundleId: "dk.yepz.webwrap.outlook", width: 1000, height: 700,
                                 showToolbar: true, backgroundColor: "#1a73e8",
                                 handleURLs: true, openAnyURL: true))
    }

    func testURLHandlingDefaultsOffWhenAbsent() {
        let cfg = AppConfig.parse(plistData: plist(["WebWrapURL": "https://x.test"]))
        XCTAssertEqual(cfg?.handleURLs, false)
        XCTAssertEqual(cfg?.openAnyURL, false)
    }

    func testBackgroundColorAbsentParsesNil() {
        let cfg = AppConfig.parse(plistData: plist(["WebWrapURL": "https://x.test"]))
        XCTAssertNil(cfg?.backgroundColor)
    }

    func testBackgroundColorEmptyParsesNil() {
        let cfg = AppConfig.parse(plistData: plist([
            "WebWrapURL": "https://x.test", "WebWrapBackgroundColor": ""]))
        XCTAssertNil(cfg?.backgroundColor)
    }

    func testToolbarDefaultsOffWhenAbsent() {
        // Apps created before the toolbar flag have no WebWrapToolbar key.
        let cfg = AppConfig.parse(plistData: plist(["WebWrapURL": "https://x.test"]))
        XCTAssertEqual(cfg?.showToolbar, false)
    }

    func testToolbarZeroParsesAsOff() {
        let cfg = AppConfig.parse(plistData: plist([
            "WebWrapURL": "https://x.test", "WebWrapToolbar": "0"]))
        XCTAssertEqual(cfg?.showToolbar, false)
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
                                 bundleId: "dk.yepz.webwrap.old", width: 1200, height: 800,
                                 showToolbar: false, backgroundColor: "#123456",
                                 handleURLs: false, openAnyURL: false)

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

    func testToolbarOverrideToggles() {
        XCTAssertTrue(base.applying(showToolbar: true).showToolbar)
        let on = base.applying(showToolbar: true)
        XCTAssertFalse(on.applying(showToolbar: false).showToolbar)
    }

    func testToolbarCarriedOverWhenNil() {
        // A nil override (flag omitted on `update`) keeps the existing setting.
        let on = base.applying(showToolbar: true)
        XCTAssertTrue(on.applying(url: "https://new.test").showToolbar)
    }

    func testBackgroundColorCarriedOverByDefault() {
        // The default `applying()` (no backgroundColor arg) keeps the existing color.
        XCTAssertEqual(base.applying(url: "https://new.test").backgroundColor, "#123456")
    }

    func testBackgroundColorCanBeReplacedAndCleared() {
        XCTAssertEqual(base.applying(backgroundColor: "#abcdef").backgroundColor, "#abcdef")
        // .some(nil) clears it (double-optional inner nil).
        XCTAssertNil(base.applying(backgroundColor: .some(nil)).backgroundColor)
    }

    func testURLHandlingOverrideToggles() {
        XCTAssertTrue(base.applying(handleURLs: true).handleURLs)
        XCTAssertTrue(base.applying(openAnyURL: true).openAnyURL)
        let on = base.applying(handleURLs: true, openAnyURL: true)
        XCTAssertFalse(on.applying(handleURLs: false).handleURLs)
        XCTAssertFalse(on.applying(openAnyURL: false).openAnyURL)
    }

    func testURLHandlingCarriedOverWhenNil() {
        let on = base.applying(handleURLs: true, openAnyURL: true)
        let after = on.applying(url: "https://new.test")
        XCTAssertTrue(after.handleURLs)
        XCTAssertTrue(after.openAnyURL)
    }
}
