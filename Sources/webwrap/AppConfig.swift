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
        return AppConfig(url: url, name: name, bundleId: bundleId, width: width, height: height)
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
                  width: Int? = nil, height: Int? = nil) -> AppConfig {
        AppConfig(
            url: url ?? self.url,
            name: name ?? self.name,
            bundleId: self.bundleId,
            width: width ?? self.width,
            height: height ?? self.height)
    }
}
