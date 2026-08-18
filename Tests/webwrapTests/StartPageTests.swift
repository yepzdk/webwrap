import XCTest
@testable import webwrap

// Tests for the handler-only start page's pure HTML generation. Mirrors the
// OfflineFallback tests: escaping and the CSSColor-gated background rule.

final class StartPageTests: XCTestCase {
    func testContainsEscapedAppName() {
        let html = StartPage.html(appName: "Read & Relax <x>", backgroundColor: nil)
        XCTAssertTrue(html.contains("Read &amp; Relax &lt;x&gt;"))
        XCTAssertFalse(html.contains("Read & Relax <x>"))
    }

    func testDefaultBackgroundFollowsAppearance() {
        // No manifest color → the light/dark-switching variable, not a fixed color.
        let html = StartPage.html(appName: "Reader", backgroundColor: nil)
        XCTAssertTrue(html.contains("background: var(--bg);"))
    }

    func testParseableBackgroundColorIsApplied() {
        let html = StartPage.html(appName: "Reader", backgroundColor: "#1a73e8")
        XCTAssertTrue(html.contains("background: #1a73e8;"))
    }

    func testUnparseableBackgroundColorIsIgnored() {
        // A non-hex value could break out of the CSS declaration — must be dropped.
        let html = StartPage.html(appName: "Reader",
                                  backgroundColor: "red; } .card { display:none")
        XCTAssertTrue(html.contains("background: var(--bg);"))
        XCTAssertFalse(html.contains("display:none"))
    }

    // MARK: - URL entry

    func testOffersURLEntryAndTheShortcutHint() {
        let html = StartPage.html(appName: "Reader", backgroundColor: nil)
        XCTAssertTrue(html.contains("id=\"url\""))
        XCTAssertTrue(html.contains("placeholder=\"Paste or type a URL\""))
        XCTAssertTrue(html.contains("<button type=\"submit\">Open</button>"))
        // The keyboard path is taught, not just the button.
        XCTAssertTrue(html.contains("<kbd>⇧⌘O</kbd>"))
        XCTAssertTrue(html.contains("messageHandlers.webwrapOpenURL.postMessage"))
        // Autofocused so a paste-and-return needs no click.
        XCTAssertTrue(html.contains("autofocus"))
    }

    func testHasAnInlineRejectionMessageHookedToTheHost() {
        // A beep alone is invisible when the user is looking at the field they typed into.
        let html = StartPage.html(appName: "Reader", backgroundColor: nil)
        XCTAssertTrue(html.contains("id=\"error\""))
        XCTAssertTrue(html.contains("role=\"alert\""))
        XCTAssertTrue(html.contains("window.webwrapURLRejected"))
    }

    // MARK: - Recents

    func testListsRecentsInlineNewestFirst() {
        var history = ReaderHistory()
        history.record(title: "Older piece", url: "https://news.example.com/older")
        history.record(title: "Newest piece", url: "https://blog.example.com/new")
        let html = StartPage.html(appName: "Reader", history: history, backgroundColor: nil)
        XCTAssertTrue(html.contains("class=\"recents-inline\""))
        XCTAssertTrue(html.contains("data-url=\"https://blog.example.com/new\""))
        XCTAssertTrue(html.contains("blog.example.com"))
        let newest = html.range(of: "Newest piece")
        let oldest = html.range(of: "Older piece")
        XCTAssertNotNil(newest)
        XCTAssertNotNil(oldest)
        XCTAssertTrue(newest!.lowerBound < oldest!.lowerBound)
    }

    func testRecentTitlesAreEscaped() {
        var history = ReaderHistory()
        history.record(title: "Tips & <script>", url: "https://x.test/a\" onclick=\"alert(1)")
        let html = StartPage.html(appName: "Reader", history: history, backgroundColor: nil)
        XCTAssertTrue(html.contains("Tips &amp; &lt;script&gt;"))
        XCTAssertFalse(html.contains("onclick=\"alert(1)\""))
    }

    func testEmptyHistoryKeepsTheRoutingExplanation() {
        // A first-run app genuinely has nothing to list, so it still explains how to
        // get links in rather than showing a bare empty box.
        let html = StartPage.html(appName: "Reader", backgroundColor: nil)
        XCTAssertTrue(html.contains("No articles yet"))
        XCTAssertTrue(html.contains("Choosy"))
        XCTAssertFalse(html.contains("class=\"recents-inline\""))
    }

    // MARK: - Shared chrome

    func testCarriesTheSameChromeAsTheReader() {
        var history = ReaderHistory()
        history.record(title: "Something", url: "https://x.test/s")
        let html = StartPage.html(appName: "Reader", history: history, backgroundColor: nil)
        // Appearance popover and recents popover, both from ReaderChrome.
        XCTAssertTrue(html.contains("id=\"readerAa\""))
        XCTAssertTrue(html.contains("id=\"readerRecentsBtn\""))
        XCTAssertTrue(html.contains("messageHandlers.webwrapReader.postMessage"))
        XCTAssertTrue(html.contains("messageHandlers.webwrapReaderOpen.postMessage"))
    }

    func testBakedReaderSettingsDriveThePage() {
        var settings = ReaderSettings()
        settings.fontSize = 22
        settings.theme = .sepia
        let html = StartPage.html(appName: "Reader", settings: settings, backgroundColor: nil)
        XCTAssertTrue(html.contains("<html lang=\"en\" data-theme=\"sepia\">"))
        XCTAssertTrue(html.contains("--reader-size: 22px;"))
        // The script is seeded with the same settings it renders.
        XCTAssertTrue(html.contains(settings.json))
    }

    func testExplicitThemeOverridesBakedBackground() {
        var settings = ReaderSettings()
        settings.theme = .black
        let html = StartPage.html(appName: "Reader", settings: settings,
                                  backgroundColor: "#1a73e8")
        XCTAssertTrue(html.contains(":root[data-theme] body { background: var(--bg); }"))
    }

    func testIsACompleteStandaloneDocument() {
        let html = StartPage.html(appName: "Reader", backgroundColor: nil)
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.hasSuffix("</html>"))
    }

    func testHasNoReadingProgressBar() {
        // Reading progress belongs to a long article (#93); this page has no such content,
        // and the shared appearance script must not assume the hook exists here.
        var history = ReaderHistory()
        history.record(title: "Something", url: "https://x.test/s")
        let html = StartPage.html(appName: "Reader", history: history, backgroundColor: nil)
        XCTAssertFalse(html.contains("id=\"readerProgress\""))
        XCTAssertFalse(html.contains("window.webwrapOnLayoutChange = measure"))
        // The guarded call is still present (it's in the shared script) but must be a no-op.
        XCTAssertTrue(html.contains("if (window.webwrapOnLayoutChange)"))
    }
}
