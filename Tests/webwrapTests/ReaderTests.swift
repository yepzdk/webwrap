import XCTest
@testable import webwrap

// Tests for reader mode's pure core: decoding Readability's result, the reader page
// template, and the in-place replacement script. The live WebKit orchestration is
// hand-verified per repo convention.

final class ReaderDecodeTests: XCTestCase {
    func testDecodesFullArticle() {
        let json = """
        {"title":"A Title","byline":"By Someone","siteName":"The Site","content":"<p>Body</p>"}
        """
        XCTAssertEqual(Reader.decode(json),
                       Article(title: "A Title", byline: "By Someone",
                               siteName: "The Site", content: "<p>Body</p>"))
    }

    func testDecodesWithAbsentOptionals() {
        let article = Reader.decode(#"{"title":"T","content":"<p>x</p>"}"#)
        XCTAssertEqual(article?.title, "T")
        XCTAssertNil(article?.byline)
        XCTAssertNil(article?.siteName)
    }

    func testNilForNonArticleResults() {
        // The script returns null for non-readerable pages; WebKit may surface that
        // as nil or NSNull — and anything else unexpected must also decode to nil.
        XCTAssertNil(Reader.decode(nil))
        XCTAssertNil(Reader.decode(NSNull()))
        XCTAssertNil(Reader.decode(42))
        XCTAssertNil(Reader.decode(""))
        XCTAssertNil(Reader.decode("not json"))
        XCTAssertNil(Reader.decode(#"{"title":"missing content"}"#))
    }
}

final class ReaderExtractionScriptTests: XCTestCase {
    func testContainsVendoredSourcesAndGate() {
        let script = Reader.extractionScript
        // Both vendored libraries are inlined, and the cheap gate runs before parse.
        XCTAssertTrue(script.contains("function Readability("))
        XCTAssertTrue(script.contains("function isProbablyReaderable("))
        XCTAssertTrue(script.contains("isProbablyReaderable(document)"))
        // Parse must run on a clone — Readability's parse is destructive.
        XCTAssertTrue(script.contains("document.cloneNode(true)"))
    }
}

final class ReaderPageTests: XCTestCase {
    private let article = Article(title: "Tips & Tricks <2026>", byline: "By A & B",
                                  siteName: "News <Site>", content: "<p>Hello <em>world</em></p>")

    func testEscapesTitleAndMetaButNotContent() {
        let html = ReaderPage.html(article: article, backgroundColor: nil)
        XCTAssertTrue(html.contains("Tips &amp; Tricks &lt;2026&gt;"))
        XCTAssertTrue(html.contains("By A &amp; B · News &lt;Site&gt;"))
        // The Readability-cleaned body HTML is inserted verbatim.
        XCTAssertTrue(html.contains("<p>Hello <em>world</em></p>"))
    }

    func testMetaLineOmittedWhenAbsent() {
        let bare = Article(title: "T", byline: nil, siteName: nil, content: "<p>x</p>")
        XCTAssertFalse(ReaderPage.html(article: bare, backgroundColor: nil)
            .contains("class=\"meta\""))
    }

    func testBackgroundGating() {
        // Same rule as StartPage/OfflineFallback: hex applies, garbage falls back to
        // the appearance-following variable.
        XCTAssertTrue(ReaderPage.html(article: article, backgroundColor: "#1a73e8")
            .contains("background: #1a73e8;"))
        let injected = ReaderPage.html(article: article,
                                       backgroundColor: "red; } body { display:none")
        XCTAssertTrue(injected.contains("background: var(--bg);"))
        XCTAssertFalse(injected.contains("display:none"))
    }

    func testIsAnInnerDocumentFragment() {
        // documentElement.innerHTML accepts head+body, not a doctype/<html> wrapper.
        let html = ReaderPage.html(article: article, backgroundColor: nil)
        XCTAssertFalse(html.contains("<!doctype"))
        XCTAssertFalse(html.contains("<html"))
        XCTAssertTrue(html.hasPrefix("<head>"))
        XCTAssertTrue(html.hasSuffix("</body>"))
    }

    func testReplacementScriptEmbedsHTMLJSONSafely() throws {
        // Quotes, newlines, and unicode must survive the trip into a JS literal.
        let tricky = "<p>\"quoted\"\nline två \\ backslash</p>"
        let script = try XCTUnwrap(ReaderPage.replacementScript(html: tricky))
        XCTAssertTrue(script.contains("document.documentElement.innerHTML"))
        // The embedded JSON round-trips back to the original string. The literal sits
        // between the wrapping "(" and the ")[0]" unwrap.
        let start = try XCTUnwrap(script.range(of: "(")).upperBound
        let end = try XCTUnwrap(script.range(of: ")[0]")).lowerBound
        let json = String(script[start..<end])
        let decoded = try JSONDecoder().decode([String].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, [tricky])
    }
}
