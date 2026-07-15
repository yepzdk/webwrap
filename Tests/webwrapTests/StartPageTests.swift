import XCTest
@testable import webwrap

// Tests for the handler-only start page's pure HTML generation. Mirrors the
// OfflineFallback tests: escaping and the CSSColor-gated background rule.

final class StartPageTests: XCTestCase {
    func testContainsEscapedAppName() {
        let html = StartPage.html(appName: "Read & Relax <x>", backgroundColor: nil)
        XCTAssertTrue(html.contains("Read &amp; Relax &lt;x&gt;"))
        XCTAssertFalse(html.contains("Read & Relax <x>"))
    }

    func testDefaultBackgroundFollowsAppearance() {
        // No manifest color → the light/dark-switching variable, not a fixed color.
        let html = StartPage.html(appName: "Reader", backgroundColor: nil)
        XCTAssertTrue(html.contains("background: var(--bg);"))
    }

    func testParseableBackgroundColorIsApplied() {
        let html = StartPage.html(appName: "Reader", backgroundColor: "#1a73e8")
        XCTAssertTrue(html.contains("background: #1a73e8;"))
    }

    func testUnparseableBackgroundColorIsIgnored() {
        // A non-hex value could break out of the CSS declaration — must be dropped.
        let html = StartPage.html(appName: "Reader",
                                  backgroundColor: "red; } .card { display:none")
        XCTAssertTrue(html.contains("background: var(--bg);"))
        XCTAssertFalse(html.contains("display:none"))
    }
}
