import XCTest
@testable import webwrap

// Tests for the tracking-URL cleaner (port of yepzdk/url-cleaner). Pure — no host.

final class URLCleanerTests: XCTestCase {
    private func clean(_ s: String) -> String {
        URLCleaner.clean(URL(string: s)!).absoluteString
    }

    // MARK: - Path-embedded encoded destinations (TLDR style)

    func testUnwrapsTLDRTrackingURL() {
        // The reported real-world URL: encoded destination in the path, tracking
        // segments after the first literal slash, utm param inside the destination.
        let tracking = "https://tracking.tldrnewsletter.com/CL0/https:%2F%2Fwww.figma.com"
            + "%2Fblog%2Fgpt-5-6-is-now-available-in-figma-make%2F%3Futm_source=tldrdesign"
            + "/1/0100019f6099b895-39a4390f-2407-4534-b1e0-ae08c0822612-000000"
            + "/C76Ew-pTnPFLboJMXxswwsn1zOXh1eDM8v6wIed1KpE=452"
        XCTAssertEqual(clean(tracking),
                       "https://www.figma.com/blog/gpt-5-6-is-now-available-in-figma-make/")
    }

    func testUnwrapsFullyEncodedSchemeVariant() {
        // Some wrappers encode the colon too (https%3A%2F%2F).
        XCTAssertEqual(clean("https://t.example.com/r/https%3A%2F%2Fdest.test%2Fa/xyz"),
                       "https://dest.test/a")
    }

    func testPlainNestedURLIsNotUnwrapped() {
        // Wayback Machine links embed the destination UNENCODED — must survive.
        let wayback = "https://web.archive.org/web/20240101000000/https://example.com/page"
        XCTAssertEqual(clean(wayback), wayback)
    }

    // MARK: - Query-embedded destinations

    func testUnwrapsGoogleRedirect() {
        XCTAssertEqual(clean("https://www.google.com/url?q=https://example.com/article&sa=D"),
                       "https://example.com/article")
        XCTAssertEqual(clean("https://www.google.com/url?url=https://example.com/x"),
                       "https://example.com/x")
    }

    func testUnwrapsFacebookAndSafeLinks() {
        XCTAssertEqual(clean("https://l.facebook.com/l.php?u=https://example.com/post&h=x"),
                       "https://example.com/post")
        XCTAssertEqual(
            clean("https://eur01.safelinks.protection.outlook.com/?url=https://example.com/doc&data=x"),
            "https://example.com/doc")
    }

    func testOAuthRedirectURIIsNotUnwrapped() {
        // Sign-in links must keep their redirect_uri — only utm-style params from
        // the tracker list may be touched (none here).
        let oauth = "https://login.example.com/authorize?client_id=x"
            + "&redirect_uri=https://app.example.com/callback&state=abc"
        XCTAssertEqual(clean(oauth), oauth)
    }

    func testRedirectParamWithNonURLValueIgnored() {
        // ?q= carrying a search term, not a URL, is left alone.
        let search = "https://duckduckgo.com/?q=swift+wkwebview"
        XCTAssertEqual(clean(search), search)
    }

    func testUnwrapsLinkedInRedirectorOnly() {
        XCTAssertEqual(clean("https://lnkd.in/x?url=https://example.com/post"),
                       "https://example.com/post")
        XCTAssertEqual(
            clean("https://www.linkedin.com/redir/redirect?url=https://example.com/post"),
            "https://example.com/post")
        // Any other LinkedIn page is an ordinary site, not a redirector.
        let feed = "https://www.linkedin.com/feed/?url=https://example.com/post"
        XCTAssertEqual(clean(feed), feed)
    }

    // MARK: - Query unwrapping is limited to redirector hosts (#119)

