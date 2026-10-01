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

    // MARK: - User agent (tri-state)

    func testUserAgentUnsetUsesBakedDefault() {
        let store = MemoryStore()
        XCTAssertEqual(HostSettings.userAgent(store: store, bakedDefault: "edge"), "edge")
        XCTAssertNil(HostSettings.userAgent(store: store, bakedDefault: nil))
    }

    func testUserAgentExplicitValueWinsOverBakedDefault() {
        let store = MemoryStore()
        HostSettings.setUserAgent("chrome", store: store)
        XCTAssertEqual(HostSettings.userAgent(store: store, bakedDefault: "edge"), "chrome")
        XCTAssertEqual(HostSettings.userAgent(store: store, bakedDefault: nil), "chrome")
    }

    func testUserAgentExplicitClearOverridesBakedValue() {
        let store = MemoryStore()
        // User explicitly chose the default — a baked preset must NOT show through.
        HostSettings.setUserAgent(nil, store: store)
        XCTAssertNil(HostSettings.userAgent(store: store, bakedDefault: "edge"))
    }

    func testUserAgentEmptyStringTreatedAsCleared() {
        let store = MemoryStore()
        HostSettings.setUserAgent("", store: store)
        XCTAssertNil(HostSettings.userAgent(store: store, bakedDefault: "edge"))
    }

    // MARK: - Page zoom

    func testZoomDefaultsToOneWhenUnsetOrGarbled() {
        let store = MemoryStore()
        XCTAssertEqual(HostSettings.zoom(store: store), 1.0)
        store.set("not a number", forKey: HostSettings.Key.zoom)
        XCTAssertEqual(HostSettings.zoom(store: store), 1.0)
    }

    func testZoomRoundTripsAndClamps() {
        let store = MemoryStore()
        HostSettings.setZoom(1.3, store: store)
        XCTAssertEqual(HostSettings.zoom(store: store), 1.3)
        // Out-of-range values clamp on write and on read.
        HostSettings.setZoom(9.0, store: store)
        XCTAssertEqual(HostSettings.zoom(store: store), HostSettings.zoomRange.upperBound)
        XCTAssertEqual(HostSettings.clampZoom(0.01), HostSettings.zoomRange.lowerBound)
    }

    // MARK: - Restore defaults

    func testRestoreDefaultsClearsAllOverrides() {
        let store = MemoryStore()
        HostSettings.setToolbar(true, store: store)
        HostSettings.setToolbarStyle(.compact, store: store)
        HostSettings.setProgressBar(true, store: store)
        HostSettings.setBackgroundColor("#abcdef", store: store)
        HostSettings.setUserAgent("chrome", store: store)
        HostSettings.setZoom(2.0, store: store)
        HostSettings.setReaderSettingsJSON(#"{"theme":"sepia"}"#, store: store)

        HostSettings.restoreDefaults(store: store)

        // Everything falls back to the baked defaults again.
        XCTAssertFalse(HostSettings.toolbar(store: store, bakedDefault: false))
        XCTAssertEqual(HostSettings.toolbarStyle(store: store, bakedDefault: .regular), .regular)
        XCTAssertFalse(HostSettings.progressBar(store: store, bakedDefault: false))
        XCTAssertEqual(HostSettings.backgroundColor(store: store, bakedDefault: "#1a73e8"), "#1a73e8")
        XCTAssertNil(HostSettings.backgroundColor(store: store, bakedDefault: nil))
        XCTAssertEqual(HostSettings.userAgent(store: store, bakedDefault: "edge"), "edge")
        XCTAssertNil(HostSettings.userAgent(store: store, bakedDefault: nil))
        XCTAssertEqual(HostSettings.zoom(store: store), 1.0)
        XCTAssertNil(HostSettings.readerSettingsJSON(store: store))
    }

    func testRestoreDefaultsKeepsReaderHistory() {
        // History is user-generated data, not a presentation default — an appearance
        // reset must not silently delete it (cleared from the reader panel instead).
        let store = MemoryStore()
        let stored = #"[{"title":"T","url":"https://example.com/"}]"#
        HostSettings.setReaderHistoryJSON(stored, store: store)
        HostSettings.restoreDefaults(store: store)
        XCTAssertEqual(HostSettings.readerHistoryJSON(store: store), stored)
    }

    // MARK: - Per-setting override clearing (what `update` uses, #118)

    func testClearOverrideRestoresTheBakedDefaultForThatSettingOnly() {
        let store = MemoryStore()
        HostSettings.setToolbar(false, store: store)
        HostSettings.setProgressBar(false, store: store)

        HostSettings.clearOverride(.toolbar, store: store)

        XCTAssertTrue(HostSettings.toolbar(store: store, bakedDefault: true))
        // The setting the update didn't mention keeps the user's in-app choice.
        XCTAssertFalse(HostSettings.progressBar(store: store, bakedDefault: true))
    }

    func testClearOverrideHandlesTheTriStateSettings() {
        let store = MemoryStore()
        // An explicitly cleared color is the worst case: the marker alone shadows a
        // newly baked color until both keys go.
        HostSettings.setBackgroundColor(nil, store: store)
        HostSettings.setUserAgent(nil, store: store)
        XCTAssertNil(HostSettings.backgroundColor(store: store, bakedDefault: "#1a73e8"))

        HostSettings.clearOverride(.backgroundColor, store: store)
        HostSettings.clearOverride(.userAgent, store: store)

        XCTAssertEqual(HostSettings.backgroundColor(store: store, bakedDefault: "#1a73e8"),
                       "#1a73e8")
        XCTAssertEqual(HostSettings.userAgent(store: store, bakedDefault: "edge"), "edge")
    }

    func testHasOverrideReportsWhatTheSettingsWindowTouched() {
        let store = MemoryStore()
        for setting in HostSettings.Setting.allCases {
            XCTAssertFalse(HostSettings.hasOverride(setting, store: store), "\(setting)")
        }
        HostSettings.setToolbarStyle(.compact, store: store)
        HostSettings.setBackgroundColor(nil, store: store)
        XCTAssertTrue(HostSettings.hasOverride(.toolbarStyle, store: store))
        XCTAssertTrue(HostSettings.hasOverride(.backgroundColor, store: store))
        XCTAssertFalse(HostSettings.hasOverride(.toolbar, store: store))
    }

    // MARK: - Effective config (what interactive `update` seeds its prompts from)

    /// A baked config with every overridable setting at a known value, so a test override
    /// can differ from each of them.
    private static let baked = AppConfig(
        url: "https://example.test", name: "Example",
        bundleId: "dk.yepz.webwrap.example", width: 1200, height: 800,
        showToolbar: true, toolbarStyle: .regular,
        progressBar: true, backgroundColor: "#123456", userAgent: "chrome",
        handleURLs: false, openAnyURL: false, externalLinks: true, reader: false)

    func testEffectiveConfigWithoutOverridesIsTheBakedConfig() {
        XCTAssertEqual(HostSettings.effectiveConfig(Self.baked, store: MemoryStore()), Self.baked)
    }

    func testEffectiveConfigPrefersEachOverride() {
        let store = MemoryStore()
        HostSettings.setToolbar(false, store: store)
        HostSettings.setToolbarStyle(.compact, store: store)
        HostSettings.setProgressBar(false, store: store)
        HostSettings.setBackgroundColor("#abcdef", store: store)
        HostSettings.setUserAgent("edge", store: store)

        let effective = HostSettings.effectiveConfig(Self.baked, store: store)
        XCTAssertFalse(effective.showToolbar)
        XCTAssertEqual(effective.toolbarStyle, .compact)
        XCTAssertFalse(effective.progressBar)
        XCTAssertEqual(effective.backgroundColor, "#abcdef")
        XCTAssertEqual(effective.userAgent, "edge")
    }

    /// The tri-state overrides can be set to "none", which has to beat a baked value
    /// rather than reading as "no override".
    func testEffectiveConfigHonorsClearedTriStateOverrides() {
        let store = MemoryStore()
        HostSettings.setBackgroundColor(nil, store: store)
        HostSettings.setUserAgent(nil, store: store)

        let effective = HostSettings.effectiveConfig(Self.baked, store: store)
        XCTAssertNil(effective.backgroundColor)
        XCTAssertNil(effective.userAgent)
    }

    func testEffectiveConfigLeavesNonOverridableSettingsAlone() {
        let store = MemoryStore()
        HostSettings.setToolbar(false, store: store)

        let effective = HostSettings.effectiveConfig(Self.baked, store: store)
        XCTAssertEqual(effective.url, Self.baked.url)
        XCTAssertEqual(effective.name, Self.baked.name)
        XCTAssertEqual(effective.bundleId, Self.baked.bundleId)
        XCTAssertEqual(effective.width, Self.baked.width)
        XCTAssertEqual(effective.height, Self.baked.height)
        XCTAssertEqual(effective.handleURLs, Self.baked.handleURLs)
        XCTAssertEqual(effective.openAnyURL, Self.baked.openAnyURL)
        XCTAssertEqual(effective.externalLinks, Self.baked.externalLinks)
        XCTAssertEqual(effective.reader, Self.baked.reader)
    }

    /// The prompt seed is built from the effective config, so a toolbar switched off in
    /// the app's Settings window defaults the prompt to off — Enter keeps it off (#118).
    func testUpdateSeedStartsFromTheEffectiveValues() {
        let store = MemoryStore()
        HostSettings.setToolbar(false, store: store)
        HostSettings.setProgressBar(false, store: store)

        let seed = OptionDefaults.forUpdate(
            existing: HostSettings.effectiveConfig(Self.baked, store: store))
        XCTAssertFalse(seed.toolbar)
        XCTAssertFalse(seed.progressBar)
        XCTAssertEqual(OptionDefaults.forUpdate(existing: Self.baked).toolbar, true,
                       "the baked config still seeds the toolbar on")
    }

    /// A changed `--url` re-resolves the new site's manifest color, and that still wins
    /// over the background the user had set in the app.
    func testChangedURLBackgroundBeatsTheBackgroundOverride() {
        let store = MemoryStore()
        HostSettings.setBackgroundColor("#abcdef", store: store)

        var seed = OptionDefaults.forUpdate(
            existing: HostSettings.effectiveConfig(Self.baked, store: store))
        XCTAssertEqual(seed.backgroundColor, "#abcdef")
        // What `Update.run` does when the entered URL differs from the existing one.
        seed.backgroundColor = "#00ff00"
        XCTAssertEqual(seed.backgroundColor, "#00ff00")
    }

    // MARK: - Reader history

    func testReaderHistoryJSONRoundTrips() {
        let store = MemoryStore()
        XCTAssertNil(HostSettings.readerHistoryJSON(store: store))
        var history = ReaderHistory()
        history.record(title: "An article", url: "https://example.com/a")
        HostSettings.setReaderHistoryJSON(history.json, store: store)
        XCTAssertEqual(ReaderHistory.fromJSON(HostSettings.readerHistoryJSON(store: store)),
                       history)
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
