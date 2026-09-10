import XCTest
@testable import webwrap

// Tests for the pure helpers shared by the interactive and flag-driven create paths:
// slug/bundle-id derivation (AppBuilder) and the name suggestion (Create).

final class SlugTests: XCTestCase {
    func testLowercasesAndHyphenates() {
        XCTAssertEqual(AppBuilder.slug(from: "Microsoft Outlook"), "microsoft-outlook")
    }

    func testCollapsesNonAlphanumericRuns() {
        XCTAssertEqual(AppBuilder.slug(from: "Foo!!  Bar / Baz"), "foo-bar-baz")
    }

    func testEmptyFallsBackToApp() {
        XCTAssertEqual(AppBuilder.slug(from: ""), "app")
        XCTAssertEqual(AppBuilder.slug(from: "   "), "app")
        XCTAssertEqual(AppBuilder.slug(from: "!!!"), "app")
    }
}

final class BundleIdTests: XCTestCase {
    func testDerivesFromName() {
        XCTAssertEqual(AppBuilder.defaultBundleId(name: "Outlook", override: nil),
                       "dk.yepz.webwrap.outlook")
    }

    func testOverrideWins() {
        XCTAssertEqual(AppBuilder.defaultBundleId(name: "Outlook", override: "com.acme.mail"),
                       "com.acme.mail")
    }

    func testEmptyOverrideIgnored() {
        XCTAssertEqual(AppBuilder.defaultBundleId(name: "Outlook", override: ""),
                       "dk.yepz.webwrap.outlook")
    }
}

final class SuggestNameTests: XCTestCase {
    func testTakesFirstHostLabelCapitalized() {
        XCTAssertEqual(Create.suggestName(fromURL: "https://outlook.office.com"), "Outlook")
    }

    func testStripsWww() {
        XCTAssertEqual(Create.suggestName(fromURL: "https://www.example.com"), "Example")
    }

    func testSingleLabelHost() {
        XCTAssertEqual(Create.suggestName(fromURL: "http://localhost:8080"), "Localhost")
    }

    func testNilWhenNoHost() {
        XCTAssertNil(Create.suggestName(fromURL: "not a url"))
    }
}

final class BackgroundColorValidationTests: XCTestCase {
    func testAcceptsHexColors() throws {
        XCTAssertNoThrow(try Create.validate(backgroundColor: "#1a73e8"))
        XCTAssertNoThrow(try Create.validate(backgroundColor: "#fff"))
    }

    func testRejectsJunk() {
        XCTAssertThrowsError(try Create.validate(backgroundColor: "not-a-color")) { error in
            XCTAssertTrue("\(error)".contains("hex color"))
        }
    }
}

// The `--x` / `--no-x` guards. Passing both is a contradiction the CLI must refuse rather
// than silently pick a winner; nothing exercised these before (#55).
final class ExclusiveFlagValidationTests: XCTestCase {
    func testValueWithItsClearFlagIsRejected() {
        XCTAssertThrowsError(try Create.validateExclusive(
            value: "#1a73e8", clear: true, flag: "background-color")) { error in
            XCTAssertEqual("\(error)",
                           "`--background-color` and `--no-background-color` are mutually exclusive.")
        }
    }

    func testEitherFlagAloneIsAccepted() {
        XCTAssertNoThrow(try Create.validateExclusive(value: "safari", clear: false, flag: "user-agent"))
        XCTAssertNoThrow(try Create.validateExclusive(value: nil, clear: true, flag: "user-agent"))
        XCTAssertNoThrow(try Create.validateExclusive(value: nil, clear: false, flag: "user-agent"))
    }

    func testMessageNamesThePairItGuards() {
        // Each call site passes its own flag name; a wrong one would misdirect the user.
        XCTAssertThrowsError(try Create.validateExclusive(
            value: "https://example.com", clear: true, flag: "url")) { error in
            XCTAssertEqual("\(error)", "`--url` and `--no-url` are mutually exclusive.")
        }
    }
}
