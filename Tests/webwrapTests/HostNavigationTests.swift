import XCTest
@testable import webwrap

// Tests for the pure "Copy Current URL" decision (no AppKit / pasteboard).

final class HostNavigationTests: XCTestCase {
    func testReturnsAbsoluteStringForLoadedURL() {
        let url = URL(string: "https://outlook.office.com/mail/inbox?id=42")
        XCTAssertEqual(HostNavigation.urlToCopy(currentURL: url),
                       "https://outlook.office.com/mail/inbox?id=42")
    }

    func testNilWhenNoURL() {
        // No page loaded → nothing to copy → menu item stays disabled.
        XCTAssertNil(HostNavigation.urlToCopy(currentURL: nil))
    }
}
