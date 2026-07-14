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

final class NavigationPolicyTests: XCTestCase {
    /// Shorthand: policy for a wrapped outlook.office.com app without --open-any-url.
    private func policy(_ url: String, isMainFrame: Bool = true, isLinkClick: Bool = false,
                        targetsNewWindow: Bool = false, appHost: String? = "outlook.office.com",
                        allowAnyDomain: Bool = false,
                        externalLinks: Bool = true) -> HostNavigation.NavigationPolicy {
        HostNavigation.policy(for: URL(string: url)!, isMainFrame: isMainFrame,
                              isLinkClick: isLinkClick, targetsNewWindow: targetsNewWindow,
                              appHost: appHost, allowAnyDomain: allowAnyDomain,
                              externalLinks: externalLinks)
    }

    func testOffSiteNewWindowOpensExternally() {
        // The Outlook email-link case: target=_blank to some article.
        XCTAssertEqual(policy("https://news.example.com/story", targetsNewWindow: true),
                       .externalBrowser)
    }

    func testOffSiteMainFrameLinkClickOpensExternally() {
        XCTAssertEqual(policy("https://news.example.com/story", isLinkClick: true),
                       .externalBrowser)
    }

    func testSafelinksWrappedLinkOpensExternally() {
        XCTAssertEqual(policy("https://eur01.safelinks.protection.outlook.com/?url=x",
                              isLinkClick: true, targetsNewWindow: true),
                       .externalBrowser)
    }

    func testSameSiteStaysInApp() {
        XCTAssertEqual(policy("https://outlook.office.com/mail/inbox", isLinkClick: true),
                       .inApp)
        // Subdomains count as same-site (dot-boundary rule).
        XCTAssertEqual(policy("https://attachments.outlook.office.com/x",
                              targetsNewWindow: true),
                       .inApp)
    }

    func testSSOHostsStayInApp() {
        // Sign-in round-trips must complete inside the app's own data store.
        XCTAssertEqual(policy("https://login.microsoftonline.com/common/oauth2/authorize",
                              isLinkClick: true),
                       .inApp)
        XCTAssertEqual(policy("https://accounts.google.com/signin", isLinkClick: true,
                              appHost: "mail.google.com"),
                       .inApp)
        // Subdomain of an SSO host.
        XCTAssertEqual(policy("https://eur.okta.com/login", isLinkClick: true), .inApp)
    }

    func testRedirectsAndFormPostsStayInApp() {
        // OAuth chains are redirects/form posts, not link clicks — never externalized.
        XCTAssertEqual(policy("https://some-idp.example.com/callback"), .inApp)
    }

    func testSubframeLinkClickStaysInApp() {
        // A link inside an iframe navigating that iframe isn't a page-leaving jump.
        XCTAssertEqual(policy("https://ads.example.com/x", isMainFrame: false,
                              isLinkClick: true),
                       .inApp)
    }

    func testNonWebSchemesGoToSystem() {
        XCTAssertEqual(policy("mailto:someone@example.com", isLinkClick: true),
                       .externalBrowser)
        XCTAssertEqual(policy("msteams://l/meetup-join/x", isLinkClick: true),
                       .externalBrowser)
    }

    func testInternalContentSchemesStayInApp() {
        // The offline fallback (loadHTMLString → about:blank), blank popups, and
        // blob: downloads must never be handed to NSWorkspace.
        XCTAssertEqual(policy("about:blank"), .inApp)
        XCTAssertEqual(policy("data:text/html,hi"), .inApp)
        XCTAssertEqual(policy("blob:https://outlook.office.com/uuid"), .inApp)
    }

    func testExternalLinksOffKeepsWebLinksInApp() {
        // --no-external-links: the pre-option behavior — everything web in-window.
        XCTAssertEqual(policy("https://news.example.com/story", isLinkClick: true,
                              externalLinks: false),
                       .inApp)
        XCTAssertEqual(policy("https://news.example.com/story", targetsNewWindow: true,
                              externalLinks: false),
                       .inApp)
        // mailto: can never render in the web view, so it still goes to the system.
        XCTAssertEqual(policy("mailto:a@b.com", externalLinks: false), .externalBrowser)
    }

    func testAllowAnyDomainBrowsesInWindow() {
        XCTAssertEqual(policy("https://news.example.com/story", isLinkClick: true,
                              targetsNewWindow: true, allowAnyDomain: true),
                       .inApp)
        // Non-web schemes still go to the system even with allow-any.
        XCTAssertEqual(policy("mailto:a@b.com", allowAnyDomain: true), .externalBrowser)
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
