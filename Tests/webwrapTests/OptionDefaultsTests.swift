import XCTest
@testable import webwrap

// Tests for the pure option-seed / mode-decision logic backing the interactive flows.
// The stdin orchestration (promptForOptions) and Prompt.askWithDefault read real stdin
// and are verified by hand, per the repo convention.

final class OptionDefaultsForCreateTests: XCTestCase {
    func testCoalescesFlagsAndTakesManifestBackground() {
        let seed = OptionDefaults.forCreate(
            width: 1200, height: 800, toolbar: false, toolbarStyle: .regular, progressBar: false,
            handleURLs: false, openAnyURL: false, externalLinks: true, reader: false,
            iconPath: nil, manifestBackground: "#1a73e8", explicitBackground: nil,
            userAgent: nil,
            noSign: false, signIdentity: nil, notarize: false, notaryProfile: nil)
        XCTAssertEqual(seed, OptionSeed(
            width: 1200, height: 800, toolbar: false, toolbarStyle: .regular, progressBar: false,
            handleURLs: false, openAnyURL: false, externalLinks: true, reader: false,
            iconPath: nil, backgroundColor: "#1a73e8", userAgent: nil,
            noSign: false, signIdentity: nil, notarize: false, notaryProfile: nil))
    }

    func testExplicitBackgroundOverridesManifest() {
        let seed = OptionDefaults.forCreate(
            width: 1200, height: 800, toolbar: false, toolbarStyle: .regular, progressBar: false,
            handleURLs: false, openAnyURL: false, externalLinks: true, reader: false,
            iconPath: nil, manifestBackground: "#1a73e8", explicitBackground: "#ff0000",
            userAgent: nil,
            noSign: false, signIdentity: nil, notarize: false, notaryProfile: nil)
        XCTAssertEqual(seed.backgroundColor, "#ff0000")
    }

    func testCarriesExplicitFlagValues() {
        let seed = OptionDefaults.forCreate(
            width: 1000, height: 700, toolbar: true, toolbarStyle: .compact, progressBar: true,
            handleURLs: true, openAnyURL: true, externalLinks: false, reader: true,
            iconPath: "/tmp/x.png", manifestBackground: nil, explicitBackground: nil,
            userAgent: "edge",
            noSign: true, signIdentity: "Developer ID Application: X", notarize: false, notaryProfile: nil)
        XCTAssertEqual(seed.width, 1000)
        XCTAssertEqual(seed.height, 700)
        XCTAssertTrue(seed.toolbar)
        XCTAssertEqual(seed.toolbarStyle, .compact)
        XCTAssertTrue(seed.progressBar)
        XCTAssertTrue(seed.handleURLs)
        XCTAssertTrue(seed.openAnyURL)
        XCTAssertFalse(seed.externalLinks)
        XCTAssertTrue(seed.reader)
        XCTAssertEqual(seed.iconPath, "/tmp/x.png")
        XCTAssertNil(seed.backgroundColor)
        XCTAssertEqual(seed.userAgent, "edge")
        XCTAssertTrue(seed.noSign)
        XCTAssertEqual(seed.signIdentity, "Developer ID Application: X")
    }
}

final class OptionDefaultsForUpdateTests: XCTestCase {
    private let existing = AppConfig(
        url: "https://github.com", name: "GitHub", bundleId: "dk.yepz.webwrap.github",
        width: 1400, height: 900, showToolbar: true, toolbarStyle: .compact,
        progressBar: true, backgroundColor: "#0d1117",
        userAgent: "chrome",
        handleURLs: true, openAnyURL: false,
        externalLinks: false, reader: true)

    func testMapsPersistedConfigToSeed() {
        let seed = OptionDefaults.forUpdate(existing: existing)
        XCTAssertEqual(seed.width, 1400)
        XCTAssertEqual(seed.height, 900)
        XCTAssertTrue(seed.toolbar)
        XCTAssertEqual(seed.toolbarStyle, .compact)
        XCTAssertTrue(seed.progressBar)
        XCTAssertEqual(seed.backgroundColor, "#0d1117")
        XCTAssertEqual(seed.userAgent, "chrome")
        XCTAssertTrue(seed.handleURLs)
        XCTAssertFalse(seed.openAnyURL)
        XCTAssertFalse(seed.externalLinks)
        XCTAssertTrue(seed.reader)
    }

    func testIconAndSigningAreNotSeededFromConfig() {
        // Neither is persisted, so the seed is "keep existing" icon (nil) and ad-hoc signing.
        let seed = OptionDefaults.forUpdate(existing: existing)
        XCTAssertNil(seed.iconPath)
        XCTAssertFalse(seed.noSign)
        XCTAssertNil(seed.signIdentity)
        XCTAssertFalse(seed.notarize)
        XCTAssertNil(seed.notaryProfile)
    }
}

final class ResolveUpdateBackgroundTests: XCTestCase {
    // The result is a String??: nil = carry over, .some(nil) = clear, .some(x) = set.

