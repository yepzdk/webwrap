import Foundation

/// The full configuration baked into a generated webwrap app's `Info.plist`. Read back
/// when updating an existing app so its settings can be preserved or selectively
/// overridden.
struct AppConfig: Equatable {
    var url: String
    var name: String
    var bundleId: String
    var width: Int
    var height: Int
    /// Whether the app shows a navigation toolbar (back/forward/reload). Off by default
    /// to keep the chromeless look; opt in with `--toolbar`.
    var showToolbar: Bool
    /// Whether the app shows a thin page-load progress line at the top of the window.
    /// Off by default; opt in with `--progress-bar`.
    var progressBar: Bool
    /// Window background color (a CSS color string, e.g. "#1a73e8"), used to avoid a
    /// white first-paint flash. Nil when unset. Derived from the site's manifest at
    /// create time; carried over on update.
    var backgroundColor: String?
    /// Whether the app registers as an http/https handler and navigates to URLs it's
    /// opened with (e.g. from Choosy). Off by default; `--handle-urls`.
    var handleURLs: Bool
    /// When `handleURLs` is on, whether off-domain incoming URLs are accepted too.
    /// `--open-any-url`.
    var openAnyURL: Bool

    /// Parses an existing app's `Info.plist` bytes into an `AppConfig`, or nil if the
    /// bundle isn't a webwrap app (no `WebWrapURL` marker) or can't be parsed. Pure.
    static func parse(plistData data: Data) -> AppConfig? {
        guard let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any],
              let url = dict["WebWrapURL"] as? String
        else { return nil }
        let name = (dict["CFBundleName"] as? String) ?? ""
        let bundleId = (dict["CFBundleIdentifier"] as? String) ?? ""
        // Dimensions are stored as strings; fall back to the defaults if missing/garbled.
        let width = Int((dict["WebWrapWidth"] as? String) ?? "") ?? 1200
        let height = Int((dict["WebWrapHeight"] as? String) ?? "") ?? 800
        // Bool keys are stored as "1"/"0"; absent (older apps) means off.
        let showToolbar = plistBool(dict["WebWrapToolbar"])
        let progressBar = plistBool(dict["WebWrapProgressBar"])
        // Optional; absent on older apps and sites without a manifest color.
        let backgroundColor = (dict["WebWrapBackgroundColor"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        let handleURLs = plistBool(dict["WebWrapHandleURLs"])
        let openAnyURL = plistBool(dict["WebWrapOpenAnyURL"])
        return AppConfig(url: url, name: name, bundleId: bundleId,
                         width: width, height: height, showToolbar: showToolbar,
                         progressBar: progressBar,
                         backgroundColor: backgroundColor,
                         handleURLs: handleURLs, openAnyURL: openAnyURL)
    }

    /// Reads a `WebWrap*` boolean plist value, stored as the string "1"/"0". Absent or
    /// any non-"1" value reads as false. Centralizes the convention shared by all the
    /// bool keys (toolbar, handle-urls, open-any-url).
    static func plistBool(_ value: Any?) -> Bool {
        (value as? String) == "1"
    }

    /// Reads the `AppConfig` from a bundle on disk, or nil if it isn't a webwrap app.
    static func read(fromBundle appPath: String, fm: FileManager = .default) -> AppConfig? {
        let plistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = fm.contents(atPath: plistPath) else { return nil }
        return parse(plistData: data)
    }

    /// Returns a copy with the given overrides applied; nil overrides are left as-is
    /// (carried over from the existing config). The bundle identifier is intentionally
    /// NOT overridable here — it must stay stable so the app's login/session data store
    /// (keyed to the bundle id) survives an update.
    func applying(url: String? = nil, name: String? = nil,
                  width: Int? = nil, height: Int? = nil,
                  showToolbar: Bool? = nil,
                  progressBar: Bool? = nil,
                  backgroundColor: String?? = nil,
                  handleURLs: Bool? = nil,
                  openAnyURL: Bool? = nil) -> AppConfig {
        AppConfig(
            url: url ?? self.url,
            name: name ?? self.name,
            bundleId: self.bundleId,
            width: width ?? self.width,
            height: height ?? self.height,
            showToolbar: showToolbar ?? self.showToolbar,
            progressBar: progressBar ?? self.progressBar,
            // Double-optional: `nil` keeps the existing color; `.some(nil)` clears it.
            backgroundColor: backgroundColor ?? self.backgroundColor,
            handleURLs: handleURLs ?? self.handleURLs,
            openAnyURL: openAnyURL ?? self.openAnyURL)
    }
}
