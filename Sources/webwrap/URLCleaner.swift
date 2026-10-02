import Foundation

/// Unwraps tracking/redirect URLs and strips tracking query parameters from
/// incoming links, so the app navigates straight to the destination without ever
/// contacting the tracking host (which may be blocked, e.g. by a Pi-hole).
///
/// Ported from https://github.com/yepzdk/url-cleaner with three deliberate
/// deviations for navigation safety: OAuth-style `redirect`/`redirect_uri`
/// parameters are never unwrapped (that would break sign-in links), plain
/// (unencoded) URLs nested in a path are never unwrapped (that would break
/// Wayback Machine links), and query unwrapping only happens on known
/// redirector hosts (see `redirectors`). Pure — unit-tested.
enum URLCleaner {
    /// Query parameters a redirector puts the destination in. Only consulted on
    /// the hosts below, and only unwrapped when the value is an absolute http(s)
    /// URL. Google's `q` is deliberately absent here — it's a search parameter
    /// far more often than a redirect target — and added back only for
    /// `google.*/url`.
    private static let destinationParams: Set<String> =
        ["url", "u", "link", "target", "dest", "destination"]

    /// A host that redirects through a query parameter, optionally only under a
    /// path prefix (LinkedIn is a whole site with one redirector endpoint; the
    /// others are dedicated hosts).
    private struct Redirector {
        let host: String
        /// Path prefix the redirect lives under; nil when the whole host is one.
        var path: String?
    }

    /// The hosts `destinationParams` applies to, matched exact-or-subdomain so
    /// "eur01.safelinks.protection.outlook.com" is covered by the bare suffix.
    ///
    /// Unwrapping is limited to these because `?url=`, `?u=` and `?link=` are
    /// ordinary application parameters everywhere else — document viewers, image
    /// proxies, oEmbed endpoints — and rewriting those navigations sends the app
    /// to the embedded asset instead of the page, or, under same-site scoping,
    /// drops the link entirely (#119). Google is matched separately in
    /// `redirectParams(for:)` because its redirector exists on every country
    /// domain.
    private static let redirectors: [Redirector] = [
        Redirector(host: "l.facebook.com"),
        Redirector(host: "lm.facebook.com"),
        Redirector(host: "l.instagram.com"),
        Redirector(host: "l.messenger.com"),
        Redirector(host: "safelinks.protection.outlook.com"),
        Redirector(host: "lnkd.in"),
        Redirector(host: "linkedin.com", path: "/redir/"),
        Redirector(host: "out.reddit.com"),
        Redirector(host: "slack-redir.net"),
    ]

    /// Tracking query parameters to strip, as (exact names, name prefixes) —
    /// upstream's regex list flattened. Upstream also strips a bare `p`, which is
    /// skipped here: `?p=2` pagination is too common to break.
    private static let trackingParamNames: Set<String> = [
        "fbclid", "gclid", "yclid", "dclid", "twclid", "igshid", "icid",
        "ref", "ref_", "referer", "referrer", "source",
        "aff", "affiliate", "partner", "partnerid",
        "mkt_tok", "cmpid", "li_fat_id", "s_cid", "couponcode", "ssrc", "wt_zmc",
    ]
    private static let trackingParamPrefixes = [
        "utm_", "otm_", "mc_", "source_", "aff_", "hsa_", "oly_", "et_", "_hs",
    ]

    /// Cleans an incoming URL: repeatedly unwraps embedded destinations (bounded,
    /// for nested wrappers), then strips tracking parameters. Anything that can't
    /// be cleaned into a valid http(s) URL leaves the input unchanged — cleaning
    /// must never turn a working URL into a broken one.
    static func clean(_ url: URL) -> URL {
        var current = url
        // Unwrap until stable; 3 passes covers tracking-in-tracking without
        // giving a pathological URL an endless loop.
        for _ in 0..<3 {
            guard let unwrapped = unwrapDestination(of: current),
                  unwrapped != current else { break }
            current = unwrapped
        }
        return stripTrackingParams(from: current) ?? current
    }

    // MARK: - Unwrapping

    /// One unwrapping pass: the embedded destination if `url` looks like a
    /// redirector, nil otherwise.
    private static func unwrapDestination(of url: URL) -> URL? {
        if let fromQuery = destinationFromQuery(url) { return fromQuery }
        if let fromPath = encodedDestinationInPath(url) { return fromPath }
        if let postmark = postmarkDestination(url) { return postmark }
        return nil
    }

    /// A known redirect parameter whose value is an absolute http(s) URL — only on
    /// a host that is actually a redirector.
    private static func destinationFromQuery(_ url: URL) -> URL? {
        guard let names = redirectParams(for: url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }
        for item in items where names.contains(item.name.lowercased()) {
            if let value = item.value, let dest = URL(string: value),
               HostNavigation.isWebURL(dest), dest.host != nil {
                return dest
            }
        }
        return nil
    }

