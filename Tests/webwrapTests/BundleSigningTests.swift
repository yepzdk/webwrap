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

final class CodesigningIdentityListTests: XCTestCase {
    func testReadsIdentityNames() {
        let output = """
            Policy: Code Signing
              1) A1B2C3D4E5F60718293A4B5C6D7E8F9001122334 "Developer ID Application: Jesper Example (AB12CD34EF)"
              2) 0011223344556677889900AABBCCDDEEFF001122 "Apple Development: Someone (ZZ99YY88XX)"
                 2 identities found

                 Valid identities only (*) 2 valid identities found
            """
        XCTAssertEqual(BundleSigning.codesigningIdentities(inSecurityOutput: output),
                       ["Developer ID Application: Jesper Example (AB12CD34EF)",
                        "Apple Development: Someone (ZZ99YY88XX)"])
    }

    func testNoIdentitiesInKeychain() {
        XCTAssertEqual(BundleSigning.codesigningIdentities(
            inSecurityOutput: "     0 valid identities found"), [])
        XCTAssertEqual(BundleSigning.codesigningIdentities(inSecurityOutput: ""), [])
    }
}

final class UpdateSigningResolutionTests: XCTestCase {
    private let existing = "Developer ID Application: Jesper Example (AB12CD34EF)"
    /// Stands in for a keychain that holds the app's own identity.
    private func available(_ identity: String) -> Bool { identity == existing }
    /// Stands in for another Mac's keychain, which holds nothing we can sign with.
    private func unavailable(_: String) -> Bool { false }

    func testExistingIdentityIsCarriedOver() {
        // The regression: a routine `update --width 1400` must not come back ad-hoc.
        let resolved = OptionDefaults.resolveUpdateSigning(
            noSign: false, sign: nil, existingIdentity: existing, isAvailable: available)
        XCTAssertEqual(resolved.signIdentity, existing)
        XCTAssertTrue(resolved.carriedOver)
    }

    func testUnavailableIdentityFallsBackToAdHoc() {
        // On a Mac without the private key, codesign would fail after the old bundle
        // is gone — an ad-hoc app beats no app (#117).
        let resolved = OptionDefaults.resolveUpdateSigning(
            noSign: false, sign: nil, existingIdentity: existing, isAvailable: unavailable)
        XCTAssertNil(resolved.signIdentity)
        XCTAssertFalse(resolved.carriedOver)
    }

    func testExplicitSignIsNotKeychainChecked() {
        // `--sign` is the user's own claim: codesign reports a bad one before the
        // rebuild starts, and second-guessing it here would break legitimate uses.
        let other = "Developer ID Application: Someone Else (ZZ99YY88XX)"
        let resolved = OptionDefaults.resolveUpdateSigning(
            noSign: false, sign: other, existingIdentity: existing, isAvailable: unavailable)
        XCTAssertEqual(resolved.signIdentity, other)
        XCTAssertFalse(resolved.carriedOver)
    }

    func testNoSignWins() {
        // An explicit downgrade is still allowed — it just can't happen by accident.
        let resolved = OptionDefaults.resolveUpdateSigning(
            noSign: true, sign: nil, existingIdentity: existing, isAvailable: available)
        XCTAssertNil(resolved.signIdentity)
        XCTAssertFalse(resolved.carriedOver)
    }

    func testAdHocAppStaysAdHoc() {
        let resolved = OptionDefaults.resolveUpdateSigning(
            noSign: false, sign: nil, existingIdentity: nil, isAvailable: available)
        XCTAssertNil(resolved.signIdentity)
        XCTAssertFalse(resolved.carriedOver)
    }

    func testKeychainIsNotProbedWhenFlagsDecide() {
        // The probe shells out to `security`, so it must not run when the answer is
        // already known from the command line.
        var probes = 0
        let counting: (String) -> Bool = { _ in probes += 1; return true }
        _ = OptionDefaults.resolveUpdateSigning(
            noSign: true, sign: nil, existingIdentity: existing, isAvailable: counting)
        _ = OptionDefaults.resolveUpdateSigning(
            noSign: false, sign: "Developer ID Application: Other (ZZ99YY88XX)",
            existingIdentity: existing, isAvailable: counting)
        XCTAssertEqual(probes, 0)
    }
}
