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

/// The reader's appearance settings, adjustable from the in-reader "Aa" popover and
/// persisted per app. Plain persisted state like page zoom — there is no baked plist
/// default to layer over. Pure so decoding/encoding is unit-testable.
struct ReaderSettings: Equatable {
    enum FontFamily: String, CaseIterable {
        case serif, sans
        /// The CSS font stack. The serif stack matches the reader's original design;
        /// sans matches the meta-line stack used elsewhere in the generated pages.
        var css: String {
            switch self {
            case .serif: return "ui-serif, \"New York\", Georgia, serif"
            case .sans: return "-apple-system, BlinkMacSystemFont, \"Helvetica Neue\", Arial, sans-serif"
            }
        }
    }

    enum Width: String, CaseIterable {
        case narrow, normal, wide
        var css: String {
            switch self {
            case .narrow: return "36rem"
            case .normal: return "42rem"
            case .wide: return "52rem"
            }
        }
    }

    enum LineHeight: String, CaseIterable {
        case compact, normal, relaxed
        var css: String {
            switch self {
            case .compact: return "1.4"
            case .normal: return "1.6"
            case .relaxed: return "1.8"
            }
        }
    }

    /// `auto` follows the system light/dark appearance (the original behavior); the
    /// explicit themes pin a palette regardless of system appearance.
    enum Theme: String, CaseIterable {
        case auto, light, sepia, dark, black
    }

    var fontSize = 17
    var fontFamily = FontFamily.serif
    var width = Width.normal
    var lineHeight = LineHeight.normal
    var theme = Theme.auto

    static let fontSizeRange = 12...28

    /// Tolerant decode of a settings payload — a `WKScriptMessage.body` dictionary or
    /// a `JSONSerialization` object. Missing/unknown fields keep their defaults and
    /// the font size is clamped, so a garbled payload can never poison the reader.
    static func decode(_ value: Any?) -> ReaderSettings {
        guard let dict = value as? [String: Any] else { return ReaderSettings() }
        var settings = ReaderSettings()
        if let size = dict["fontSize"] as? Int {
            settings.fontSize = min(max(size, fontSizeRange.lowerBound), fontSizeRange.upperBound)
        }
        if let raw = dict["fontFamily"] as? String, let value = FontFamily(rawValue: raw) {
            settings.fontFamily = value
        }
        if let raw = dict["width"] as? String, let value = Width(rawValue: raw) {
            settings.width = value
        }
        if let raw = dict["lineHeight"] as? String, let value = LineHeight(rawValue: raw) {
            settings.lineHeight = value
        }
        if let raw = dict["theme"] as? String, let value = Theme(rawValue: raw) {
            settings.theme = value
        }
        return settings
    }