    /// The destination parameters to honour on `url`'s host, or nil when the host
    /// isn't a redirector and its query must be left alone.
    private static func redirectParams(for url: URL) -> Set<String>? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        // Google's redirector carries the destination in `q` as well as `url`, but
        // only under `/url` — `/search?q=` is a search, and searching for a URL
        // must stay on the results page.
        if isGoogleDomain(host), url.path == "/url" {
            return destinationParams.union(["q"])
        }
        for redirector in redirectors
        where host == redirector.host || host.hasSuffix("." + redirector.host) {
            guard let path = redirector.path else { return destinationParams }
            if url.path.hasPrefix(path) { return destinationParams }
        }
        return nil
    }

    /// Whether `host` is one of Google's own domains — google.com, google.dk,
    /// google.co.uk — rather than something that merely starts with "google.".
    /// The redirector exists on every country domain, so the suffix can't be
    /// enumerated; instead the labels after "google" have to look like a public
    /// suffix, which rules out the "google.com.evil.test" shape a bare prefix
    /// check would accept.
    ///
    /// A single label is any ccTLD/gTLD of 2–3 characters. Two labels have to be
    /// one of the second-level registries Google uses under a ccTLD, because
    /// `app.dev` and `ai.xyz` are ordinary registrations whose "google" subdomain
    /// anyone can take.
    private static func isGoogleDomain(_ host: String) -> Bool {
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let labels = bare.split(separator: ".")
        guard labels.first == "google" else { return false }
        let suffix = labels.dropFirst()
        guard (1...2).contains(suffix.count),
              let tld = suffix.last, (2...3).contains(tld.count) else { return false }
        guard suffix.count == 2 else { return true }
        return googleSecondLevels.contains(String(suffix.first!))
    }

    /// The second-level labels Google registers under, e.g. google.co.uk,
    /// google.com.au, google.com.br.
    private static let googleSecondLevels: Set<String> =
        ["co", "com", "net", "org", "ac", "gov", "edu"]

    /// A percent-encoded absolute URL embedded in the path, e.g. TLDR's
    /// `…/CL0/https:%2F%2Fwww.figma.com%2Fblog%2F…%3Futm_source=x/1/0100…`.
    /// The destination's own slashes are still encoded (%2F), so it ends at the
    /// first LITERAL `/` after the marker. Only encoded embeds are unwrapped —
    /// a plain nested `https://` is left alone (Wayback Machine links).
    ///
    /// Only the path is searched. An encoded URL in the *query* is an ordinary
    /// parameter value unless the host is a known redirector, in which case
    /// `destinationFromQuery` has already unwrapped it (#119).
    private static func encodedDestinationInPath(_ url: URL) -> URL? {
        // The still-encoded path, so the markers below are visible.
        guard let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .percentEncodedPath else { return nil }
        let lower = raw.lowercased()
        // The scheme may have its colon encoded too (https%3A%2F%2F).
        let markers = ["https:%2f%2f", "http:%2f%2f", "https%3a%2f%2f", "http%3a%2f%2f"]
        guard let markerRange = markers
            .compactMap({ lower.range(of: $0) })
            .min(by: { $0.lowerBound < $1.lowerBound })
        else { return nil }

        let tail = String(raw[markerRange.lowerBound...])
        let encoded = tail.split(separator: "/", maxSplits: 1,
                                 omittingEmptySubsequences: false)[0]
        guard let decoded = String(encoded).removingPercentEncoding,
              let dest = URL(string: decoded),
              HostNavigation.isWebURL(dest), dest.host != nil
        else { return nil }
        return dest
    }

    /// Postmark email tracking: `track.pstmrk.it/{2s,3s,4s}/dest.tld/path/TOKEN` —
    /// the destination is unencoded and schemeless, followed by a long tracking
    /// segment (30+ chars of [a-z0-9-], or 10+ digits). Upstream's exact rule.
    private static func postmarkDestination(_ url: URL) -> URL? {
        guard url.host?.lowercased() == "track.pstmrk.it" else { return nil }
        let raw = url.absoluteString
        let prefixes = ["track.pstmrk.it/3s/", "track.pstmrk.it/2s/",
                        "track.pstmrk.it/4s/", "track.pstmrk.it/"]
        for prefix in prefixes {
            guard let range = raw.range(of: prefix) else { continue }
            var tail = String(raw[range.upperBound...])
            if let match = tail.range(
                of: #"^([^/]+(?:/[^/]+)*?)(?:/[a-z0-9-]{30,}|/\d{10,})"#,
                options: [.regularExpression, .caseInsensitive]) {
                // Group 1 is the destination; re-derive it by trimming the
                // tracking segment the alternation matched at the end.
                let matched = String(tail[match])
                if let cut = matched.range(of: #"(?:/[a-z0-9-]{30,}|/\d{10,})$"#,
                                           options: [.regularExpression, .caseInsensitive]) {
                    tail = String(matched[..<cut.lowerBound])
                } else {
                    tail = matched
                }
            }
            let decoded = tail.removingPercentEncoding ?? tail
            let withScheme = decoded.hasPrefix("http://") || decoded.hasPrefix("https://")
                ? decoded : "https://" + decoded
            if let dest = URL(string: withScheme),
               HostNavigation.isWebURL(dest), dest.host != nil {
                return dest
            }
            return nil
        }
        return nil
    }

    // MARK: - Tracking parameters

    /// Whether a query parameter name is a known tracker.
    static func isTrackingParam(_ name: String) -> Bool {
        let lower = name.lowercased()
        return trackingParamNames.contains(lower)
            || trackingParamPrefixes.contains { lower.hasPrefix($0) }
    }

    /// Removes tracking parameters, preserving everything else (order, fragment).
    /// Nil when the URL can't be decomposed — the caller keeps the original.
    private static func stripTrackingParams(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        guard let items = components.queryItems, !items.isEmpty else { return url }
        let kept = items.filter { !isTrackingParam($0.name) }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url
    }
}
