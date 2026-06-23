import XCTest
import Foundation
@testable import webwrap

// Tests for IconResolver's pure parsing/selection helpers. No network: the full-chain
// tests inject a canned `fetch` closure so resolution is exercised end to end offline.
//
// XCTest (not swift-testing) is used deliberately — it ships with every Swift
// toolchain, so CI runs on the default runner image without pinning an Xcode.

final class AttributeTests: XCTestCase {
    func testDoubleQuoted() {
        XCTAssertEqual(IconResolver.attribute("href", in: #"<link rel="icon" href="/a.png">"#), "/a.png")
    }

    func testSingleQuoted() {
        XCTAssertEqual(IconResolver.attribute("href", in: "<link rel='icon' href='/a.png'>"), "/a.png")
    }

    func testUnquoted() {
        XCTAssertEqual(IconResolver.attribute("href", in: "<link rel=icon href=/a.png>"), "/a.png")
    }

    func testCaseInsensitiveName() {
        XCTAssertEqual(IconResolver.attribute("href", in: #"<link HREF="/A.png">"#), "/A.png")
    }

    func testPreservesValueCase() {
        XCTAssertEqual(IconResolver.attribute("href", in: #"<link href="/MixedCase.PNG">"#), "/MixedCase.PNG")
    }

    func testNoSubstringMatch() {
        // "data-href" must not satisfy a query for "href".
        let tag = #"<link data-href="/wrong.png" href="/right.png">"#
        XCTAssertEqual(IconResolver.attribute("href", in: tag), "/right.png")
    }

    func testAbsent() {
        XCTAssertNil(IconResolver.attribute("sizes", in: #"<link href="/a.png">"#))
    }
}

final class LinkTagTests: XCTestCase {
    func testExtractsAll() {
        let html = """
        <head><link rel="manifest" href="/m.json">
        <LINK rel="icon" href="/i.png" /><meta charset="utf-8"></head>
        """
        XCTAssertEqual(IconResolver.linkTags(in: html).count, 2)
    }

    func testNone() {
        XCTAssertTrue(IconResolver.linkTags(in: "<head><meta></head>").isEmpty)
    }
}

final class LinkHrefTests: XCTestCase {
    func testExactRel() {
        let html = #"<link rel="manifest" href="/site.webmanifest">"#
        XCTAssertEqual(IconResolver.linkHref(in: html, matchingRel: "manifest"), "/site.webmanifest")
    }

    func testMultiTokenRel() {
        let html = #"<link rel="shortcut icon" href="/favicon.ico">"#
        XCTAssertEqual(IconResolver.linkHref(in: html, matchingRel: "icon"), "/favicon.ico")
    }

    func testPrefixMatch() {
        let html = #"<link rel="apple-touch-icon-precomposed" href="/at.png">"#
        XCTAssertEqual(IconResolver.linkHref(in: html, matchingRel: "apple-touch-icon", prefix: true), "/at.png")
    }

    func testNoPrefixNoMatch() {
        let html = #"<link rel="apple-touch-icon-precomposed" href="/at.png">"#
        XCTAssertNil(IconResolver.linkHref(in: html, matchingRel: "apple-touch-icon"))
    }
}

final class LargestSizeTests: XCTestCase {
    func testSingle() {
        XCTAssertEqual(IconResolver.largestSize(in: "180x180"), 180)
    }

    func testList() {
        XCTAssertEqual(IconResolver.largestSize(in: "16x16 32x32 192x192"), 192)
    }

    func testAnyOrEmpty() {
        XCTAssertNil(IconResolver.largestSize(in: "any"))
        XCTAssertNil(IconResolver.largestSize(in: ""))
        XCTAssertNil(IconResolver.largestSize(in: nil))
    }
}

final class BestIconLinkTests: XCTestCase {
    func testLargestWins() {
        let html = """
        <link rel="icon" href="/16.png" sizes="16x16">
        <link rel="icon" href="/192.png" sizes="192x192">
        <link rel="icon" href="/32.png" sizes="32x32">
        """
        XCTAssertEqual(IconResolver.bestIconLinkHref(in: html), "/192.png")
    }

    func testUnsizedFallback() {
        let html = #"<link rel="icon" href="/favicon.ico">"#
        XCTAssertEqual(IconResolver.bestIconLinkHref(in: html), "/favicon.ico")
    }

    func testIgnoresNonIcon() {
        let html = #"<link rel="stylesheet" href="/x.css">"#
        XCTAssertNil(IconResolver.bestIconLinkHref(in: html))
    }
}

final class ManifestIconTests: XCTestCase {
    func testLargestPng() {
        let json = """
        {"icons":[
          {"src":"/a-192.png","sizes":"192x192","type":"image/png"},
          {"src":"/a-512.png","sizes":"512x512","type":"image/png"},
          {"src":"/a-512.svg","sizes":"512x512","type":"image/svg+xml"}
        ]}
        """.data(using: .utf8)!
        XCTAssertEqual(IconResolver.bestManifestIconHref(fromManifestJSON: json), "/a-512.png")
    }

    func testMissingFields() {
        let json = #"{"icons":[{"src":"/only.png"}]}"#.data(using: .utf8)!
        XCTAssertEqual(IconResolver.bestManifestIconHref(fromManifestJSON: json), "/only.png")
    }

    func testMalformed() {
        XCTAssertNil(IconResolver.bestManifestIconHref(fromManifestJSON: Data("not json".utf8)))
    }

    func testNoIcons() {
        XCTAssertNil(IconResolver.bestManifestIconHref(fromManifestJSON: Data(#"{"name":"x"}"#.utf8)))
    }
}

final class ResolveURLTests: XCTestCase {
    let base = URL(string: "https://example.com/app/page")!

    func testAbsolute() {
        XCTAssertEqual(IconResolver.resolveURL("https://cdn.example.com/i.png", against: base)?.absoluteString,
                       "https://cdn.example.com/i.png")
    }

    func testRootRelative() {
        XCTAssertEqual(IconResolver.resolveURL("/icons/i.png", against: base)?.absoluteString,
                       "https://example.com/icons/i.png")
    }

    func testProtocolRelative() {
        XCTAssertEqual(IconResolver.resolveURL("//cdn.example.com/i.png", against: base)?.absoluteString,
                       "https://cdn.example.com/i.png")
    }

    func testEmpty() {
        XCTAssertNil(IconResolver.resolveURL("   ", against: base))
    }
}

final class ResolveChainTests: XCTestCase {
    /// Builds a resolver whose fetch returns canned bytes for specific URLs.
    private func resolver(site: String, responses: [String: Data]) -> IconResolver {
        IconResolver(siteURL: URL(string: site)!) { url in responses[url.absoluteString] }
    }

    func testManifestWins() {
        let r = resolver(site: "https://example.com/", responses: [
            "https://example.com/": Data(#"<link rel="manifest" href="/m.json">"#.utf8),
            "https://example.com/m.json": Data(#"{"icons":[{"src":"/icon-512.png","sizes":"512x512","type":"image/png"}]}"#.utf8),
            "https://example.com/icon-512.png": Data("PNGBYTES".utf8),
        ])
        let resolved = r.resolve()
        XCTAssertEqual(resolved?.source, .manifest)
        XCTAssertEqual(resolved?.ext, "png")
        XCTAssertEqual(resolved?.data, Data("PNGBYTES".utf8))
    }

    func testAppleTouchFallback() {
        let r = resolver(site: "https://example.com/", responses: [
            "https://example.com/": Data(#"<link rel="apple-touch-icon" href="/at.png">"#.utf8),
            "https://example.com/at.png": Data("ATBYTES".utf8),
        ])
        let resolved = r.resolve()
        XCTAssertEqual(resolved?.source, .appleTouchIcon)
        XCTAssertEqual(resolved?.data, Data("ATBYTES".utf8))
    }

    func testFaviconIcoFallback() {
        let r = resolver(site: "https://example.com/", responses: [
            "https://example.com/": Data("<html><head></head></html>".utf8),
            "https://example.com/favicon.ico": Data("ICOBYTES".utf8),
        ])
        let resolved = r.resolve()
        XCTAssertEqual(resolved?.source, .faviconIco)
        XCTAssertEqual(resolved?.ext, "ico")
    }

    func testGoogleFallback() {
        let r = resolver(site: "https://example.com/", responses: [
            "https://example.com/": Data("<html></html>".utf8),
            "https://www.google.com/s2/favicons?sz=256&domain=example.com": Data("GBYTES".utf8),
        ])
        XCTAssertEqual(r.resolve()?.source, .googleService)
    }

    func testNothingFound() {
        let r = resolver(site: "https://example.com/", responses: [:])
        XCTAssertNil(r.resolve())
    }
}
