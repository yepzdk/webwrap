import Foundation

/// The size of the navigation toolbar. `regular` is macOS's tall unified toolbar (the
/// original look); `compact` is the shorter `unifiedCompact` style with smaller icons.
/// Backed by stable raw strings so it round-trips through the `Info.plist` and
/// `UserDefaults`. Pure — no AppKit — so it's shared by the CLI/config layers too; the
/// host maps it to concrete AppKit metrics.
enum ToolbarStyle: String, CaseIterable, Equatable {
    case regular
    case compact

    /// The default when nothing is specified (and what legacy apps without the key get),
    /// chosen to preserve the original look.
    static let `default`: ToolbarStyle = .regular

    /// Parses a stored raw value, falling back to the default for nil/unknown values so a
    /// missing or garbled plist/UserDefaults entry is never fatal.
    static func parse(_ raw: String?) -> ToolbarStyle {
        raw.flatMap(ToolbarStyle.init(rawValue:)) ?? .default
    }
}

/// Runtime-adjustable presentation settings for a generated app, layered over the
/// values baked into the bundle's `Info.plist` at create/update time.
///
/// A signed bundle's `Info.plist` is read-only at runtime (writing it would invalidate
/// the code signature), so in-app changes can't edit it. Instead the baked plist value
/// is the *default* and the in-app Settings window writes *overrides* into the app's own
/// `UserDefaults`. The effective value is the override when present, else the baked
/// default. "Restore Defaults" clears the overrides so the app falls back to its baked
/// config.
///
/// Only presentation settings live here — toolbar, progress bar, window background.
/// Identity (URL/name/icon) and build concerns (signing) stay create/update-only.
///
/// The resolution logic is pure (the store is injected) so it's unit-testable without
/// touching real `UserDefaults`; `HostDefaultsStore` wires the real store at runtime.
enum HostSettings {
    /// `UserDefaults` keys the in-app Settings window writes overrides to. Namespaced so
    /// they don't collide with anything WebKit or AppKit may persist for the app.
    enum Key {
        static let toolbar = "webwrap.override.toolbar"
        static let toolbarStyle = "webwrap.override.toolbarStyle"
        static let progressBar = "webwrap.override.progressBar"
        /// The background override is tri-state, so it needs two keys: a "set" marker and
        /// the value. Marker present + value present → that color; marker present + value
        /// absent → explicitly cleared (no color); marker absent → fall back to baked.
        static let backgroundColorSet = "webwrap.override.backgroundColorSet"
        static let backgroundColor = "webwrap.override.backgroundColorValue"
    }

    /// The minimal read/write surface `HostSettings` needs from a key-value store.
    /// `UserDefaults` satisfies this directly; tests pass an in-memory implementation.
    protocol Store: AnyObject {
        func bool(forKey key: String) -> Bool
        func string(forKey key: String) -> String?
        /// Whether a value has ever been written for `key` (distinguishes "unset" from
        /// "set to the type's zero value").
        func hasValue(forKey key: String) -> Bool
        func set(_ value: Bool, forKey key: String)
        func set(_ value: String?, forKey key: String)
        func remove(forKey key: String)
    }

    // MARK: - Resolution (override over baked default)

    /// The effective "show toolbar" value: the override if one has been set, else the
    /// baked default from the plist.
    static func toolbar(store: Store, bakedDefault: Bool) -> Bool {
        store.hasValue(forKey: Key.toolbar) ? store.bool(forKey: Key.toolbar) : bakedDefault
    }

    /// The effective navigation-toolbar size: the override if one has been set, else the
    /// baked default from the plist.
    static func toolbarStyle(store: Store, bakedDefault: ToolbarStyle) -> ToolbarStyle {
        store.hasValue(forKey: Key.toolbarStyle)
            ? ToolbarStyle.parse(store.string(forKey: Key.toolbarStyle))
            : bakedDefault
    }

    /// The effective "show progress bar" value: override if set, else baked default.
    static func progressBar(store: Store, bakedDefault: Bool) -> Bool {
        store.hasValue(forKey: Key.progressBar) ? store.bool(forKey: Key.progressBar) : bakedDefault
    }

    /// The effective background color (a CSS color string, or nil for none).
    ///
    /// Tri-state: when no override marker is set, the baked default is used; when the
    /// override is set, its value wins — including `nil`, which means the user explicitly
    /// cleared the color (so a baked color does NOT show through).
    static func backgroundColor(store: Store, bakedDefault: String?) -> String? {
        guard store.bool(forKey: Key.backgroundColorSet) else { return bakedDefault }
        // Treat an empty stored value the same as cleared.
        return store.string(forKey: Key.backgroundColor).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Writing overrides

    static func setToolbar(_ value: Bool, store: Store) {
        store.set(value, forKey: Key.toolbar)
    }

    static func setToolbarStyle(_ value: ToolbarStyle, store: Store) {
        store.set(value.rawValue, forKey: Key.toolbarStyle)
    }

    static func setProgressBar(_ value: Bool, store: Store) {
        store.set(value, forKey: Key.progressBar)
    }

    /// Sets the background override. `nil` records an explicit "no color" (which overrides
    /// a baked color); a color string records that color.
    static func setBackgroundColor(_ value: String?, store: Store) {
        store.set(true, forKey: Key.backgroundColorSet)
        store.set(value, forKey: Key.backgroundColor)
    }

    // MARK: - Restore defaults

    /// Clears all overrides so every setting falls back to its baked plist default.
    static func restoreDefaults(store: Store) {
        store.remove(forKey: Key.toolbar)
        store.remove(forKey: Key.toolbarStyle)
        store.remove(forKey: Key.progressBar)
        store.remove(forKey: Key.backgroundColorSet)
        store.remove(forKey: Key.backgroundColor)
    }
}

/// `HostSettings.Store` backed by real `UserDefaults` (the app's standard suite, already
/// namespaced per-bundle). Used by the host; tests use an in-memory store instead.
final class HostDefaultsStore: HostSettings.Store {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    func hasValue(forKey key: String) -> Bool { defaults.object(forKey: key) != nil }
    func set(_ value: Bool, forKey key: String) { defaults.set(value, forKey: key) }
    func set(_ value: String?, forKey key: String) { defaults.set(value, forKey: key) }
    func remove(forKey key: String) { defaults.removeObject(forKey: key) }
}
