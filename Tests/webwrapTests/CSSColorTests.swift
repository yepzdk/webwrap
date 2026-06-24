import XCTest
@testable import webwrap

// Tests for the pure CSS hex-color parser used to paint the window background from the
// manifest. No AppKit involved.

final class CSSColorTests: XCTestCase {
    private func assertRGBA(_ string: String,
                            _ r: Double, _ g: Double, _ b: Double, _ a: Double,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let c = CSSColor.parse(string) else {
            return XCTFail("expected \(string) to parse", file: file, line: line)
        }
        XCTAssertEqual(c.red, r, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(c.green, g, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(c.blue, b, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(c.alpha, a, accuracy: 0.001, file: file, line: line)
    }

    func testSixDigitHex() {
        assertRGBA("#ffffff", 1, 1, 1, 1)
        assertRGBA("#000000", 0, 0, 0, 1)
        assertRGBA("#1a73e8", 26/255, 115/255, 232/255, 1)
    }

    func testThreeDigitShorthand() {
        // #abc expands to #aabbcc.
        assertRGBA("#fff", 1, 1, 1, 1)
        assertRGBA("#abc", 0xaa/255.0, 0xbb/255.0, 0xcc/255.0, 1)
    }

    func testEightDigitHexWithAlpha() {
        assertRGBA("#00000080", 0, 0, 0, 128/255)
    }

    func testFourDigitShorthandWithAlpha() {
        // #f008 → #ff000088.
        assertRGBA("#f008", 1, 0, 0, 0x88/255.0)
    }

    func testCaseInsensitiveAndTrimmed() {
        assertRGBA("  #FFFFFF  ", 1, 1, 1, 1)
    }

    func testRejectsNonHexForms() {
        // Named colors and rgb()/hsl() are intentionally unsupported (→ default bg).
        XCTAssertNil(CSSColor.parse("white"))
        XCTAssertNil(CSSColor.parse("rgb(255,255,255)"))
        XCTAssertNil(CSSColor.parse("#xyz"))
        XCTAssertNil(CSSColor.parse("#12"))      // wrong length
        XCTAssertNil(CSSColor.parse("#1234567"))  // 7 digits
        XCTAssertNil(CSSColor.parse(""))
    }
}
