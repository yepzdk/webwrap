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
