import XCTest
@testable import webwrap

// The only pure, testable bit of Prompt: cancel-word detection. The stdin I/O itself is
// hand-verified, per the repo convention.

final class PromptCancelTests: XCTestCase {
    func testRecognizesCancelWords() {
        XCTAssertTrue(Prompt.isCancel("q"))
        XCTAssertTrue(Prompt.isCancel("quit"))
        XCTAssertTrue(Prompt.isCancel("cancel"))
    }

    func testCaseAndWhitespaceInsensitive() {
        XCTAssertTrue(Prompt.isCancel("  Q  "))
        XCTAssertTrue(Prompt.isCancel("Cancel"))
        XCTAssertTrue(Prompt.isCancel("QUIT"))
    }

    func testOrdinaryInputIsNotCancel() {
        XCTAssertFalse(Prompt.isCancel(""))
        XCTAssertFalse(Prompt.isCancel("y"))
        XCTAssertFalse(Prompt.isCancel("quality")) // not a cancel word
        XCTAssertFalse(Prompt.isCancel("https://github.com"))
    }
}
