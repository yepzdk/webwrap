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
            "WebWrapToolbarStyle": "compact",
            "WebWrapBackgroundColor": "#1a73e8",
            "WebWrapUserAgent": "edge",
            "WebWrapHandleURLs": "1",
            "WebWrapOpenAnyURL": "1",
            "WebWrapProgressBar": "1",
            "WebWrapExternalLinks": "0",
            "WebWrapReader": "1",
        ])
        XCTAssertEqual(AppConfig.parse(plistData: data),
                       AppConfig(url: "https://outlook.office.com", name: "Outlook",
                                 bundleId: "dk.yepz.webwrap.outlook", width: 1000, height: 700,
                                 showToolbar: true, toolbarStyle: .compact,
                                 progressBar: true, backgroundColor: "#1a73e8",
                                 userAgent: "edge",
                                 handleURLs: true, openAnyURL: true,
                                 externalLinks: false, reader: true))
    }

    func testReaderDefaultsOffWhenAbsent() {
        // Apps created before reader mode have no key — reader stays off.
        let cfg = AppConfig.parse(plistData: plist(["WebWrapURL": "https://x.test"]))
        XCTAssertEqual(cfg?.reader, false)
    }

    func testEmptyURLParsesAsHandlerOnly() {
        // Handler-only apps bake WebWrapURL as "" — still recognized as webwrap apps.
        let cfg = AppConfig.parse(plistData: plist(["WebWrapURL": ""]))
        XCTAssertNotNil(cfg)
        XCTAssertEqual(cfg?.isHandlerOnly, true)
    }

    func testSiteAppIsNotHandlerOnly() {
        let cfg = AppConfig.parse(plistData: plist(["WebWrapURL": "https://x.test"]))
        XCTAssertEqual(cfg?.isHandlerOnly, false)
    }

    func testExternalLinksDefaultsOnWhenAbsent() {
        // Apps created before the option have no key — they adopt the default (on).
        let cfg = AppConfig.parse(plistData: plist(["WebWrapURL": "https://x.test"]))
        XCTAssertEqual(cfg?.externalLinks, true)
    }

    func testExternalLinksZeroParsesAsOff() {
        let cfg = AppConfig.parse(plistData: plist([
            "WebWrapURL": "https://x.test", "WebWrapExternalLinks": "0"]))
        XCTAssertEqual(cfg?.externalLinks, false)
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

    func testUserAgentAbsentParsesNil() {
        let cfg = AppConfig.parse(plistData: plist(["WebWrapURL": "https://x.test"]))
        XCTAssertNil(cfg?.userAgent)
    }

    func testUserAgentEmptyParsesNil() {
        let cfg = AppConfig.parse(plistData: plist([
            "WebWrapURL": "https://x.test", "WebWrapUserAgent": ""]))
        XCTAssertNil(cfg?.userAgent)
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

    func testToolbarStyleDefaultsToRegularWhenAbsent() {
        // Apps created before the toolbar-size setting have no WebWrapToolbarStyle key.
        let cfg = AppConfig.parse(plistData: plist(["WebWrapURL": "https://x.test"]))
        XCTAssertEqual(cfg?.toolbarStyle, .regular)
    }

    func testToolbarStyleUnknownValueFallsBackToRegular() {
        let cfg = AppConfig.parse(plistData: plist([
            "WebWrapURL": "https://x.test", "WebWrapToolbarStyle": "gigantic"]))
        XCTAssertEqual(cfg?.toolbarStyle, .regular)
    }

    func testToolbarStyleCompactParses() {
        let cfg = AppConfig.parse(plistData: plist([
            "WebWrapURL": "https://x.test", "WebWrapToolbarStyle": "compact"]))
        XCTAssertEqual(cfg?.toolbarStyle, .compact)
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
                                 showToolbar: false, toolbarStyle: .regular,
                                 progressBar: false, backgroundColor: "#123456",
                                 userAgent: "chrome",
                                 handleURLs: false, openAnyURL: false,
                                 externalLinks: true, reader: false)

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

    func testToolbarStyleOverrideAndCarryOver() {
        XCTAssertEqual(base.applying(toolbarStyle: .compact).toolbarStyle, .compact)
        // A nil override (flag omitted) keeps the existing style.
        let compact = base.applying(toolbarStyle: .compact)
        XCTAssertEqual(compact.applying(url: "https://new.test").toolbarStyle, .compact)
    }

    func testProgressBarOverrideToggles() {
        XCTAssertTrue(base.applying(progressBar: true).progressBar)
        let on = base.applying(progressBar: true)
        XCTAssertFalse(on.applying(progressBar: false).progressBar)
    }

    func testProgressBarCarriedOverWhenNil() {
        let on = base.applying(progressBar: true)
        XCTAssertTrue(on.applying(url: "https://new.test").progressBar)
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

    func testUserAgentCarriedOverByDefault() {
        XCTAssertEqual(base.applying(url: "https://new.test").userAgent, "chrome")
    }

    func testUserAgentCanBeReplacedAndCleared() {
        XCTAssertEqual(base.applying(userAgent: "edge").userAgent, "edge")
        // .some(nil) resets to the default (double-optional inner nil).
        XCTAssertNil(base.applying(userAgent: .some(nil)).userAgent)
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

    func testExternalLinksOverrideTogglesAndCarriesOver() {
        XCTAssertFalse(base.applying(externalLinks: false).externalLinks)
        // A nil override (flag omitted on `update`) keeps the existing setting.
        let off = base.applying(externalLinks: false)
        XCTAssertFalse(off.applying(url: "https://new.test").externalLinks)
    }

    func testReaderOverrideTogglesAndCarriesOver() {
        XCTAssertTrue(base.applying(reader: true).reader)
        // A nil override (flag omitted on `update`) keeps the existing setting.
        let on = base.applying(reader: true)
        XCTAssertTrue(on.applying(url: "https://new.test").reader)
    }
}
