import XCTest
@testable import webwrap

// Tests for FallbackIcon's pure color/monogram/contrast helpers. The bitmap drawing in
// `pngData` is AppKit and verified by hand; a light smoke test at the bottom exercises it
// on the macOS CI runner (it's a no-op elsewhere since AppKit only exists on macOS).

final class FallbackIconFillColorTests: XCTestCase {
    private func assertRGB(_ background: String?,
                           _ r: Double, _ g: Double, _ b: Double,
                           file: StaticString = #filePath, line: UInt = #line) {
        let c = FallbackIcon.fillColor(background: background)
        XCTAssertEqual(c.red, r, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(c.green, g, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(c.blue, b, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(c.alpha, 1.0, accuracy: 0.001, file: file, line: line)
    }

    func testValidHexParses() {
        assertRGB("#8b0000", 0x8b / 255.0, 0, 0)
        assertRGB("#ffffff", 1, 1, 1)
        assertRGB("#abc", 0xaa / 255.0, 0xbb / 255.0, 0xcc / 255.0)
    }

    func testNilFallsBackToNeutral() {
        let c = FallbackIcon.fillColor(background: nil)
        XCTAssertEqual(c, FallbackIcon.neutralDefault)
    }

    func testUnparseableFallsBackToNeutral() {
        // Named colors and garbage aren't hex — CSSColor.parse returns nil.
        XCTAssertEqual(FallbackIcon.fillColor(background: "rebeccapurple"), FallbackIcon.neutralDefault)
        XCTAssertEqual(FallbackIcon.fillColor(background: "not a color"), FallbackIcon.neutralDefault)
        XCTAssertEqual(FallbackIcon.fillColor(background: ""), FallbackIcon.neutralDefault)
    }

    func testFullyTransparentFallsBackToNeutral() {
        // An icon needs an opaque backdrop; a zero-alpha color can't provide one.
        XCTAssertEqual(FallbackIcon.fillColor(background: "#00000000"), FallbackIcon.neutralDefault)
    }

    func testAlphaIsDroppedToOpaque() {
        // A semi-transparent color keeps its RGB but is forced opaque.
        assertRGB("#8b000080", 0x8b / 255.0, 0, 0)
    }
}

final class FallbackIconMonogramTests: XCTestCase {
    func testFirstLetterUppercased() {
        XCTAssertEqual(FallbackIcon.monogram(for: "Slack"), "S")
        XCTAssertEqual(FallbackIcon.monogram(for: "example"), "E")
    }

    func testDigitIsAccepted() {
        XCTAssertEqual(FallbackIcon.monogram(for: "1Password"), "1")
    }

    func testLeadingSymbolsAndWhitespaceSkipped() {
        XCTAssertEqual(FallbackIcon.monogram(for: "  @home"), "H")
        XCTAssertEqual(FallbackIcon.monogram(for: "!!!Bang"), "B")
    }

    func testNoAlphanumericFallsBackToW() {
        XCTAssertEqual(FallbackIcon.monogram(for: ""), "W")
        XCTAssertEqual(FallbackIcon.monogram(for: "   "), "W")
        XCTAssertEqual(FallbackIcon.monogram(for: "!@#$"), "W")
    }
}

final class FallbackIconContrastTests: XCTestCase {
    func testDarkBackdropWantsLightText() {
        XCTAssertFalse(FallbackIcon.prefersDarkText(on: CSSColor.parse("#000000")!))
        XCTAssertFalse(FallbackIcon.prefersDarkText(on: CSSColor.parse("#8b0000")!))
        XCTAssertFalse(FallbackIcon.prefersDarkText(on: FallbackIcon.neutralDefault))
    }

    func testLightBackdropWantsDarkText() {
        XCTAssertTrue(FallbackIcon.prefersDarkText(on: CSSColor.parse("#ffffff")!))
        XCTAssertTrue(FallbackIcon.prefersDarkText(on: CSSColor.parse("#ffe066")!))
    }
}

#if canImport(AppKit)
final class FallbackIconRenderTests: XCTestCase {
    func testProducesPNGData() {
        // A tiny render is enough to prove the AppKit drawing path returns real PNG bytes.
        guard let data = FallbackIcon.pngData(background: "#8b0000", name: "Fallback Test", size: 64) else {
            return XCTFail("expected fallback PNG data")
        }
        XCTAssertFalse(data.isEmpty)
        // PNG magic number: 89 50 4E 47 0D 0A 1A 0A.
        let magic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertEqual(Array(data.prefix(8)), magic)
    }

    func testWorksWithNoBackgroundColor() {
        // Handler-only path: no background color, still a well-formed icon.
        let data = FallbackIcon.pngData(background: nil, name: "Handler Test", size: 64)
        XCTAssertNotNil(data)
    }
}
#endif