    func testClearWinsOverEverything() {
        let r = OptionDefaults.resolveUpdateBackground(
            explicit: "#ff0000", clear: true, urlChanged: true, reResolved: "#00ff00")
        // .some(nil) — cleared, despite an explicit color and a re-resolved value.
        guard case .some(let inner) = r else { return XCTFail("expected .some") }
        XCTAssertNil(inner)
    }

    func testExplicitBeatsReResolved() {
        let r = OptionDefaults.resolveUpdateBackground(
            explicit: "#ff0000", clear: false, urlChanged: true, reResolved: "#00ff00")
        XCTAssertEqual(r, .some("#ff0000"))
    }

    func testUrlChangedAdoptsReResolved() {
        let r = OptionDefaults.resolveUpdateBackground(
            explicit: nil, clear: false, urlChanged: true, reResolved: "#00ff00")
        XCTAssertEqual(r, .some("#00ff00"))
    }

    func testUrlChangedToSiteWithoutColorClears() {
        // The color follows the new site: no manifest color → .some(nil) (clear).
        let r = OptionDefaults.resolveUpdateBackground(
            explicit: nil, clear: false, urlChanged: true, reResolved: nil)
        guard case .some(let inner) = r else { return XCTFail("expected .some") }
        XCTAssertNil(inner)
    }

    func testNoChangeCarriesOver() {
        let r = OptionDefaults.resolveUpdateBackground(
            explicit: nil, clear: false, urlChanged: false, reResolved: nil)
        // nil — carry over the existing color.
        XCTAssertEqual(r, .none)
    }
}

final class ResolveUpdateUserAgentTests: XCTestCase {
    // The result is a String??: nil = carry over, .some(nil) = reset, .some(x) = set.

    func testClearWinsOverExplicit() {
        let r = OptionDefaults.resolveUpdateUserAgent(explicit: "edge", clear: true)
        guard case .some(let inner) = r else { return XCTFail("expected .some") }
        XCTAssertNil(inner)
    }

    func testExplicitSets() {
        XCTAssertEqual(OptionDefaults.resolveUpdateUserAgent(explicit: "edge", clear: false),
                       .some("edge"))
    }

    func testNoFlagsCarriesOver() {
        XCTAssertEqual(OptionDefaults.resolveUpdateUserAgent(explicit: nil, clear: false), .none)
    }
}

final class ResolveOpenAnyURLTests: XCTestCase {
    func testOnlyWhenBothOn() {
        XCTAssertTrue(OptionDefaults.resolveOpenAnyURL(handleURLs: true, openAnyURL: true))
        XCTAssertFalse(OptionDefaults.resolveOpenAnyURL(handleURLs: true, openAnyURL: false))
        // Off-domain is meaningless without handling, so it's forced off.
        XCTAssertFalse(OptionDefaults.resolveOpenAnyURL(handleURLs: false, openAnyURL: true))
        XCTAssertFalse(OptionDefaults.resolveOpenAnyURL(handleURLs: false, openAnyURL: false))
    }
}

final class CreateModeTests: XCTestCase {
    func testBothPresentIsNonInteractive() {
        XCTAssertEqual(OptionDefaults.createMode(isInteractive: true, hasURL: true, hasName: true),
                       .nonInteractive)
        // Even off a TTY, both present builds directly.
        XCTAssertEqual(OptionDefaults.createMode(isInteractive: false, hasURL: true, hasName: true),
                       .nonInteractive)
    }

    func testMissingOnTTYPrompts() {
        XCTAssertEqual(OptionDefaults.createMode(isInteractive: true, hasURL: false, hasName: true),
                       .interactive)
        XCTAssertEqual(OptionDefaults.createMode(isInteractive: true, hasURL: true, hasName: false),
                       .interactive)
    }

    func testMissingOffTTYIsMissingInput() {
        XCTAssertEqual(OptionDefaults.createMode(isInteractive: false, hasURL: false, hasName: false),
                       .missingInput)
    }
}

final class UpdateModeTests: XCTestCase {
    func testBareOnTTYIsInteractive() {
        XCTAssertEqual(OptionDefaults.updateMode(isInteractive: true, anyOptionFlag: false, force: false),
                       .interactive)
    }

    func testAnyFlagOrForceIsNonInteractive() {
        XCTAssertEqual(OptionDefaults.updateMode(isInteractive: true, anyOptionFlag: true, force: false),
                       .nonInteractive)
        XCTAssertEqual(OptionDefaults.updateMode(isInteractive: true, anyOptionFlag: false, force: true),
                       .nonInteractive)
    }

    func testNonTTYBareIsNonInteractive() {
        // Off a TTY with no flags: not interactive (the run() then requires --force).
        XCTAssertEqual(OptionDefaults.updateMode(isInteractive: false, anyOptionFlag: false, force: false),
                       .nonInteractive)
    }
}
