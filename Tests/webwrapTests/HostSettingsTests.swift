import XCTest
@testable import webwrap

// Tests for the pure override-over-baked-default resolution of the runtime-adjustable
// presentation settings. No AppKit / UserDefaults — an in-memory store is injected.

final class HostSettingsTests: XCTestCase {
    /// In-memory `HostSettings.Store` standing in for `UserDefaults`. Tracks presence so
    /// the "has a value been set" distinction is exercised the same way `UserDefaults`
    /// (`object(forKey:) != nil`) behaves.
    private final class MemoryStore: HostSettings.Store {
        private var bools: [String: Bool] = [:]
        private var strings: [String: String] = [:]
        private var present: Set<String> = []

        func bool(forKey key: String) -> Bool { bools[key] ?? false }
        func string(forKey key: String) -> String? { strings[key] }
        func hasValue(forKey key: String) -> Bool { present.contains(key) }
        func set(_ value: Bool, forKey key: String) { bools[key] = value; present.insert(key) }
        func set(_ value: String?, forKey key: String) {
            if let value { strings[key] = value } else { strings[key] = nil }
            present.insert(key)
        }
        func remove(forKey key: String) {
            bools[key] = nil; strings[key] = nil; present.remove(key)
        }
    }

    // MARK: - Toolbar

    func testToolbarFallsBackToBakedDefaultWhenNoOverride() {
        let store = MemoryStore()
        XCTAssertTrue(HostSettings.toolbar(store: store, bakedDefault: true))
        XCTAssertFalse(HostSettings.toolbar(store: store, bakedDefault: false))
    }

    func testToolbarOverrideWinsOverBakedDefault() {
        let store = MemoryStore()
        HostSettings.setToolbar(false, store: store)
        XCTAssertFalse(HostSettings.toolbar(store: store, bakedDefault: true))
        HostSettings.setToolbar(true, store: store)
        XCTAssertTrue(HostSettings.toolbar(store: store, bakedDefault: false))
    }

    // MARK: - Toolbar style

    func testToolbarStyleFallsBackToBakedDefaultWhenNoOverride() {
        let store = MemoryStore()
        XCTAssertEqual(HostSettings.toolbarStyle(store: store, bakedDefault: .compact), .compact)
        XCTAssertEqual(HostSettings.toolbarStyle(store: store, bakedDefault: .regular), .regular)
    }

    func testToolbarStyleOverrideWinsOverBakedDefault() {
        let store = MemoryStore()
        HostSettings.setToolbarStyle(.compact, store: store)
        XCTAssertEqual(HostSettings.toolbarStyle(store: store, bakedDefault: .regular), .compact)
        HostSettings.setToolbarStyle(.regular, store: store)
        XCTAssertEqual(HostSettings.toolbarStyle(store: store, bakedDefault: .compact), .regular)
    }

    func testToolbarStyleGarbledOverrideFallsBackToDefault() {
        // A corrupt stored value parses to the type default rather than crashing.
        let store = MemoryStore()
        store.set("enormous", forKey: HostSettings.Key.toolbarStyle)
        XCTAssertEqual(HostSettings.toolbarStyle(store: store, bakedDefault: .compact), .regular)
    }

    // MARK: - Progress bar

    func testProgressBarFallsBackToBakedDefaultWhenNoOverride() {
        let store = MemoryStore()
        XCTAssertTrue(HostSettings.progressBar(store: store, bakedDefault: true))
        XCTAssertFalse(HostSettings.progressBar(store: store, bakedDefault: false))
    }

    func testProgressBarOverrideWinsOverBakedDefault() {
        let store = MemoryStore()
        HostSettings.setProgressBar(true, store: store)
        XCTAssertTrue(HostSettings.progressBar(store: store, bakedDefault: false))
        HostSettings.setProgressBar(false, store: store)
        XCTAssertFalse(HostSettings.progressBar(store: store, bakedDefault: true))
    }

    // MARK: - Background color (tri-state)

    func testBackgroundUnsetUsesBakedDefault() {
        let store = MemoryStore()
        XCTAssertEqual(HostSettings.backgroundColor(store: store, bakedDefault: "#1a73e8"), "#1a73e8")
        XCTAssertNil(HostSettings.backgroundColor(store: store, bakedDefault: nil))
    }

    func testBackgroundExplicitColorWinsOverBakedDefault() {
        let store = MemoryStore()
        HostSettings.setBackgroundColor("#ff0000", store: store)
        XCTAssertEqual(HostSettings.backgroundColor(store: store, bakedDefault: "#1a73e8"), "#ff0000")
        XCTAssertEqual(HostSettings.backgroundColor(store: store, bakedDefault: nil), "#ff0000")
    }

    func testBackgroundExplicitClearOverridesBakedColor() {
        let store = MemoryStore()
        // User explicitly chose "no color" — a baked color must NOT show through.
        HostSettings.setBackgroundColor(nil, store: store)
        XCTAssertNil(HostSettings.backgroundColor(store: store, bakedDefault: "#1a73e8"))
    }

    func testBackgroundEmptyStringTreatedAsCleared() {
        let store = MemoryStore()
        HostSettings.setBackgroundColor("", store: store)
        XCTAssertNil(HostSettings.backgroundColor(store: store, bakedDefault: "#1a73e8"))
    }

    // MARK: - Restore defaults

    func testRestoreDefaultsClearsAllOverrides() {
        let store = MemoryStore()
        HostSettings.setToolbar(true, store: store)
        HostSettings.setToolbarStyle(.compact, store: store)
        HostSettings.setProgressBar(true, store: store)
        HostSettings.setBackgroundColor("#abcdef", store: store)

        HostSettings.restoreDefaults(store: store)

        // Everything falls back to the baked defaults again.
        XCTAssertFalse(HostSettings.toolbar(store: store, bakedDefault: false))
        XCTAssertEqual(HostSettings.toolbarStyle(store: store, bakedDefault: .regular), .regular)
        XCTAssertFalse(HostSettings.progressBar(store: store, bakedDefault: false))
        XCTAssertEqual(HostSettings.backgroundColor(store: store, bakedDefault: "#1a73e8"), "#1a73e8")
        XCTAssertNil(HostSettings.backgroundColor(store: store, bakedDefault: nil))
    }
}

final class ToolbarStyleTests: XCTestCase {
    func testParseKnownValues() {
        XCTAssertEqual(ToolbarStyle.parse("regular"), .regular)
        XCTAssertEqual(ToolbarStyle.parse("compact"), .compact)
    }

    func testParseNilAndUnknownFallBackToDefault() {
        XCTAssertEqual(ToolbarStyle.parse(nil), .default)
        XCTAssertEqual(ToolbarStyle.parse(""), .default)
        XCTAssertEqual(ToolbarStyle.parse("Regular"), .default) // case-sensitive raw values
        XCTAssertEqual(ToolbarStyle.parse("huge"), .default)
    }

    func testDefaultIsRegular() {
        XCTAssertEqual(ToolbarStyle.default, .regular)
    }
}
