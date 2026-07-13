import XCTest
@testable import webwrap

// Tests for the generated app's About-panel credits text (pure, no AppKit).

final class HostAboutTests: XCTestCase {
    func testUrlAndCreatorVersion() {
        let credits = HostAbout.credits(url: "https://outlook.office.com", creatorVersion: "0.2.0")
        XCTAssertEqual(credits, """
        Opens: https://outlook.office.com
        Browser identity: Safari (default)
        Created with webwrap 0.2.0
        """)
    }

    func testMissingCreatorVersionFallsBack() {
        let credits = HostAbout.credits(url: "https://x.test", creatorVersion: nil)
        XCTAssertEqual(credits, """
        Opens: https://x.test
        Browser identity: Safari (default)
        Created with webwrap
        """)
    }

    func testMissingURLOmitsOpensLine() {
        let credits = HostAbout.credits(url: nil, creatorVersion: "1.2.3")
        XCTAssertEqual(credits, "Browser identity: Safari (default)\nCreated with webwrap 1.2.3")
    }

    func testEmptyStringsTreatedAsMissing() {
        XCTAssertEqual(HostAbout.credits(url: "", creatorVersion: ""),
                       "Browser identity: Safari (default)\nCreated with webwrap")
    }

    func testUserAgentPresetShownByName() {
        let credits = HostAbout.credits(url: nil, creatorVersion: nil, userAgent: "edge")
        XCTAssertTrue(credits.contains("Browser identity: Edge"))
    }

    func testCustomUserAgentShownAsCustom() {
        // The full string lives in Settings; About just names the kind.
        let credits = HostAbout.credits(url: nil, creatorVersion: nil,
                                        userAgent: "Mozilla/5.0 (Whatever) Gecko/1.0")
        XCTAssertTrue(credits.contains("Browser identity: Custom"))
    }
}

final class UserAgentDisplayNameTests: XCTestCase {
    func testMapping() {
        XCTAssertEqual(UserAgent.displayName(for: nil), "Safari (default)")
        XCTAssertEqual(UserAgent.displayName(for: ""), "Safari (default)")
        XCTAssertEqual(UserAgent.displayName(for: "safari"), "Safari (default)")
        XCTAssertEqual(UserAgent.displayName(for: "Chrome"), "Chrome")
        XCTAssertEqual(UserAgent.displayName(for: "EDGE"), "Edge")
        XCTAssertEqual(UserAgent.displayName(for: "Mozilla/5.0 (X) Gecko"), "Custom")
    }
}