    /// The settings as a JSON string — the storage format, and (JSON being valid JS)
    /// what the reader page's script is seeded with.
    var json: String {
        let dict: [String: Any] = [
            "fontSize": fontSize,
            "fontFamily": fontFamily.rawValue,
            "width": width.rawValue,
            "lineHeight": lineHeight.rawValue,
            "theme": theme.rawValue,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Decodes stored JSON, with the same tolerance as `decode` — nil/garbage means
    /// defaults, never an error.
    static func fromJSON(_ string: String?) -> ReaderSettings {
        guard let string, let data = string.data(using: .utf8) else { return ReaderSettings() }
        return decode(try? JSONSerialization.jsonObject(with: data))
    }
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
    /// The complete reader document, loaded by the host as its OWN document via
    /// `loadHTMLString(_:baseURL:)` with the article URL as base — so relative image
    /// URLs keep resolving, and the article page's still-running JS dies with its
    /// document. (An in-place DOM swap was reverted within a second on hydrating
    /// sites — React re-rendering after `didFinish` — see #76.) Title and byline/site
    /// are escaped; `article.content` is inserted as-is (it's the Readability-cleaned
    /// HTML of the page the user was already viewing).
    ///
    /// Appearance is driven by `settings`, baked in as CSS custom properties plus a
    /// `data-theme` attribute; the in-page "Aa" popover adjusts the same properties
    /// live and posts the new settings to the host (`webwrapReader`) for persistence.
    ///
    /// `history` is the recents list, baked into a sibling popover; its rows post the
    /// chosen URL to the host (`webwrapReaderOpen`), which validates and navigates.
    /// Titles are escaped there too — they come from other sites' pages.
    static func html(article: Article,
                     settings: ReaderSettings = ReaderSettings(),
                     history: ReaderHistory = ReaderHistory(),
                     backgroundColor: String?) -> String {
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
        // The theme attribute is only present for explicit themes; `auto` keeps the
        // media-query behavior (and the baked background color) below.
        let themeAttr = settings.theme == .auto ? "" : " data-theme=\"\(settings.theme.rawValue)\""
        let sans = ReaderSettings.FontFamily.sans.css
        let serif = ReaderSettings.FontFamily.serif.css
        // Recents rows are built here rather than by the page script so titles and URLs
        // (other sites' content) run through the same escaping as the article title.
        // The URL lives in a data attribute; the host re-validates it before navigating.
        let recentRows = history.entries.map { entry in
            let host = URL(string: entry.url)?.host ?? ""
            let hostLine = host.isEmpty ? ""
                : "<span class=\"recent-host\">\(OfflineFallback.escape(host))</span>"
            return """
            <button class="recent" data-url="\(OfflineFallback.escape(entry.url))">\
            <span class="recent-title">\(OfflineFallback.escape(entry.title))</span>\(hostLine)</button>
            """
        }.joined(separator: "\n                ")
        // The clear action only appears when there's something to clear.
        let recentsBody = history.entries.isEmpty
            ? "<p class=\"recent-empty\">No recent articles</p>"
            : recentRows + "\n                <button id=\"readerClear\">Clear history</button>"
        return """
        <!doctype html>
        <html lang="en"\(themeAttr)>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(title)</title>
        <style>
          :root {
            --bg: #fafafa; --fg: #1c1c1e; --muted: #6b6b70; --accent: #2563eb;
            --border: rgba(0,0,0,0.12); --surface: rgba(0,0,0,0.05);
            --reader-size: \(settings.fontSize)px;
            --reader-leading: \(settings.lineHeight.css);
            --reader-width: \(settings.width.css);
            --reader-font: \(settings.fontFamily.css);
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --bg: #1c1c1e; --fg: #f2f2f7; --muted: #9a9aa0; --accent: #3b82f6;
              --border: rgba(255,255,255,0.16); --surface: rgba(255,255,255,0.08);
            }
          }
          /* Explicit themes pin a palette; the attribute selector outranks both the
             light defaults and the dark media query above. */
          :root[data-theme="light"] {
            --bg: #fafafa; --fg: #1c1c1e; --muted: #6b6b70; --accent: #2563eb;
            --border: rgba(0,0,0,0.12); --surface: rgba(0,0,0,0.05);
            color-scheme: light;
          }
          :root[data-theme="sepia"] {
            --bg: #f4ecd8; --fg: #3d3225; --muted: #6f6049; --accent: #2563eb;
            --border: rgba(61,50,37,0.18); --surface: rgba(61,50,37,0.07);
            color-scheme: light;
          }
          :root[data-theme="dark"] {
            --bg: #1c1c1e; --fg: #f2f2f7; --muted: #9a9aa0; --accent: #3b82f6;
            --border: rgba(255,255,255,0.16); --surface: rgba(255,255,255,0.08);
            color-scheme: dark;
          }
          :root[data-theme="black"] {
            --bg: #000000; --fg: #f2f2f7; --muted: #98989e; --accent: #3b82f6;
            --border: rgba(255,255,255,0.18); --surface: rgba(255,255,255,0.10);
            color-scheme: dark;
          }
          * { box-sizing: border-box; }
          html, body { margin: 0; }
          body {
            \(bgRule)
            color: var(--fg);
            font-family: var(--reader-font);
            font-size: var(--reader-size);
            line-height: var(--reader-leading);
            -webkit-font-smoothing: antialiased;
          }
          /* An explicit theme wins over any baked background color. */
          :root[data-theme] body { background: var(--bg); }
          main { max-width: var(--reader-width); margin: 0 auto; padding: 48px 24px 96px; }
          header { margin-bottom: 40px; padding-bottom: 20px; border-bottom: 1px solid var(--border); }
          h1 { font-size: 1.65em; line-height: 1.25; letter-spacing: -0.01em; margin: 0; }
          .meta {
            color: var(--muted); margin: 10px 0 0;
            font: 0.82em/1.5 \(sans);
          }
          article h2 { font-size: 1.3em; line-height: 1.3; margin: 1.6em 0 0.6em; }
          article h3 { font-size: 1.12em; line-height: 1.3; margin: 1.4em 0 0.5em; }
          article p { margin: 0 0 1.2em; }
          article a { color: var(--accent); }
          article img, article video { max-width: 100%; height: auto; }
          article figure { margin: 28px 0; }
          article figcaption {
            color: var(--muted); font-size: 0.76em; margin-top: 8px;
            font-family: \(sans);
          }
          article blockquote {
            margin: 24px 0; padding-left: 16px;
            border-left: 3px solid var(--border); color: var(--muted);
          }
          article pre {
            overflow-x: auto; background: var(--surface);
            padding: 12px 14px; border-radius: 6px; font-size: 0.82em;
          }
          article code { font-family: ui-monospace, Menlo, monospace; font-size: 0.9em; }
          article table { display: block; overflow-x: auto; border-collapse: collapse; }
          article td, article th { border: 1px solid var(--border); padding: 6px 10px; }
          article hr { border: 0; border-top: 1px solid var(--border); margin: 32px 0; }
          /* Appearance ("Aa") popover. Chrome UI, so it keeps the sans stack and fixed
             sizes regardless of the reading settings. */
          .reader-controls {
            position: fixed; top: 14px; right: 14px; z-index: 10;
            display: flex; gap: 6px;
            font-family: \(sans); font-size: 12px; line-height: 1.3;
          }
          /* Each button owns the popover anchored under it. */
          .reader-control { position: relative; }
          #readerAa, #readerRecentsBtn {
            padding: 4px 10px; font-family: inherit; font-size: 14px;
            color: var(--muted); background: var(--bg);
            border: 1px solid var(--border); border-radius: 6px; cursor: pointer;
          }
          #readerAa:hover, #readerAa[aria-expanded="true"],
          #readerRecentsBtn:hover, #readerRecentsBtn[aria-expanded="true"] { color: var(--fg); }
          /* The icon button matches the "Aa" button's box; the SVG inherits currentColor. */
          #readerRecentsBtn { display: flex; align-items: center; padding: 5px 9px; }
          #readerRecentsBtn svg { display: block; }
          #readerPanel, #readerRecents {
            position: absolute; top: calc(100% + 8px); right: 0; width: 240px;
            padding: 12px; background: var(--bg);
            border: 1px solid var(--border); border-radius: 8px;
            box-shadow: 0 4px 16px rgba(0,0,0,0.12);
            display: flex; flex-direction: column; gap: 10px;
          }
          #readerPanel[hidden], #readerRecents[hidden] { display: none; }
          /* Recents: a plain list of titles. Padding is on the rows, so the panel itself
             sheds its gap and lets a long list scroll instead of running off-screen. */
          /* Right-anchored like the Aa panel: the controls sit at the window's right edge,
             so the panel has to hang leftward to stay on screen. `max-width` keeps it from
             running off the LEFT edge on a narrow window. */
          #readerRecents {
            width: 280px; max-width: calc(100vw - 28px);
            padding: 6px; gap: 0; max-height: 60vh; overflow-y: auto;
          }
          .recent {
            display: block; width: 100%; padding: 7px 8px; border: 0; border-radius: 5px;
            background: transparent; cursor: pointer; text-align: left;
            font-family: inherit; font-size: 12px; color: var(--fg);
          }
          .recent:hover { background: var(--surface); }
          .recent-title {
            display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
          }
          .recent-host { display: block; margin-top: 2px; font-size: 11px; color: var(--muted); }
          .recent-empty { margin: 0; padding: 7px 8px; color: var(--muted); }
          /* Clearing history lives next to the history itself — Restore Defaults is for
             presentation settings and deliberately leaves user data alone. */
          #readerClear {
            margin: 4px 6px 2px; padding: 6px 8px; border: 0; border-top: 1px solid var(--border);
            border-radius: 0; background: transparent; cursor: pointer; text-align: left;
            font-family: inherit; font-size: 11px; color: var(--muted);
          }
          #readerClear:hover { color: var(--fg); }
          .seg { display: flex; border: 1px solid var(--border); border-radius: 6px; overflow: hidden; }
          .seg button {
            flex: 1; padding: 7px 0; border: 0; background: transparent; cursor: pointer;
            font-family: inherit; font-size: 12px; color: var(--muted);
          }
          .seg button + button { border-left: 1px solid var(--border); }
          .seg button[aria-pressed="true"] { background: var(--surface); color: var(--fg); }
          .seg button:disabled { opacity: 0.4; cursor: default; }
          .seg button[data-value="serif"] { font-family: \(serif); }
          .a-small { font-size: 12px; }
          .a-large { font-size: 17px; }
          .themes { display: flex; justify-content: space-between; padding: 2px; }
          .swatch {
            width: 26px; height: 26px; border-radius: 50%; cursor: pointer;
            border: 1px solid var(--border); padding: 0;
          }
          .swatch[aria-pressed="true"] { box-shadow: 0 0 0 2px var(--bg), 0 0 0 4px var(--accent); }
          .swatch-auto { background: linear-gradient(135deg, #fafafa 50%, #1c1c1e 50%); }
          .swatch-light { background: #fafafa; }
          .swatch-sepia { background: #f4ecd8; }
          .swatch-dark { background: #1c1c1e; }
          .swatch-black { background: #000000; }
          /* Popover headings — the popovers are opened from unlabelled icon buttons, so
             each one names itself once opened. */
          .panel-title {
            margin: 0; padding: 2px 2px 8px; border-bottom: 1px solid var(--border);
            font-size: 11px; font-weight: 600; letter-spacing: 0.04em;
            text-transform: uppercase; color: var(--muted);
          }
          /* The recents panel puts padding on its rows, so its heading carries its own. */
          #readerRecents .panel-title { margin: 2px 6px 4px; padding: 2px 2px 8px; }
        </style>
        </head>
        <body>
          <div class="reader-controls">
            <div class="reader-control">
              <button id="readerRecentsBtn" aria-label="Recent articles"
                      title="Recent articles" aria-haspopup="true"
                      aria-expanded="false" aria-controls="readerRecents">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                     stroke-width="2" stroke-linecap="round" aria-hidden="true">
                  <path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>
                </svg>
              </button>
              <div id="readerRecents" hidden aria-labelledby="readerRecentsTitle">
                <h2 class="panel-title" id="readerRecentsTitle">Recent articles</h2>
                \(recentsBody)
              </div>
            </div>
            <div class="reader-control">
              <button id="readerAa" aria-label="Reader appearance"
                      title="Text &amp; appearance" aria-haspopup="true"
                      aria-expanded="false" aria-controls="readerPanel">Aa</button>
              <div id="readerPanel" hidden aria-labelledby="readerPanelTitle">
                <h2 class="panel-title" id="readerPanelTitle">Text &amp; appearance</h2>
                <div class="seg" role="group" aria-label="Font size">
                  <button data-step="-1" aria-label="Decrease font size"
                          title="Smaller text"><span class="a-small">A</span></button>
                  <button data-step="1" aria-label="Increase font size"
                          title="Larger text"><span class="a-large">A</span></button>
                </div>
                <div class="seg" role="group" aria-label="Font style">
                  <button data-key="fontFamily" data-value="serif">Serif</button>
                  <button data-key="fontFamily" data-value="sans">Sans</button>
                </div>
                <div class="seg" role="group" aria-label="Column width">
                  <button data-key="width" data-value="narrow">Narrow</button>
                  <button data-key="width" data-value="normal">Normal</button>
                  <button data-key="width" data-value="wide">Wide</button>
                </div>
                <div class="seg" role="group" aria-label="Line height">
                  <button data-key="lineHeight" data-value="compact">Compact</button>
                  <button data-key="lineHeight" data-value="normal">Normal</button>
                  <button data-key="lineHeight" data-value="relaxed">Relaxed</button>
                </div>
                <div class="themes" role="group" aria-label="Theme">
                  <button class="swatch swatch-auto" data-key="theme" data-value="auto" aria-label="Auto theme" title="Auto"></button>
                  <button class="swatch swatch-light" data-key="theme" data-value="light" aria-label="Light theme" title="Light"></button>
                  <button class="swatch swatch-sepia" data-key="theme" data-value="sepia" aria-label="Sepia theme" title="Sepia"></button>
                  <button class="swatch swatch-dark" data-key="theme" data-value="dark" aria-label="Dark theme" title="Dark"></button>
                  <button class="swatch swatch-black" data-key="theme" data-value="black" aria-label="Black theme" title="Black"></button>
                </div>
              </div>
            </div>
          </div>
          <main>
            <header>
              <h1>\(title)</h1>
              \(metaLine)
            </header>
            <article>\(article.content)</article>
          </main>
          <script>
          (function () {
            var s = \(settings.json);
            var MIN = \(ReaderSettings.fontSizeRange.lowerBound), MAX = \(ReaderSettings.fontSizeRange.upperBound);
            var FONTS = { serif: '\(serif)', sans: '\(sans)' };
            var WIDTHS = { narrow: '\(ReaderSettings.Width.narrow.css)', normal: '\(ReaderSettings.Width.normal.css)', wide: '\(ReaderSettings.Width.wide.css)' };
            var LEADINGS = { compact: '\(ReaderSettings.LineHeight.compact.css)', normal: '\(ReaderSettings.LineHeight.normal.css)', relaxed: '\(ReaderSettings.LineHeight.relaxed.css)' };
            var root = document.documentElement;
            var btn = document.getElementById('readerAa');
            var panel = document.getElementById('readerPanel');
            var recentsBtn = document.getElementById('readerRecentsBtn');
            var recents = document.getElementById('readerRecents');
            // The two popovers, so opening one closes the other.
            var popovers = [{ btn: btn, panel: panel }, { btn: recentsBtn, panel: recents }];

            function apply() {
              root.style.setProperty('--reader-size', s.fontSize + 'px');
              root.style.setProperty('--reader-font', FONTS[s.fontFamily]);
              root.style.setProperty('--reader-width', WIDTHS[s.width]);
              root.style.setProperty('--reader-leading', LEADINGS[s.lineHeight]);
              if (s.theme === 'auto') { root.removeAttribute('data-theme'); }
              else { root.setAttribute('data-theme', s.theme); }
              panel.querySelectorAll('button[data-key]').forEach(function (b) {
                b.setAttribute('aria-pressed', String(s[b.dataset.key] === b.dataset.value));
              });
              panel.querySelector('button[data-step="-1"]').disabled = s.fontSize <= MIN;
              panel.querySelector('button[data-step="1"]').disabled = s.fontSize >= MAX;
            }
            function save() {
              try { window.webkit.messageHandlers.webwrapReader.postMessage(s); } catch (e) {}
            }
            // Opens one popover and closes the rest; `null` closes everything.
            function setOpen(which) {
              popovers.forEach(function (p) {
                var open = p.panel === which;
                p.panel.hidden = !open;
                p.btn.setAttribute('aria-expanded', String(open));
              });
            }
            panel.addEventListener('click', function (e) {
              var b = e.target.closest('button');
              if (!b || b.disabled) { return; }
              if (b.dataset.step) {
                s.fontSize = Math.min(MAX, Math.max(MIN, s.fontSize + Number(b.dataset.step)));
              } else if (b.dataset.key) {
                s[b.dataset.key] = b.dataset.value;
              } else { return; }
              apply(); save();
            });
            btn.addEventListener('click', function () { setOpen(panel.hidden ? panel : null); });
            recentsBtn.addEventListener('click', function () {
              setOpen(recents.hidden ? recents : null);
            });
            // A recents row hands its URL to the host, which re-validates it against the
            // app's domain scope before navigating — the same path an incoming link takes.
            recents.addEventListener('click', function (e) {
              if (e.target.closest('#readerClear')) {
                // Removing the button detaches the click target, so the document-level
                // close handler would see a node outside .reader-controls and hide the
                // panel — hiding the empty state we're about to show. Stop it here.
                e.stopPropagation();
                // Empty the panel in place — the host clears the stored list.
                recents.querySelectorAll('.recent, #readerClear').forEach(function (n) {
                  n.remove();
                });
                recents.insertAdjacentHTML('beforeend',
                  '<p class="recent-empty">No recent articles</p>');
                try { window.webkit.messageHandlers.webwrapReaderClear.postMessage(''); }
                catch (err) {}
                return;
              }
              var row = e.target.closest('button[data-url]');
              if (!row) { return; }
              setOpen(null);
              try { window.webkit.messageHandlers.webwrapReaderOpen.postMessage(row.dataset.url); }
              catch (err) {}
            });
            document.addEventListener('click', function (e) {
              if (!e.target.closest('.reader-controls')) { setOpen(null); }
            });
            document.addEventListener('keydown', function (e) {
              if (e.key !== 'Escape') { return; }
              // Return focus to the button that opened the popover being dismissed.
              var open = popovers.filter(function (p) { return !p.panel.hidden; })[0];
              if (open) { setOpen(null); open.btn.focus(); }
            });
            apply();
          })();
          </script>
        </body>
        </html>
        """
    }
}
