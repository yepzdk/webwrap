import XCTest
@testable import webwrap

// Tests for the signing/notarization flag validation and summary description — pure
// logic, no codesign/notarytool invocation.

final class SigningValidationTests: XCTestCase {
    private func validate(noSign: Bool = false, sign: String? = nil,
                          notarize: Bool = false, notaryProfile: String? = nil) throws {
        try Create.validateSigning(noSign: noSign, sign: sign,
                                   notarize: notarize, notaryProfile: notaryProfile)
    }

    func testDefaultAdHocIsValid() throws {
        XCTAssertNoThrow(try validate()) // nothing set → ad-hoc, fine
    }

    func testNoSignAloneIsValid() throws {
        XCTAssertNoThrow(try validate(noSign: true))
    }

    func testSignAloneIsValid() throws {
        XCTAssertNoThrow(try validate(sign: "Developer ID Application: X (TEAMID)"))
    }

    func testSignAndNotarizeWithProfileIsValid() throws {
        XCTAssertNoThrow(try validate(sign: "Developer ID Application: X (TEAMID)",
                                      notarize: true, notaryProfile: "webwrap"))
    }

    func testNoSignWithSignConflicts() {
        XCTAssertThrowsError(try validate(noSign: true, sign: "Developer ID Application: X")) { error in
            XCTAssertTrue("\(error)".contains("mutually exclusive"))
        }
    }

    func testNotarizeWithoutSignFails() {
        XCTAssertThrowsError(try validate(notarize: true, notaryProfile: "webwrap")) { error in
            XCTAssertTrue("\(error)".contains("requires `--sign`"))
        }
    }

    func testNotarizeWithoutProfileFails() {
        XCTAssertThrowsError(try validate(sign: "Developer ID Application: X", notarize: true)) { error in
            XCTAssertTrue("\(error)".contains("--notary-profile"))
        }
    }

    func testNotarizeWithEmptyProfileFails() {
        XCTAssertThrowsError(try validate(sign: "Developer ID Application: X",
                                          notarize: true, notaryProfile: ""))
    }
}

final class SigningDescriptionTests: XCTestCase {
    func testNoSign() {
        XCTAssertEqual(Create.signingDescription(noSign: true, sign: nil, notarize: false),
                       "none (--no-sign)")
    }

    func testAdHocDefault() {
        XCTAssertEqual(Create.signingDescription(noSign: false, sign: nil, notarize: false),
                       "ad-hoc")
    }

    func testDeveloperID() {
        XCTAssertEqual(
            Create.signingDescription(noSign: false, sign: "Developer ID Application: X (T)", notarize: false),
            "Developer ID (Developer ID Application: X (T))")
    }

    func testDeveloperIDNotarized() {
        XCTAssertEqual(
            Create.signingDescription(noSign: false, sign: "Developer ID Application: X (T)", notarize: true),
            "Developer ID + notarized (Developer ID Application: X (T))")
    }
}

// The error text for a tool that exited non-zero. Losing this output is what made a
// codesign failure unactionable (#105).
final class ProcessFailureMessageTests: XCTestCase {
    func testIncludesWhatTheToolSaid() {
        let message = AppBuilder.processFailureMessage(
            command: "/usr/bin/codesign", status: 1,
            output: "error: The specified item could not be found in the keychain.")
        XCTAssertTrue(message.contains("/usr/bin/codesign"))
        XCTAssertTrue(message.contains("status 1"))
        XCTAssertTrue(message.contains("could not be found in the keychain"))
    }

    func testSilentFailureStillNamesCommandAndStatus() {
        // Some tools fail without a word; the message must not end in a dangling colon.
        for silent in ["", "   ", "\n\t "] {
            let message = AppBuilder.processFailureMessage(
                command: "/usr/bin/iconutil", status: 65, output: silent)
            XCTAssertEqual(message, "/usr/bin/iconutil exited with status 65.",
                           "for \(silent.debugDescription)")
        }
    }
}
