import Foundation

/// Reader mode's pure core: extracting an article from a page and rendering it as a
/// clean, distraction-free page. Everything here is string/JSON work — unit-tested;
/// the WebKit orchestration (when to extract, applying the result) lives in the host.

/// An article extracted by Readability, decoded from its `parse()` result.
struct Article: Decodable, Equatable {
    let title: String
    let byline: String?
    let siteName: String?
    /// The Readability-cleaned article body HTML (`<script>` is stripped upstream).
    let content: String
}

enum Reader {
    /// The script the host evaluates on a loaded page. Gates on the cheap
    /// `isProbablyReaderable` check, parses a CLONE of the document (Readability's
    /// parse is destructive), and returns the article as a JSON string — or `null`
    /// when the page isn't an article. The IIFE keeps the vendored sources out of
    /// the page's global scope.
    static var extractionScript: String {
        """
        (function() {
        \(ReadabilityJS.readability)
        \(ReadabilityJS.readerable)
        if (!isProbablyReaderable(document)) { return null; }
        var article = new Readability(document.cloneNode(true)).parse();
        if (!article || !article.content) { return null; }
        return JSON.stringify({
          title: article.title || document.title || "",
          byline: article.byline,
          siteName: article.siteName,
          content: article.content
        });
        })()
        """
    }

    /// Decodes an `evaluateJavaScript` result into an `Article`. The script returns
    /// a JSON string or null, but be tolerant of anything else WebKit hands back —
    /// nil means "no article", never an error.
    static func decode(_ jsResult: Any?) -> Article? {
        guard let json = jsResult as? String, !json.isEmpty else { return nil }
        return try? JSONDecoder().decode(Article.self, from: Data(json.utf8))
    }
}

/// Renders an extracted article as the reader page, and swaps it into the live
/// document. Shares the `--bg` light/dark pattern (and background-color gating) with
/// `StartPage`/`OfflineFallback`.
enum ReaderPage {
    /// The reader document as a `<head>…</head><body>…</body>` fragment — exactly
    /// what `document.documentElement.innerHTML` accepts (a doctype/`<html>` wrapper
    /// would be dropped anyway). Title and byline/site are escaped; `article.content`
    /// is inserted as-is (it's the Readability-cleaned HTML of the page the user was
    /// already viewing).
    static func html(article: Article, backgroundColor: String?) -> String {
        let title = OfflineFallback.escape(article.title)
        // Byline and site name merge into one muted meta line; either may be absent.
        let meta = [article.byline, article.siteName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(OfflineFallback.escape)
            .joined(separator: " · ")
        let metaLine = meta.isEmpty ? "" : "<p class=\"meta\">\(meta)</p>"
        let bgRule: String
        if let backgroundColor, CSSColor.parse(backgroundColor) != nil {
            bgRule = "background: \(backgroundColor);"
        } else {
            bgRule = "background: var(--bg);"
        }
        return """
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(title)</title>
        <style>
          :root {
            --bg: #fafafa; --fg: #1c1c1e; --muted: #6b6b70; --accent: #2563eb;
            --border: rgba(0,0,0,0.12); --surface: rgba(0,0,0,0.05);
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --bg: #1c1c1e; --fg: #f2f2f7; --muted: #9a9aa0; --accent: #3b82f6;
              --border: rgba(255,255,255,0.16); --surface: rgba(255,255,255,0.08);
            }
          }
          * { box-sizing: border-box; }
          html, body { margin: 0; }
          body {
            \(bgRule)
            color: var(--fg);
            font: 17px/1.6 ui-serif, "New York", Georgia, serif;
            -webkit-font-smoothing: antialiased;
          }
          main { max-width: 42rem; margin: 0 auto; padding: 48px 24px 96px; }
          header { margin-bottom: 40px; padding-bottom: 20px; border-bottom: 1px solid var(--border); }
          h1 { font-size: 28px; line-height: 1.25; letter-spacing: -0.01em; margin: 0; }
          .meta {
            color: var(--muted); margin: 10px 0 0;
            font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
          }
          article h2 { font-size: 22px; line-height: 1.3; margin: 1.6em 0 0.6em; }
          article h3 { font-size: 19px; line-height: 1.3; margin: 1.4em 0 0.5em; }
          article p { margin: 0 0 1.2em; }
          article a { color: var(--accent); }
          article img, article video { max-width: 100%; height: auto; }
          article figure { margin: 28px 0; }
          article figcaption {
            color: var(--muted); font-size: 13px; margin-top: 8px;
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
          }
          article blockquote {
            margin: 24px 0; padding-left: 16px;
            border-left: 3px solid var(--border); color: var(--muted);
          }
          article pre {
            overflow-x: auto; background: var(--surface);
            padding: 12px 14px; border-radius: 6px; font-size: 14px;
          }
          article code { font-family: ui-monospace, Menlo, monospace; font-size: 0.9em; }
          article table { display: block; overflow-x: auto; border-collapse: collapse; }
          article td, article th { border: 1px solid var(--border); padding: 6px 10px; }
          article hr { border: 0; border-top: 1px solid var(--border); margin: 32px 0; }
        </style>
        </head>
        <body>
          <main>
            <header>
              <h1>\(title)</h1>
              \(metaLine)
            </header>
            <article>\(article.content)</article>
          </main>
        </body>
        """
    }

    /// JS that swaps `html` into the live document in place — no navigation, so
    /// history stays clean and the article's relative URLs keep resolving against
    /// the original document URL. The HTML rides in as a JSON string literal, which
    /// survives any quotes/newlines/unicode it contains. Nil only if JSON encoding
    /// fails (practically never for a String).
    ///
    /// ponytail: the original page's already-running JS isn't torn down — timers may
    /// keep firing harmlessly against the replaced DOM. A separate about:reader-style
    /// document is the upgrade path if a site ever misbehaves.
    static func replacementScript(html: String) -> String? {
        // Encoded as a one-element array (JSONEncoder wants a top-level container);
        // [0] unwraps it in JS.
        guard let data = try? JSONEncoder().encode([html]),
              let literal = String(data: data, encoding: .utf8) else { return nil }
        return "document.documentElement.innerHTML = (\(literal))[0]; window.scrollTo(0, 0);"
    }
}
