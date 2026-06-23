import XCTest
import Foundation
@testable import webwrap

// Tests for the icon-quality additions (#14): og:image/twitter:image meta extraction,
// the squareness guard, and the og:image step in the resolution chain (with a mocked
// measurer so no real images/sips are needed).

final class SocialImageURLTests: XCTestCase {
    func testPrefersOgImage() {
        let html = """
        <meta property="og:image" content="https://x.test/og.png">
        <meta name="twitter:image" content="https://x.test/tw.png">
        """
        XCTAssertEqual(IconResolver.socialImageURL(in: html), "https://x.test/og.png")
    }

    func testFallsBackToTwitterImage() {
        let html = #"<meta name="twitter:image" content="https://x.test/tw.png">"#
        XCTAssertEqual(IconResolver.socialImageURL(in: html), "https://x.test/tw.png")
    }

    func testHandlesOgImageUrlVariant() {
        let html = #"<meta property="og:image:url" content="https://x.test/o.png">"#
        XCTAssertEqual(IconResolver.socialImageURL(in: html), "https://x.test/o.png")
    }

    func testNilWhenAbsent() {
        XCTAssertNil(IconResolver.socialImageURL(in: "<meta charset=\"utf-8\">"))
    }

    func testIgnoresEmptyContent() {
        XCTAssertNil(IconResolver.socialImageURL(in: #"<meta property="og:image" content="">"#))
    }
}

final class SquarenessTests: XCTestCase {
    func testExactSquareAccepted() {
        XCTAssertTrue(IconResolver.isSquareEnough(width: 512, height: 512))
    }

    func testWithinToleranceAccepted() {
        // 512x460 → ratio ~1.11, under the default 1.15.
        XCTAssertTrue(IconResolver.isSquareEnough(width: 512, height: 460))
    }

    func testWideBannerRejected() {
        // 1920x1080 (16:9) → ratio ~1.78.
        XCTAssertFalse(IconResolver.isSquareEnough(width: 1920, height: 1080))
    }

    func testTallImageRejected() {
        XCTAssertFalse(IconResolver.isSquareEnough(width: 600, height: 1200))
    }

    func testJustOverToleranceRejected() {
        // ratio 1.20 > 1.15
        XCTAssertFalse(IconResolver.isSquareEnough(width: 1200, height: 1000))
    }

    func testZeroDimensionsRejected() {
        XCTAssertFalse(IconResolver.isSquareEnough(width: 0, height: 0))
    }
}

final class MetaTagScanTests: XCTestCase {
    func testExtractsMetaTags() {
        let html = """
        <META property="og:image" content="/a.png">
        <meta name="twitter:image" content="/b.png"><link rel="icon" href="/c.png">
        """
        // Two meta tags; the <link> must not be counted.
        XCTAssertEqual(IconResolver.metaTags(in: html).count, 2)
    }
}

final class OpenGraphChainTests: XCTestCase {
    private func resolver(site: String,
                          responses: [String: Data],
                          measure: @escaping IconResolver.Measure) -> IconResolver {
        IconResolver(siteURL: URL(string: site)!,
                     fetch: { responses[$0.absoluteString] },
                     measure: measure)
    }

    func testUsesSquareOgImageBeforeFavicon() {
        let r = resolver(
            site: "https://x.test/",
            responses: [
                "https://x.test/": Data(#"<meta property="og:image" content="/og.png">"#.utf8),
                "https://x.test/og.png": Data("OGBYTES".utf8),
                "https://x.test/favicon.ico": Data("ICO".utf8),
            ],
            measure: { _ in (1024, 1024) }) // square → accepted
        let resolved = r.resolve()
        XCTAssertEqual(resolved?.source, .openGraphImage)
        XCTAssertEqual(resolved?.data, Data("OGBYTES".utf8))
    }

    func testSkipsWideOgImageAndFallsBackToFavicon() {
        let r = resolver(
            site: "https://x.test/",
            responses: [
                "https://x.test/": Data(#"<meta property="og:image" content="/banner.png">"#.utf8),
                "https://x.test/banner.png": Data("BANNER".utf8),
                "https://x.test/favicon.ico": Data("ICO".utf8),
            ],
            measure: { _ in (1920, 1080) }) // 16:9 → rejected, falls through
        let resolved = r.resolve()
        XCTAssertEqual(resolved?.source, .faviconIco)
    }

    func testSkipsOgImageWhenUnmeasurable() {
        let r = resolver(
            site: "https://x.test/",
            responses: [
                "https://x.test/": Data(#"<meta property="og:image" content="/og.png">"#.utf8),
                "https://x.test/og.png": Data("OG".utf8),
                "https://x.test/favicon.ico": Data("ICO".utf8),
            ],
            measure: { _ in nil }) // undecodable → skip
        XCTAssertEqual(r.resolve()?.source, .faviconIco)
    }
}
