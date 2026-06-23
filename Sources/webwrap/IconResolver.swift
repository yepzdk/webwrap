import Foundation

/// Resolves the best available icon for a website by walking a chain of sources,
/// from highest quality to last resort:
///
///   1. Web app manifest (`<link rel="manifest">` → manifest JSON `icons[]`)
///   2. `apple-touch-icon` link
///   3. `<link rel="icon">` / `shortcut icon`
///   4. `/favicon.ico` at the site root
///   5. Google's favicon service
///
/// The first source that yields usable image bytes wins. Every step is best-effort:
/// network failures, malformed HTML/JSON, and missing tags each fall through to the
/// next source, and "no icon found" (returning `nil`) is an acceptable outcome — the
/// generated app simply gets the default bundle icon.
///
/// All network access goes through an injected `fetch` closure so the parsing logic
/// (link extraction, `sizes` parsing, manifest icon selection, URL resolution) stays
/// pure and unit-testable without hitting the network.
struct IconResolver {
    /// Where an icon ultimately came from — surfaced to the user by the interactive flow.
    enum Source: String {
        case manifest = "web app manifest"
        case appleTouchIcon = "apple-touch-icon"
        case linkIcon = "link icon"
        case openGraphImage = "og:image"
        case faviconIco = "favicon.ico"
        case googleService = "favicon service"
    }

    struct Resolved {
        let data: Data
        /// Lowercased file extension (without dot), e.g. "png", "ico". Used to pick a
        /// temp filename so `sips` reads the bytes with the right decoder.
        let ext: String
        let source: Source
    }

    /// Fetches the bytes at a URL, or returns nil on any failure. Injected so tests
    /// can supply canned responses and the resolver never touches the real network.
    typealias Fetch = (URL) -> Data?

    /// Measures image bytes, returning (width, height) in pixels, or nil if undecodable.
    /// Injected so the squareness guard is testable without `sips` or real images.
    typealias Measure = (Data) -> (width: Int, height: Int)?

    let siteURL: URL
    let fetch: Fetch
    let measure: Measure

    init(siteURL: URL, fetch: @escaping Fetch, measure: @escaping Measure = IconResolver.sipsMeasure) {
        self.siteURL = siteURL
        self.fetch = fetch
        self.measure = measure
    }

