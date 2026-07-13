import XCTest
@testable import webwrap

// Tests for the pure resolution of the user-agent setting (preset token / custom
// string / nil) to what the host assigns to `WKWebView.customUserAgent`.

final class UserAgentTests: XCTestCase {
    func testNilAndSafariResolveToNil() {
        // nil customUserAgent keeps the Safari-suffixed default from
        // applicationNameForUserAgent.
        XCTAssertNil(UserAgent.customUserAgent(for: nil))
        XCTAssertNil(UserAgent.customUserAgent(for: "safari"))
        XCTAssertNil(UserAgent.customUserAgent(for: "Safari"))
        XCTAssertNil(UserAgent.customUserAgent(for: ""))
        XCTAssertNil(UserAgent.customUserAgent(for: "  "))
    }

    func testPresetsResolveCaseInsensitively() {
        let chrome = UserAgent.customUserAgent(for: "chrome")
        XCTAssertNotNil(chrome)
        XCTAssertTrue(chrome!.contains("Chrome/"))
        XCTAssertFalse(chrome!.contains("Edg/"))
        XCTAssertEqual(UserAgent.customUserAgent(for: "Chrome"), chrome)

        let edge = UserAgent.customUserAgent(for: "EDGE")
        XCTAssertNotNil(edge)
        XCTAssertTrue(edge!.contains("Edg/"))
        XCTAssertTrue(edge!.contains("Chrome/")) // Edge's UA embeds the Chrome token
    }

    func testCustomStringPassesThroughVerbatim() {
        let custom = "Mozilla/5.0 (MyBrowser) Gecko/20100101 Firefox/128.0"
        XCTAssertEqual(UserAgent.customUserAgent(for: custom), custom)
    }

    func testSafariApplicationNameHasVersionAndSafariTokens() {
        // The whole point of the feature: the default UA must carry both tokens that
        // UA-sniffing sites look for.
        XCTAssertTrue(UserAgent.safariApplicationName.contains("Version/"))
        XCTAssertTrue(UserAgent.safariApplicationName.contains("Safari/"))
    }
}
