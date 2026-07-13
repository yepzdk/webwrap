import Foundation

/// Resolves the `WebWrapUserAgent` setting (a preset token or a literal UA string) to
/// what the host should apply to its web view. Pure — unit-tested.
///
/// WKWebView's stock user agent lacks the `Version/x Safari/x` suffix real Safari
/// sends, so UA-sniffing sites classify wrapped apps as an ancient/unknown browser.
/// The host therefore always appends `safariApplicationName` via
/// `applicationNameForUserAgent`, making the default UA identical to Safari's; the
/// presets below override the whole string via `customUserAgent` instead.
///
/// The raw token (not the resolved string) is what's baked into the plist and stored
/// as a Settings override, so bumping the preset strings here updates every app on
/// its next `webwrap update`.
enum UserAgent {
    /// Appended to WKWebView's default UA (via `applicationNameForUserAgent`) so the
    /// result matches real Safari. Bump alongside Safari releases.
    static let safariApplicationName = "Version/26.0 Safari/605.1.15"

    /// Full replacement UA strings per preset token. Chrome froze its UA format, so
    /// only the major version needs occasional bumping; Edge is Chrome plus a suffix.
    private static let chrome =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
        + "Chrome/138.0.0.0 Safari/537.36"
    private static let presets: [String: String] = [
        "safari": "", // sentinel: resolved to nil below (use the Safari-suffixed default)
        "chrome": chrome,
        "edge": chrome + " Edg/138.0.0.0",
    ]

    /// The preset tokens accepted (case-insensitively) besides a literal UA string.
    /// Drives help text and the Settings popup so they can't drift from `presets`.
    static let presetTokens = ["safari", "chrome", "edge"]

    /// Human-readable name of a raw setting value, for display (About panel):
    /// nil/empty/`safari` → "Safari (default)", preset tokens → their capitalized
    /// names, anything else → "Custom" (the full string is visible in Settings).
    static func displayName(for raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return "Safari (default)" }
        switch raw.lowercased() {
        case "safari": return "Safari (default)"
        case "chrome": return "Chrome"
        case "edge": return "Edge"
        default: return "Custom"
        }
    }

    /// What to assign to `WKWebView.customUserAgent` for a raw setting value:
    /// nil/empty/`safari` → nil (keep the Safari-suffixed default), a preset token →
    /// its full UA string, anything else → the string verbatim (a custom UA).
    static func customUserAgent(for raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        if let preset = presets[raw.lowercased()] {
            return preset.isEmpty ? nil : preset
        }
        return raw
    }
}
