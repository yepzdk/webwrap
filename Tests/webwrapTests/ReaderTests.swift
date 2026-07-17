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

final class ReaderSettingsTests: XCTestCase {
    func testDecodesFullPayload() {
        let payload: [String: Any] = ["fontSize": 21, "fontFamily": "sans", "width": "wide",
                                      "lineHeight": "relaxed", "theme": "sepia"]
        let settings = ReaderSettings.decode(payload)
        XCTAssertEqual(settings.fontSize, 21)
        XCTAssertEqual(settings.fontFamily, .sans)
        XCTAssertEqual(settings.width, .wide)
        XCTAssertEqual(settings.lineHeight, .relaxed)
        XCTAssertEqual(settings.theme, .sepia)
    }

    func testPartialAndUnknownFieldsFallBackToDefaults() {
        // A payload only naming some fields (or naming unknown values) keeps the
        // defaults for the rest — a garbled popover message can't poison the reader.
        let settings = ReaderSettings.decode(["theme": "black", "width": "ultrawide",
                                              "fontFamily": 7])
        XCTAssertEqual(settings.theme, .black)
        XCTAssertEqual(settings.width, .normal)
        XCTAssertEqual(settings.fontFamily, .serif)
        XCTAssertEqual(settings.fontSize, 17)
    }

    func testGarbageDecodesToDefaults() {
        XCTAssertEqual(ReaderSettings.decode(nil), ReaderSettings())
        XCTAssertEqual(ReaderSettings.decode("not a dict"), ReaderSettings())
        XCTAssertEqual(ReaderSettings.decode(NSNull()), ReaderSettings())
        XCTAssertEqual(ReaderSettings.fromJSON(nil), ReaderSettings())
        XCTAssertEqual(ReaderSettings.fromJSON("not json"), ReaderSettings())
    }

    func testFontSizeIsClamped() {
        XCTAssertEqual(ReaderSettings.decode(["fontSize": 6]).fontSize,
                       ReaderSettings.fontSizeRange.lowerBound)
        XCTAssertEqual(ReaderSettings.decode(["fontSize": 90]).fontSize,
                       ReaderSettings.fontSizeRange.upperBound)
    }

    func testJSONRoundTrip() {
        var settings = ReaderSettings()
        settings.fontSize = 14
        settings.fontFamily = .sans
        settings.width = .narrow
        settings.lineHeight = .compact
        settings.theme = .dark
        XCTAssertEqual(ReaderSettings.fromJSON(settings.json), settings)
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

    func testDefaultSettingsBakeStockDesign() {
        let html = ReaderPage.html(article: article, backgroundColor: nil)
        XCTAssertTrue(html.contains("--reader-size: 17px;"))
        XCTAssertTrue(html.contains("--reader-leading: 1.6;"))
        XCTAssertTrue(html.contains("--reader-width: 42rem;"))
        XCTAssertTrue(html.contains("--reader-font: ui-serif, \"New York\", Georgia, serif;"))
        // Auto theme = no data-theme attribute, appearance follows the system.
        XCTAssertTrue(html.contains("<html lang=\"en\">"))
    }

    func testSettingsAreBakedIntoVarsAndTheme() {
        var settings = ReaderSettings()
        settings.fontSize = 22
        settings.fontFamily = .sans
        settings.width = .wide
        settings.lineHeight = .relaxed
        settings.theme = .sepia
        let html = ReaderPage.html(article: article, settings: settings, backgroundColor: nil)
        XCTAssertTrue(html.contains("<html lang=\"en\" data-theme=\"sepia\">"))
        XCTAssertTrue(html.contains("--reader-size: 22px;"))
        XCTAssertTrue(html.contains("--reader-leading: 1.8;"))
        XCTAssertTrue(html.contains("--reader-width: 52rem;"))
        XCTAssertTrue(html.contains("--reader-font: -apple-system,"))
        // The popover script is seeded with the same settings it renders.
        XCTAssertTrue(html.contains(settings.json))
    }

    func testExplicitThemeOverridesBakedBackground() {
        // A baked background color still applies in auto theme, but the rule that pins
        // explicit themes to their palette must be present so it wins when set.
        var settings = ReaderSettings()
        settings.theme = .black
        let html = ReaderPage.html(article: article, settings: settings,
                                   backgroundColor: "#1a73e8")
        XCTAssertTrue(html.contains("background: #1a73e8;"))
        XCTAssertTrue(html.contains(":root[data-theme] body { background: var(--bg); }"))
        XCTAssertTrue(html.contains("data-theme=\"black\""))
    }

    func testContainsAppearancePopoverAndBridge() {
        let html = ReaderPage.html(article: article, backgroundColor: nil)
        XCTAssertTrue(html.contains("id=\"readerAa\""))
        XCTAssertTrue(html.contains("messageHandlers.webwrapReader.postMessage"))
        // Every adjustable value has a control.
        for value in ["serif", "sans", "narrow", "normal", "wide",
                      "compact", "relaxed", "auto", "light", "sepia", "dark", "black"] {
            XCTAssertTrue(html.contains("data-value=\"\(value)\""), value)
        }
    }

    func testIsACompleteStandaloneDocument() {
        // Loaded via loadHTMLString as its own document — the doctype keeps WebKit in
        // standards mode (see #76 for why the reader must be a separate document).
        let html = ReaderPage.html(article: article, backgroundColor: nil)
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("<html lang=\"en\">"))
        XCTAssertTrue(html.hasSuffix("</html>"))
    }
}
