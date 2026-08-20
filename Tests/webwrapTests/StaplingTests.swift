import XCTest
@testable import webwrap

// Tests for the stapling retry/backoff schedule and the "notarized but not stapled"
// failure message — pure logic, no stapler/notarytool invocation.

final class StaplingBackoffTests: XCTestCase {
    func testFirstAttemptHasNoDelay() {
        XCTAssertEqual(AppBuilder.stapleBackoff(beforeAttempt: 1), 0)
    }

    func testBackoffGrows() {
        XCTAssertEqual(AppBuilder.stapleBackoff(beforeAttempt: 2), 5)
        XCTAssertEqual(AppBuilder.stapleBackoff(beforeAttempt: 3), 15)
    }

    func testBackoffIsCappedForLaterAttempts() {
        XCTAssertEqual(AppBuilder.stapleBackoff(beforeAttempt: 4), 30)
        XCTAssertEqual(AppBuilder.stapleBackoff(beforeAttempt: 99), 30)
    }

    func testAttemptsIsGreaterThanOne() {
        // The whole point is to retry; a single attempt would defeat the mechanism.
        XCTAssertGreaterThan(AppBuilder.stapleAttempts, 1)
    }
}

final class NotStapledMessageTests: XCTestCase {
    func testStatesNotarizedButNotStapled() {
        let msg = AppBuilder.notStapledMessage(appPath: "/tmp/Example.app", output: "")
        XCTAssertTrue(msg.contains("notarized"))
        XCTAssertTrue(msg.contains("not be stapled"))
    }

    func testProvidesManualStapleCommand() {
        let msg = AppBuilder.notStapledMessage(appPath: "/tmp/Example.app", output: "")
        XCTAssertTrue(msg.contains("xcrun stapler staple \"/tmp/Example.app\""))
    }

    func testSurfacesStaplerOutput() {
        let msg = AppBuilder.notStapledMessage(
            appPath: "/tmp/Example.app",
            output: "The staple and validate action failed! Error 65.")
        XCTAssertTrue(msg.contains("The staple and validate action failed! Error 65."))
    }

    func testEmptyOutputHasNoStrayBlankLine() {
        let msg = AppBuilder.notStapledMessage(appPath: "/tmp/Example.app", output: "   \n  ")
        XCTAssertFalse(msg.contains("\n\n"))
    }
}
