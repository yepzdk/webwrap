import XCTest
import Foundation
@testable import webwrap

// Tests for #16: skipping empty / placeholder `data:` icon hrefs so the resolver falls
// through to the next source instead of attempting a doomed conversion.

final class UsableIconHrefTests: XCTestCase {
    func testAcceptsNormalURLs() {
        XCTAssertTrue(IconResolver.isUsableIconHref("https://x.test/icon.png"))
        XCTAssertTrue(IconResolver.isUsableIconHref("/favicon.ico"))
        XCTAssertTrue(IconResolver.isUsableIconHref("//cdn.x.test/i.png"))
    }

    func testAcceptsDataURIWithPayload() {
        // A real (tiny) data URI carrying actual bytes is usable.
        XCTAssertTrue(IconResolver.isUsableIconHref("data:image/png;base64,iVBORw0KGgo="))
    }

    func testRejectsEmptyAndWhitespace() {
        XCTAssertFalse(IconResolver.isUsableIconHref(""))
        XCTAssertFalse(IconResolver.isUsableIconHref("   "))
    }

    func testRejectsEmptyDataURIs() {
        XCTAssertFalse(IconResolver.isUsableIconHref("data:,"))           // example.com's placeholder
        XCTAssertFalse(IconResolver.isUsableIconHref("data:;base64,"))
        XCTAssertFalse(IconResolver.isUsableIconHref("DATA:,"))           // case-insensitive scheme
        XCTAssertFalse(IconResolver.isUsableIconHref("data:image/png,  ")) // payload only whitespace
    }
}

final class SkipEmptyIconChainTests: XCTestCase {
    private func resolver(site: String, responses: [String: Data]) -> IconResolver {
        IconResolver(siteURL: URL(string: site)!, fetch: { responses[$0.absoluteString] })
    }

    func testLinkIconWithDataURIIsSkippedAndFallsThrough() {
        // Mirrors example.com: the only <link rel="icon"> is an empty data: URI.
        // It must be ignored so the resolver falls through to favicon.ico.
        let r = resolver(site: "https://x.test/", responses: [
            "https://x.test/": Data(#"<link rel="icon" href="data:,">"#.utf8),
            "https://x.test/favicon.ico": Data("ICO".utf8),
        ])
        let resolved = r.resolve()
        XCTAssertEqual(resolved?.source, .faviconIco)
    }

    func testRealLinkIconStillUsed() {
        // A normal link icon is unaffected by the new filter.
        let r = resolver(site: "https://x.test/", responses: [
            "https://x.test/": Data(#"<link rel="icon" href="/icon.png">"#.utf8),
            "https://x.test/icon.png": Data("PNG".utf8),
        ])
        let resolved = r.resolve()
        XCTAssertEqual(resolved?.source, .linkIcon)
        XCTAssertEqual(resolved?.data, Data("PNG".utf8))
    }
}