    /// Convenience initializer using a real network fetch with a short timeout.
    init?(urlString: String) {
        guard let url = URL(string: urlString) else { return nil }
        self.init(siteURL: url) { target in
            var request = URLRequest(url: target)
            request.timeoutInterval = 10
            // A browser-ish UA: some sites serve different (or no) markup to unknown clients.
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) webwrap",
                forHTTPHeaderField: "User-Agent")
            let semaphore = DispatchSemaphore(value: 0)
            var result: Data?
            let task = URLSession.shared.dataTask(with: request) { data, response, _ in
                defer { semaphore.signal() }
                if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
                    return
                }
                result = data
            }
            task.resume()
            // Bound the wait so a hung host can't stall app creation indefinitely.
            _ = semaphore.wait(timeout: .now() + 12)
            return result
        }
    }

    /// Default image measurer: writes the bytes to a temp file and reads pixel dimensions
    /// via `sips`. Returns nil if the bytes can't be decoded.
    static func sipsMeasure(_ data: Data) -> (width: Int, height: Int)? {
        let tmp = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("webwrap-measure-\(UUID().uuidString)")
        guard (try? data.write(to: URL(fileURLWithPath: tmp))) != nil else { return nil }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        proc.arguments = ["-g", "pixelWidth", "-g", "pixelHeight", tmp]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return nil }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        proc.waitUntilExit()

        func value(_ key: String) -> Int? {
            for line in out.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix(key) { return Int(t.dropFirst(key.count).trimmingCharacters(in: .whitespaces)) }
            }
            return nil
        }
        guard let w = value("pixelWidth:"), let h = value("pixelHeight:") else { return nil }
        return (w, h)
    }

    // MARK: - Resolution chain

    /// Walks the source chain and returns the first usable icon, or nil if none found.
    func resolve() -> Resolved? {
        let html = fetch(siteURL).flatMap { String(data: $0, encoding: .utf8) } ?? ""

        if let resolved = resolveFromManifest(html: html) { return resolved }
        if let resolved = resolveFromAppleTouchIcon(html: html) { return resolved }
        if let resolved = resolveFromLinkIcon(html: html) { return resolved }
        if let resolved = resolveFromOpenGraphImage(html: html) { return resolved }
        if let resolved = resolveFromFaviconIco() { return resolved }
        if let resolved = resolveFromGoogleService() { return resolved }
        return nil
    }

    private func resolveFromManifest(html: String) -> Resolved? {
        guard let manifestHref = Self.linkHref(in: html, matchingRel: "manifest"),
              let manifestURL = Self.resolveURL(manifestHref, against: siteURL),
              let manifestData = fetch(manifestURL),
              let iconHref = Self.bestManifestIconHref(fromManifestJSON: manifestData),
              let iconURL = Self.resolveURL(iconHref, against: manifestURL),
              let data = fetch(iconURL)
        else { return nil }
        return Resolved(data: data, ext: Self.pathExtension(of: iconURL), source: .manifest)
    }

    private func resolveFromAppleTouchIcon(html: String) -> Resolved? {
        // Match both "apple-touch-icon" and "apple-touch-icon-precomposed".
        guard let href = Self.linkHref(in: html, matchingRel: "apple-touch-icon", prefix: true),
              let iconURL = Self.resolveURL(href, against: siteURL),
              let data = fetch(iconURL)
        else { return nil }
        return Resolved(data: data, ext: Self.pathExtension(of: iconURL), source: .appleTouchIcon)
    }

    private func resolveFromLinkIcon(html: String) -> Resolved? {
        guard let href = Self.bestIconLinkHref(in: html),
              let iconURL = Self.resolveURL(href, against: siteURL),
              let data = fetch(iconURL)
        else { return nil }
        return Resolved(data: data, ext: Self.pathExtension(of: iconURL), source: .linkIcon)
    }

    /// Tries the page's `og:image` / `twitter:image` sharing image. These are often much
    /// higher-resolution than a favicon, but are frequently wide 16:9 banners rather than
    /// square icons — so we measure the fetched bytes and only use it when it's close to
    /// square, otherwise fall through (a banner squashed to a square would distort).
    private func resolveFromOpenGraphImage(html: String) -> Resolved? {
        guard let href = Self.socialImageURL(in: html),
              let imageURL = Self.resolveURL(href, against: siteURL),
              let data = fetch(imageURL),
              let (w, h) = measure(data),
              Self.isSquareEnough(width: w, height: h)
        else { return nil }
        return Resolved(data: data, ext: Self.pathExtension(of: imageURL), source: .openGraphImage)
    }

    private func resolveFromFaviconIco() -> Resolved? {
        guard var comps = URLComponents(url: siteURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.path = "/favicon.ico"
        comps.query = nil
        comps.fragment = nil
        guard let url = comps.url, let data = fetch(url) else { return nil }
        return Resolved(data: data, ext: "ico", source: .faviconIco)
    }

    private func resolveFromGoogleService() -> Resolved? {
        guard let host = siteURL.host,
              let url = URL(string: "https://www.google.com/s2/favicons?sz=256&domain=\(host)"),
              let data = fetch(url)
        else { return nil }
        return Resolved(data: data, ext: "png", source: .googleService)
    }

    // MARK: - Pure helpers (no I/O — unit-tested directly)

    /// Whether an href is a usable icon URL we should bother fetching. Rejects empty/
    /// whitespace values and placeholder `data:` URIs that carry no real image (e.g.
    /// `data:,` or `data:;base64,`), which some sites declare as `<link rel="icon">`.
    /// Such an href would only fail conversion downstream, so we skip it and fall through.
    static func isUsableIconHref(_ href: String) -> Bool {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.lowercased().hasPrefix("data:") {
            // Keep only data URIs that actually carry a payload after the comma.
            guard let comma = trimmed.firstIndex(of: ",") else { return false }
            let payload = trimmed[trimmed.index(after: comma)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !payload.isEmpty
        }
        return true
    }

    /// Returns the `href` of the first `<link>` whose `rel` matches `rel`. With
    /// `prefix: true`, matches any rel token that *starts with* `rel` (so
    /// "apple-touch-icon" also catches "apple-touch-icon-precomposed").
    static func linkHref(in html: String, matchingRel rel: String, prefix: Bool = false) -> String? {
        for tag in linkTags(in: html) {
            guard let relValue = attribute("rel", in: tag)?.lowercased() else { continue }
            let tokens = relValue.split(whereSeparator: { $0 == " " }).map(String.init)
            let matched = prefix
                ? tokens.contains { $0.hasPrefix(rel) }
                : tokens.contains(rel)
            if matched, let href = attribute("href", in: tag), isUsableIconHref(href) {
                return href
            }
        }
        return nil
    }

    /// Returns the URL from an `og:image` or `twitter:image` meta tag, preferring
    /// `og:image`. Handles both `property=` (Open Graph) and `name=` (Twitter) forms.
    static func socialImageURL(in html: String) -> String? {
        var ogImage: String?
        var twitterImage: String?
        for tag in metaTags(in: html) {
            // The "key" can be in either `property` (og) or `name` (twitter/og both seen).
            let key = (attribute("property", in: tag) ?? attribute("name", in: tag))?.lowercased()
            guard let key, let content = attribute("content", in: tag), isUsableIconHref(content) else { continue }
            switch key {
            case "og:image", "og:image:url": if ogImage == nil { ogImage = content }
            case "twitter:image", "twitter:image:src": if twitterImage == nil { twitterImage = content }
            default: break
            }
        }
        return ogImage ?? twitterImage
    }

    /// Whether an image's aspect ratio is close enough to square to use as an app icon
    /// without distortion. Accepts a longer:shorter ratio up to ~1.15 (≈15% off square).
    static func isSquareEnough(width: Int, height: Int, tolerance: Double = 0.15) -> Bool {
        guard width > 0, height > 0 else { return false }
        let longer = Double(max(width, height))
        let shorter = Double(min(width, height))
        return longer / shorter <= 1.0 + tolerance
    }

    /// Picks the highest-quality `<link rel="icon"|"shortcut icon">` href by `sizes`
    /// (larger wins; an unsized entry is kept only if nothing sized was found).
    static func bestIconLinkHref(in html: String) -> String? {
        var best: (size: Int, href: String)?
        var fallback: String?
        for tag in linkTags(in: html) {
            guard let relValue = attribute("rel", in: tag)?.lowercased() else { continue }
            let tokens = relValue.split(separator: " ").map(String.init)
            // "icon", "shortcut icon", "mask-icon"… we only want raster icon rels.
            guard tokens.contains("icon") else { continue }
            guard let href = attribute("href", in: tag), isUsableIconHref(href) else { continue }
            if let size = largestSize(in: attribute("sizes", in: tag)) {
                if best == nil || size > best!.size { best = (size, href) }
            } else if fallback == nil {
                fallback = href
            }
        }
        return best?.href ?? fallback
    }

    /// From manifest JSON, returns the href of the largest square icon, preferring PNG.
    static func bestManifestIconHref(fromManifestJSON data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let icons = obj["icons"] as? [[String: Any]]
        else { return nil }

        var best: (score: Int, size: Int, href: String)?
        for icon in icons {
            guard let src = icon["src"] as? String, isUsableIconHref(src) else { continue }
            let size = largestSize(in: icon["sizes"] as? String) ?? 0
            let type = (icon["type"] as? String)?.lowercased() ?? ""
            // Prefer PNG; treat unknown type as neutral, SVG slightly lower (sips can't
            // rasterize SVG, so it would fail downstream).
            let typeScore = type.contains("png") ? 2 : (type.contains("svg") ? 0 : 1)
            if best == nil || size > best!.size || (size == best!.size && typeScore > best!.score) {
                best = (typeScore, size, src)
            }
        }
        return best?.href
    }

    /// Parses a `sizes` attribute ("16x16 32x32", "any", "180x180") and returns the
    /// largest edge length found, or nil if none parse.
    static func largestSize(in sizes: String?) -> Int? {
        guard let sizes = sizes?.lowercased(), !sizes.isEmpty else { return nil }
        var max: Int?
        for token in sizes.split(separator: " ") {
            let dims = token.split(separator: "x").compactMap { Int($0) }
            guard let edge = dims.max() else { continue }
            if max == nil || edge > max! { max = edge }
        }
        return max
    }

    /// Resolves a possibly-relative href against a base URL (handles absolute,
    /// protocol-relative `//host/x`, and root/relative paths).
    static func resolveURL(_ href: String, against base: URL) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("//") {
            let scheme = base.scheme ?? "https"
            return URL(string: "\(scheme):\(trimmed)")
        }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    static func pathExtension(of url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "png" : ext
    }

    // MARK: - Tag scanning

    /// Extracts the raw text of every `<link ...>` tag from an HTML string. A small,
    /// tolerant scanner — we only need attributes off `<link>` elements, not a full
    /// HTML parse.
    static func linkTags(in html: String) -> [String] {
        tags(in: html, named: "<link")
    }

    /// Extracts the raw text of every `<meta ...>` tag. Same tolerant scan as `linkTags`.
    static func metaTags(in html: String) -> [String] {
        tags(in: html, named: "<meta")
    }

    /// Shared scan: collects the text of every element whose opening matches `opening`
    /// (case-insensitively) up to its closing `>`.
    private static func tags(in html: String, named opening: String) -> [String] {
        var tags: [String] = []
        let lower = html.lowercased()
        var searchStart = lower.startIndex
        while let open = lower.range(of: opening, range: searchStart..<lower.endIndex) {
            guard let close = html.range(of: ">", range: open.lowerBound..<html.endIndex) else { break }
            tags.append(String(html[open.lowerBound..<close.upperBound]))
            searchStart = close.upperBound
        }
        return tags
    }

    /// Reads a single HTML attribute value from a tag, tolerating single/double/unquoted
    /// values and arbitrary whitespace around `=`.
    static func attribute(_ name: String, in tag: String) -> String? {
        let lowerTag = tag.lowercased()
        var idx = lowerTag.startIndex
        let needle = name.lowercased()
        while let found = lowerTag.range(of: needle, range: idx..<lowerTag.endIndex) {
            idx = found.upperBound
            // Ensure it's a whole attribute name (preceded by whitespace or '<'), not a
            // substring of another attribute.
            let before = found.lowerBound == lowerTag.startIndex
                ? " "
                : String(lowerTag[lowerTag.index(before: found.lowerBound)])
            guard before == " " || before == "\t" || before == "\n" || before == "<" else { continue }

            // Skip whitespace, expect '='.
            var cursor = found.upperBound
            while cursor < lowerTag.endIndex, lowerTag[cursor] == " " || lowerTag[cursor] == "\t" || lowerTag[cursor] == "\n" {
                cursor = lowerTag.index(after: cursor)
            }
            guard cursor < lowerTag.endIndex, lowerTag[cursor] == "=" else { continue }
            cursor = lowerTag.index(after: cursor)
            while cursor < lowerTag.endIndex, lowerTag[cursor] == " " || lowerTag[cursor] == "\t" || lowerTag[cursor] == "\n" {
                cursor = lowerTag.index(after: cursor)
            }
            guard cursor < lowerTag.endIndex else { return nil }

            // Read the value from the ORIGINAL tag (preserve case) at the same offset.
            let valueStartOffset = lowerTag.distance(from: lowerTag.startIndex, to: cursor)
            let valueStart = tag.index(tag.startIndex, offsetBy: valueStartOffset)
            let quote = tag[valueStart]
            if quote == "\"" || quote == "'" {
                let afterQuote = tag.index(after: valueStart)
                guard let end = tag.range(of: String(quote), range: afterQuote..<tag.endIndex) else { return nil }
                return String(tag[afterQuote..<end.lowerBound])
            } else {
                // Unquoted: read until whitespace, '>', or a self-closing "/>".
                // A lone '/' inside the value (e.g. a leading-slash path) is kept.
                var end = valueStart
                while end < tag.endIndex {
                    let ch = tag[end]
                    if ch == " " || ch == "\t" || ch == "\n" || ch == ">" { break }
                    if ch == "/" {
                        let next = tag.index(after: end)
                        if next < tag.endIndex, tag[next] == ">" { break } // self-closing
                    }
                    end = tag.index(after: end)
                }
                return String(tag[valueStart..<end])
            }
        }
        return nil
    }
}
