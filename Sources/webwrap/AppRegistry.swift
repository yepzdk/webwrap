import Foundation

/// A webwrap-generated app discovered on disk.
struct WebWrapApp: Equatable {
    let name: String
    let url: String
    let bundleId: String
    /// Absolute path to the `.app` bundle.
    let path: String
}

/// Discovers and describes webwrap-generated apps. A generated app self-identifies via
/// the `WebWrapURL` key baked into its `Info.plist` (see AppBuilder), so no external
/// registry/state is needed — we just scan the standard app directories.
enum AppRegistry {
    /// The directories `list` scans: `/Applications` and the user's `~/Applications`.
    static var searchPaths: [String] {
        var paths = ["/Applications"]
        if let userApps = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first {
            paths.append(userApps.path)
        }
        return paths
    }

    /// Scans the search paths for top-level `.app` bundles that are webwrap apps,
    /// sorted by name (case-insensitive). Directory I/O lives here; parsing is pure.
    static func discover(in searchPaths: [String] = searchPaths,
                         fm: FileManager = .default) -> [WebWrapApp] {
        var apps: [WebWrapApp] = []
        for dir in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let appPath = (dir as NSString).appendingPathComponent(entry)
                let plistPath = (appPath as NSString)
                    .appendingPathComponent("Contents/Info.plist")
                guard let data = fm.contents(atPath: plistPath),
                      let app = parse(plistData: data, appPath: appPath)
                else { continue }
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: - Pure helpers

    /// Parses an `Info.plist`'s bytes into a `WebWrapApp`, or nil if it isn't a webwrap
    /// app (no `WebWrapURL` marker) or can't be parsed. Pure — no filesystem access.
    static func parse(plistData data: Data, appPath: String) -> WebWrapApp? {
        guard let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any],
              let url = dict["WebWrapURL"] as? String
        else { return nil }
        // Fall back to the bundle filename for the name if CFBundleName is somehow absent.
        let fallbackName = ((appPath as NSString).lastPathComponent as NSString)
            .deletingPathExtension
        let name = (dict["CFBundleName"] as? String) ?? fallbackName
        let bundleId = (dict["CFBundleIdentifier"] as? String) ?? ""
        return WebWrapApp(name: name, url: url, bundleId: bundleId, path: appPath)
    }

    /// Renders the discovered apps as an aligned, human-readable table. Returns a
    /// friendly empty-state message when the list is empty. Pure — formatting only.
    static func renderTable(_ apps: [WebWrapApp]) -> String {
        guard !apps.isEmpty else {
            return "No webwrap apps found in \(searchPaths.map(abbreviate).joined(separator: " or "))."
        }

        let rows = apps.map { (name: $0.name, url: $0.url, location: abbreviate(directory(of: $0.path))) }
        let nameWidth = max("NAME".count, rows.map { $0.name.count }.max() ?? 0)
        let urlWidth = max("URL".count, rows.map { $0.url.count }.max() ?? 0)

        func line(_ name: String, _ url: String, _ location: String) -> String {
            let n = name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            let u = url.padding(toLength: urlWidth, withPad: " ", startingAt: 0)
            return "\(n)  \(u)  \(location)"
        }

        var out = [line("NAME", "URL", "LOCATION")]
        out += rows.map { line($0.name, $0.url, $0.location) }
        out.append("")
        out.append(apps.count == 1 ? "1 app" : "\(apps.count) apps")
        return out.joined(separator: "\n")
    }

    /// Replaces the user's home directory prefix with `~` for compact display.
    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// The directory containing a bundle, e.g. "/Applications/Foo.app" → "/Applications".
    static func directory(of appPath: String) -> String {
        (appPath as NSString).deletingLastPathComponent
    }
}
