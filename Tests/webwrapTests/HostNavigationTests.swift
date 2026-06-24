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

final class ShouldOpenIncomingURLTests: XCTestCase {
    func testExactHostAccepted() {
        XCTAssertTrue(HostNavigation.shouldOpen(
            incomingHost: "github.com", appHost: "github.com", allowAnyDomain: false))
    }

    func testSubdomainAccepted() {
        XCTAssertTrue(HostNavigation.shouldOpen(
            incomingHost: "www.github.com", appHost: "github.com", allowAnyDomain: false))
        XCTAssertTrue(HostNavigation.shouldOpen(
            incomingHost: "gist.github.com", appHost: "github.com", allowAnyDomain: false))
    }

    func testDifferentDomainRejected() {
        XCTAssertFalse(HostNavigation.shouldOpen(
            incomingHost: "example.com", appHost: "github.com", allowAnyDomain: false))
    }

    func testLookalikeDomainRejected() {
        // The dot-boundary check must not let "notgithub.com" match "github.com".
        XCTAssertFalse(HostNavigation.shouldOpen(
            incomingHost: "notgithub.com", appHost: "github.com", allowAnyDomain: false))
        XCTAssertFalse(HostNavigation.shouldOpen(
            incomingHost: "github.com.evil.com", appHost: "github.com", allowAnyDomain: false))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(HostNavigation.shouldOpen(
            incomingHost: "WWW.GitHub.COM", appHost: "github.com", allowAnyDomain: false))
    }

    func testAllowAnyDomainAcceptsOffDomain() {
        XCTAssertTrue(HostNavigation.shouldOpen(
            incomingHost: "example.com", appHost: "github.com", allowAnyDomain: true))
    }

    func testAllowAnyDomainStillNeedsAHost() {
        // Even with allow-any, a nil/empty incoming host is nothing to open.
        XCTAssertFalse(HostNavigation.shouldOpen(
            incomingHost: nil, appHost: "github.com", allowAnyDomain: true))
        XCTAssertFalse(HostNavigation.shouldOpen(
            incomingHost: "", appHost: "github.com", allowAnyDomain: true))
    }

    func testRejectsWhenNoAppHostAndNotAllowAny() {
        XCTAssertFalse(HostNavigation.shouldOpen(
            incomingHost: "github.com", appHost: nil, allowAnyDomain: false))
    }
}

final class IsWebURLTests: XCTestCase {
    func testAcceptsHTTPAndHTTPS() {
        XCTAssertTrue(HostNavigation.isWebURL(URL(string: "https://x.test")!))
        XCTAssertTrue(HostNavigation.isWebURL(URL(string: "http://x.test")!))
        XCTAssertTrue(HostNavigation.isWebURL(URL(string: "HTTPS://x.test")!))
    }

    func testRejectsOtherSchemes() {
        XCTAssertFalse(HostNavigation.isWebURL(URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(HostNavigation.isWebURL(URL(string: "javascript:alert(1)")!))
        XCTAssertFalse(HostNavigation.isWebURL(URL(string: "mailto:a@b.com")!))
    }
}
