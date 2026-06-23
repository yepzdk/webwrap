import XCTest
@testable import webwrap

// Tests for the generated app's About-panel credits text (pure, no AppKit).

final class HostAboutTests: XCTestCase {
    func testUrlAndCreatorVersion() {
        let credits = HostAbout.credits(url: "https://outlook.office.com", creatorVersion: "0.2.0")
        XCTAssertEqual(credits, "Opens: https://outlook.office.com\nCreated with webwrap 0.2.0")
    }

    func testMissingCreatorVersionFallsBack() {
        let credits = HostAbout.credits(url: "https://x.test", creatorVersion: nil)
        XCTAssertEqual(credits, "Opens: https://x.test\nCreated with webwrap")
    }

    func testMissingURLOmitsOpensLine() {
        let credits = HostAbout.credits(url: nil, creatorVersion: "1.2.3")
        XCTAssertEqual(credits, "Created with webwrap 1.2.3")
    }

    func testEmptyStringsTreatedAsMissing() {
        XCTAssertEqual(HostAbout.credits(url: "", creatorVersion: ""), "Created with webwrap")
    }
}