    func testRedirectParamOnOrdinaryHostIsLeftAlone() {
        // A document viewer's own ?url= parameter: unwrapping it would skip the
        // viewer page, and under same-site scoping drop the link entirely.
        let viewer = "https://example.com/viewer?url=https://cdn.example.net/report.pdf"
        XCTAssertEqual(clean(viewer), viewer)
        let proxy = "https://images.example.com/resize?u=https://cdn.example.net/a.jpg"
        XCTAssertEqual(clean(proxy), proxy)
        let oembed = "https://example.com/oembed?link=https://example.com/watch/1"
        XCTAssertEqual(clean(oembed), oembed)
    }

    func testEncodedRedirectParamOnOrdinaryHostIsLeftAlone() {
        // The same parameter percent-encoded must not be unwrapped by the
        // path-embed rule either — the embed is in the query, not the path. The
        // query's encoding is normalized on the way through, so this checks where
        // the URL points rather than its exact spelling.
        let viewer = URL(string:
            "https://example.com/viewer?url=https%3A%2F%2Fcdn.example.net%2Freport.pdf")!
        let cleaned = URLCleaner.clean(viewer)
        XCTAssertEqual(cleaned.host, "example.com")
        XCTAssertEqual(cleaned.path, "/viewer")
        XCTAssertEqual(URLComponents(url: cleaned, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "url" }?.value,
                       "https://cdn.example.net/report.pdf")
    }

    func testSearchForAURLStaysOnTheResultsPage() {
        // `q` is a search parameter everywhere except google.*/url.
        let search = "https://example.com/search?q=https://example.com/article"
        XCTAssertEqual(clean(search), search)
        let googleSearch = "https://www.google.com/search?q=https://example.com/article"
        XCTAssertEqual(clean(googleSearch), googleSearch)
    }

    func testGoogleCountryDomainRedirectUnwrapped() {
        XCTAssertEqual(clean("https://www.google.co.uk/url?q=https://example.com/a"),
                       "https://example.com/a")
        // Not every google.* host is the redirector — only the /url endpoint.
        let translate = "https://translate.google.com/?u=https://example.com/a"
        XCTAssertEqual(clean(translate), translate)
    }

    func testLookalikeRedirectorHostIsNotTrusted() {
        let fake = "https://l.facebook.com.evil.test/l.php?u=https://example.com/post"
        XCTAssertEqual(clean(fake), fake)
        let fakeGoogle = "https://google.com.evil.test/url?q=https://example.com/a"
        XCTAssertEqual(clean(fakeGoogle), fakeGoogle)
    }

    // MARK: - Postmark

    func testUnwrapsPostmark() {
        let tracking = "https://track.pstmrk.it/3s/example.com%2Farticle"
            + "/AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcd"
        XCTAssertEqual(clean(tracking), "https://example.com/article")
    }

    // MARK: - Nested wrappers

    func testNestedWrappersResolve() {
        // A Google redirect wrapping a Facebook redirect wrapping the article.
        let nested = "https://www.google.com/url?q=https://l.facebook.com/l.php%3Fu=https://example.com/deep"
        XCTAssertEqual(clean(nested), "https://example.com/deep")
    }

    // MARK: - Tracking parameter stripping

    func testStripsTrackingParamsKeepsOthers() {
        XCTAssertEqual(
            clean("https://example.com/a?utm_source=x&id=42&fbclid=abc&utm_medium=mail&gclid=z"),
            "https://example.com/a?id=42")
    }

    func testPaginationParamSurvives() {
        // Deviation from upstream: bare `p` is NOT stripped (?p=2 pagination).
        XCTAssertEqual(clean("https://example.com/list?p=2"), "https://example.com/list?p=2")
    }

    func testFragmentPreserved() {
        XCTAssertEqual(clean("https://example.com/a?utm_source=x#section"),
                       "https://example.com/a#section")
    }

    func testCleanURLIsUntouched() {
        let plain = "https://example.com/article?id=7"
        XCTAssertEqual(clean(plain), plain)
    }
}
