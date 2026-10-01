import XCTest
@testable import webwrap

// Tests for reading an existing bundle's signing identity back out of `codesign -dvv`
// output, and for what `update` then signs with (#117). Pure — no codesign is run.

final class CodesignOutputTests: XCTestCase {
    /// A real `codesign -dvv` report for a Developer-ID-signed bundle, trimmed.
    private let developerID = """
        Executable=/Applications/Example.app/Contents/MacOS/webwrap-example
        Identifier=dk.yepz.webwrap.example
        Format=app bundle with Mach-O universal (x86_64 arm64)
        CodeDirectory v=20500 size=1234 flags=0x10000(runtime) hashes=30+7
        Signature size=9000
        Authority=Developer ID Application: Jesper Example (AB12CD34EF)
        Authority=Developer ID Certification Authority
        Authority=Apple Root CA
        Timestamp=1 Sep 2026 at 10.00.00
        Info.plist entries=30
        TeamIdentifier=AB12CD34EF
        Runtime Version=14.0.0
        Sealed Resources version=2 rules=13 files=6
        """

    func testReadsDeveloperIDIdentity() {
        XCTAssertEqual(BundleSigning.developerIDIdentity(inCodesignOutput: developerID),
                       "Developer ID Application: Jesper Example (AB12CD34EF)")
    }

    func testAdHocSignatureHasNoIdentity() {
        // An ad-hoc signature carries no certificate chain at all.
        let adHoc = """
            Executable=/Applications/Example.app/Contents/MacOS/webwrap-example
            Identifier=dk.yepz.webwrap.example
            CodeDirectory v=20400 size=1234 flags=0x2(adhoc) hashes=30+7
            Signature=adhoc
            Info.plist entries=30
            Sealed Resources version=2 rules=13 files=6
            """
        XCTAssertNil(BundleSigning.developerIDIdentity(inCodesignOutput: adHoc))
    }

    func testIntermediateAuthoritiesAreNotMistakenForTheIdentity() {
        // "Developer ID Certification Authority" is Apple's intermediate, not an
        // identity that can be passed back to `codesign --sign`.
        let noLeaf = """
            Authority=Apple Development: Someone (AB12CD34EF)
            Authority=Developer ID Certification Authority
            Authority=Apple Root CA
            """
        XCTAssertNil(BundleSigning.developerIDIdentity(inCodesignOutput: noLeaf))
    }

    func testUnsignedBundleHasNoIdentity() {
        XCTAssertNil(BundleSigning.developerIDIdentity(
            inCodesignOutput: "/Applications/Example.app: code object is not signed at all"))
        XCTAssertNil(BundleSigning.developerIDIdentity(inCodesignOutput: ""))
    }
}

final class UpdateSigningResolutionTests: XCTestCase {
    private let existing = "Developer ID Application: Jesper Example (AB12CD34EF)"

    func testExistingIdentityIsCarriedOver() {
        // The regression: a routine `update --width 1400` must not come back ad-hoc.
        let resolved = OptionDefaults.resolveUpdateSigning(
            noSign: false, sign: nil, existingIdentity: existing)
        XCTAssertEqual(resolved.signIdentity, existing)
        XCTAssertTrue(resolved.carriedOver)
    }

    func testExplicitSignWins() {
        let other = "Developer ID Application: Someone Else (ZZ99YY88XX)"
        let resolved = OptionDefaults.resolveUpdateSigning(
            noSign: false, sign: other, existingIdentity: existing)
        XCTAssertEqual(resolved.signIdentity, other)
        XCTAssertFalse(resolved.carriedOver)
    }

    func testNoSignWins() {
        // An explicit downgrade is still allowed — it just can't happen by accident.
        let resolved = OptionDefaults.resolveUpdateSigning(
            noSign: true, sign: nil, existingIdentity: existing)
        XCTAssertNil(resolved.signIdentity)
        XCTAssertFalse(resolved.carriedOver)
    }

    func testAdHocAppStaysAdHoc() {
        let resolved = OptionDefaults.resolveUpdateSigning(
            noSign: false, sign: nil, existingIdentity: nil)
        XCTAssertNil(resolved.signIdentity)
        XCTAssertFalse(resolved.carriedOver)
    }
}
