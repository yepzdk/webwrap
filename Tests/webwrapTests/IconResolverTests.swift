import Testing
import Foundation
@testable import webwrap

// Tests for IconResolver's pure parsing/selection helpers. No network: the full-chain
// test injects a canned `fetch` closure so resolution is exercised end to end offline.

@Suite("IconResolver.attribute")
struct AttributeTests {
    @Test("reads double-quoted values")
    func doubleQuoted() {
        #expect(IconResolver.attribute("href", in: #"<link rel="icon" href="/a.png">"#) == "/a.png")
    }

    @Test("reads single-quoted values")
    func singleQuoted() {
        #expect(IconResolver.attribute("href", in: "<link rel='icon' href='/a.png'>") == "/a.png")
    }

    @Test("reads unquoted values")
    func unquoted() {
        #expect(IconResolver.attribute("href", in: "<link rel=icon href=/a.png>") == "/a.png")
    }

    @Test("is case-insensitive on attribute names")
    func caseInsensitiveName() {
        #expect(IconResolver.attribute("href", in: #"<link HREF="/A.png">"#) == "/A.png")
    }

    @Test("preserves value case")
    func preservesValueCase() {
        #expect(IconResolver.attribute("href", in: #"<link href="/MixedCase.PNG">"#) == "/MixedCase.PNG")
    }

    @Test("does not match a substring of another attribute name")
    func noSubstringMatch() {
        // "data-href" must not satisfy a query for "href".
        let tag = #"<link data-href="/wrong.png" href="/right.png">"#
        #expect(IconResolver.attribute("href", in: tag) == "/right.png")
    }

    @Test("returns nil when absent")
    func absent() {
        #expect(IconResolver.attribute("sizes", in: #"<link href="/a.png">"#) == nil)
    }
}

@Suite("IconResolver.linkTags")
struct LinkTagTests {
    @Test("extracts every link tag")
    func extractsAll() {
        let html = """
        <head><link rel="manifest" href="/m.json">
        <LINK rel="icon" href="/i.png" /><meta charset="utf-8"></head>
        """
        let tags = IconResolver.linkTags(in: html)
        #expect(tags.count == 2)
    }

    @Test("returns empty for no links")
    func none() {
        #expect(IconResolver.linkTags(in: "<head><meta></head>").isEmpty)
    }
}

@Suite("IconResolver.linkHref")
struct LinkHrefTests {
    @Test("matches an exact rel token")
    func exactRel() {
        let html = #"<link rel="manifest" href="/site.webmanifest">"#
        #expect(IconResolver.linkHref(in: html, matchingRel: "manifest") == "/site.webmanifest")
    }

    @Test("matches a rel with multiple tokens")
    func multiTokenRel() {
        let html = #"<link rel="shortcut icon" href="/favicon.ico">"#
        #expect(IconResolver.linkHref(in: html, matchingRel: "icon") == "/favicon.ico")
    }

    @Test("prefix match catches apple-touch-icon-precomposed")
    func prefixMatch() {
        let html = #"<link rel="apple-touch-icon-precomposed" href="/at.png">"#
        #expect(IconResolver.linkHref(in: html, matchingRel: "apple-touch-icon", prefix: true) == "/at.png")
    }

    @Test("non-prefix does not match precomposed")
    func noPrefixNoMatch() {
        let html = #"<link rel="apple-touch-icon-precomposed" href="/at.png">"#
        #expect(IconResolver.linkHref(in: html, matchingRel: "apple-touch-icon") == nil)
    }
}

@Suite("IconResolver.largestSize")
struct LargestSizeTests {
    @Test("single dimension")
    func single() {
        #expect(IconResolver.largestSize(in: "180x180") == 180)
    }

    @Test("picks the biggest from a list")
    func list() {
        #expect(IconResolver.largestSize(in: "16x16 32x32 192x192") == 192)
    }

    @Test("nil for 'any' or empty")
    func anyOrEmpty() {
        #expect(IconResolver.largestSize(in: "any") == nil)
        #expect(IconResolver.largestSize(in: "") == nil)
        #expect(IconResolver.largestSize(in: nil) == nil)
    }
}

@Suite("IconResolver.bestIconLinkHref")
struct BestIconLinkTests {
    @Test("prefers the largest sized icon")
    func largestWins() {
        let html = """
        <link rel="icon" href="/16.png" sizes="16x16">
        <link rel="icon" href="/192.png" sizes="192x192">
        <link rel="icon" href="/32.png" sizes="32x32">
        """
        #expect(IconResolver.bestIconLinkHref(in: html) == "/192.png")
    }

    @Test("falls back to an unsized icon when none are sized")
    func unsizedFallback() {
        let html = #"<link rel="icon" href="/favicon.ico">"#
        #expect(IconResolver.bestIconLinkHref(in: html) == "/favicon.ico")
    }

    @Test("ignores non-icon rels")
    func ignoresNonIcon() {
        let html = #"<link rel="stylesheet" href="/x.css">"#
        #expect(IconResolver.bestIconLinkHref(in: html) == nil)
    }
}

@Suite("IconResolver.bestManifestIconHref")
struct ManifestIconTests {
    @Test("picks the largest icon, preferring PNG")
    func largestPng() {
        let json = """
        {"icons":[
          {"src":"/a-192.png","sizes":"192x192","type":"image/png"},
          {"src":"/a-512.png","sizes":"512x512","type":"image/png"},
          {"src":"/a-512.svg","sizes":"512x512","type":"image/svg+xml"}
        ]}
        """.data(using: .utf8)!
        #expect(IconResolver.bestManifestIconHref(fromManifestJSON: json) == "/a-512.png")
    }

    @Test("handles missing sizes/type")
    func missingFields() {
        let json = #"{"icons":[{"src":"/only.png"}]}"#.data(using: .utf8)!
        #expect(IconResolver.bestManifestIconHref(fromManifestJSON: json) == "/only.png")
    }

    @Test("nil for malformed JSON")
    func malformed() {
        #expect(IconResolver.bestManifestIconHref(fromManifestJSON: Data("not json".utf8)) == nil)
    }

    @Test("nil when icons array absent")
    func noIcons() {
        #expect(IconResolver.bestManifestIconHref(fromManifestJSON: Data(#"{"name":"x"}"#.utf8)) == nil)
    }
}

@Suite("IconResolver.resolveURL")
struct ResolveURLTests {
    let base = URL(string: "https://example.com/app/page")!

    @Test("absolute URL passes through")
    func absolute() {
        #expect(IconResolver.resolveURL("https://cdn.example.com/i.png", against: base)?.absoluteString
                == "https://cdn.example.com/i.png")
    }

    @Test("root-relative resolves against host")
    func rootRelative() {
        #expect(IconResolver.resolveURL("/icons/i.png", against: base)?.absoluteString
                == "https://example.com/icons/i.png")
    }

    @Test("protocol-relative inherits the scheme")
    func protocolRelative() {
        #expect(IconResolver.resolveURL("//cdn.example.com/i.png", against: base)?.absoluteString
                == "https://cdn.example.com/i.png")
    }

    @Test("empty href is nil")
    func empty() {
        #expect(IconResolver.resolveURL("   ", against: base) == nil)
    }
}

@Suite("IconResolver.resolve (full chain, mocked fetch)")
struct ResolveChainTests {
    /// Builds a resolver whose fetch returns canned bytes for specific URLs.
    private func resolver(site: String, responses: [String: Data]) -> IconResolver {
        IconResolver(siteURL: URL(string: site)!) { url in responses[url.absoluteString] }
    }

    @Test("manifest wins when present")
    func manifestWins() {
        let r = resolver(site: "https://example.com/", responses: [
            "https://example.com/": Data(#"<link rel="manifest" href="/m.json">"#.utf8),
            "https://example.com/m.json": Data(#"{"icons":[{"src":"/icon-512.png","sizes":"512x512","type":"image/png"}]}"#.utf8),
            "https://example.com/icon-512.png": Data("PNGBYTES".utf8),
        ])
        let resolved = r.resolve()
        #expect(resolved?.source == .manifest)
        #expect(resolved?.ext == "png")
        #expect(resolved?.data == Data("PNGBYTES".utf8))
    }

    @Test("falls through to apple-touch-icon when no manifest")
    func appleTouchFallback() {
        let r = resolver(site: "https://example.com/", responses: [
            "https://example.com/": Data(#"<link rel="apple-touch-icon" href="/at.png">"#.utf8),
            "https://example.com/at.png": Data("ATBYTES".utf8),
        ])
        let resolved = r.resolve()
        #expect(resolved?.source == .appleTouchIcon)
        #expect(resolved?.data == Data("ATBYTES".utf8))
    }

    @Test("falls through to favicon.ico when HTML has no icon links")
    func faviconIcoFallback() {
        let r = resolver(site: "https://example.com/", responses: [
            "https://example.com/": Data("<html><head></head></html>".utf8),
            "https://example.com/favicon.ico": Data("ICOBYTES".utf8),
        ])
        let resolved = r.resolve()
        #expect(resolved?.source == .faviconIco)
        #expect(resolved?.ext == "ico")
    }

    @Test("falls through to Google service as last resort")
    func googleFallback() {
        let r = resolver(site: "https://example.com/", responses: [
            "https://example.com/": Data("<html></html>".utf8),
            "https://www.google.com/s2/favicons?sz=256&domain=example.com": Data("GBYTES".utf8),
        ])
        let resolved = r.resolve()
        #expect(resolved?.source == .googleService)
    }

    @Test("returns nil when every source fails")
    func nothingFound() {
        let r = resolver(site: "https://example.com/", responses: [:])
        #expect(r.resolve() == nil)
    }
}
