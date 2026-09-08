import XCTest
@testable import webwrap

// Tests for the pure parts of the notary-staple step: the retry schedule and the
// notarized-but-unstapled failure message. The stapling itself runs real processes and is
// hand-verified per repo convention (see #97 — the bug was precisely that stapling was
// assumed rather than verified).

final class StapleRetryScheduleTests: XCTestCase {
    func testAttemptCountIncludesTheImmediateFirstTry() {
        // The delays are the *pauses between* attempts, so there's one more attempt than
        // there are delays. The failure message quotes this number.
        XCTAssertEqual(AppBuilder.stapleRetryDelays.count + 1, 6)
    }

    func testBudgetCoversApplesObservedTicketLag() {
        // The lag that caused #97 was ~2 minutes, but most runs staple on the first or
        // second try; ~1 minute is the compromise. Guard both ends so a future edit can't
        // silently make it useless (too short) or make every failure a long hang (too long).
        let total = AppBuilder.stapleRetryDelays.reduce(0, +)
        XCTAssertGreaterThanOrEqual(total, 60)
        XCTAssertLessThanOrEqual(total, 120)
    }

    func testDelaysBackOffRatherThanPollFlatly() {
        let delays = AppBuilder.stapleRetryDelays
        XCTAssertFalse(delays.isEmpty)
        XCTAssertTrue(delays.allSatisfy { $0 > 0 })
        for (a, b) in zip(delays, delays.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b, "schedule must not shrink: \(delays)")
        }
    }
}

final class StapleFailureMessageTests: XCTestCase {
    private func message(appPath: String = "/tmp/Example.app",
                         output: String = "Error 65") -> String {
        AppBuilder.stapleFailureMessage(appPath: appPath, output: output)
    }

    func testSaysTheAppIsNotarizedButNotStapled() {
        // The whole point: the user must not read this as "notarization failed" and resubmit,
        // nor as a success.
        let m = message()
        XCTAssertTrue(m.contains("IS notarized"))
        XCTAssertTrue(m.contains("NOT stapled"))
        XCTAssertTrue(m.contains("Notarization succeeded"))
    }

    func testExplainsTheConsequenceForTheRecipient() {
        // A stapled ticket is what makes Gatekeeper work offline; say so, or the user can't
        // judge whether shipping it matters.
        XCTAssertTrue(message().contains("offline"))
    }

    func testGivesBothManualCommands() {
        let m = message()
        XCTAssertTrue(m.contains("xcrun stapler staple"))
        XCTAssertTrue(m.contains("xcrun stapler validate"))
    }

    func testQuotesThePathSoNamesWithSpacesArePasteable() {
        // Generated app names routinely contain spaces, and an unquoted path in the fix
        // instructions would fail for the user at the worst moment.
        let m = message(appPath: "/Applications/My Reader.app")
        XCTAssertTrue(m.contains("xcrun stapler staple \"/Applications/My Reader.app\""))
        XCTAssertTrue(m.contains("xcrun stapler validate \"/Applications/My Reader.app\""))
    }

    func testWarnsAgainstTrustingSpctl() {
        // spctl reports "accepted" on the signing machine even with no ticket — believing it
        // is how an unstapled app gets shipped.
        let m = message()
        XCTAssertTrue(m.contains("spctl"))
        XCTAssertTrue(m.contains("stapler validate"))
    }

    func testQuotesTheAttemptCountFromTheSchedule() {
        XCTAssertTrue(message().contains("\(AppBuilder.stapleRetryDelays.count + 1) attempts"))
    }

    func testIncludesCapturedStaplerOutput() {
        XCTAssertTrue(message(output: "could not find the ticket")
            .contains("could not find the ticket"))
        XCTAssertTrue(message(output: "could not find the ticket").contains("stapler said:"))
    }

    func testOmitsTheOutputSectionWhenThereIsNothingToShow() {
        // No dangling "stapler said:" header with nothing under it.
        for empty in ["", "   ", "\n\t "] {
            XCTAssertFalse(message(output: empty).contains("stapler said:"), "for \(empty.debugDescription)")
        }
    }
}

// The two commands' output is merged by runCapturingAll (stdout+stderr in one pipe), so the
// failure message has to say which one complained — recovering these diagnostics is the whole
// point of #97.
final class StapleDiagnosticsTests: XCTestCase {
    func testLabelsBothCommandsWithTheirExitStatus() {
        let d = AppBuilder.stapleDiagnostics(staple: (0, "stapled ok-ish"),
                                             validate: (65, "does not have a ticket"))
        XCTAssertTrue(d.contains("stapler staple (exit 0):"))
        XCTAssertTrue(d.contains("stapler validate (exit 65):"))
        XCTAssertTrue(d.contains("stapled ok-ish"))
        XCTAssertTrue(d.contains("does not have a ticket"))
    }

    func testAttributesOutputToTheRightCommand() {
        // The bug this guards: unlabelled concatenation made it impossible to tell whether
        // staple or validate produced a given line.
        let d = AppBuilder.stapleDiagnostics(staple: (1, "STAPLE_SAID"),
                                             validate: (66, "VALIDATE_SAID"))
        let stapleIdx = d.range(of: "STAPLE_SAID")!.lowerBound
        let validateIdx = d.range(of: "VALIDATE_SAID")!.lowerBound
        XCTAssertTrue(d.range(of: "stapler staple (exit 1):")!.lowerBound < stapleIdx)
        XCTAssertTrue(d.range(of: "stapler validate (exit 66):")!.lowerBound < validateIdx)
        XCTAssertTrue(stapleIdx < validateIdx)
    }

    func testDropsSilentCommandsRatherThanLeavingBareHeaders() {
        // stapler often says nothing on success; a header with no body is noise.
        let onlyValidate = AppBuilder.stapleDiagnostics(staple: (0, "   "),
                                                        validate: (65, "no ticket"))
        XCTAssertFalse(onlyValidate.contains("stapler staple"))
        XCTAssertTrue(onlyValidate.contains("stapler validate (exit 65):"))

        let neither = AppBuilder.stapleDiagnostics(staple: (0, ""), validate: (65, "\n\t "))
        XCTAssertTrue(neither.isEmpty)
    }

    func testEmptyDiagnosticsProduceNoOutputSectionInTheMessage() {
        // Ties the two pure pieces together: nothing captured → no dangling "stapler said:".
        let d = AppBuilder.stapleDiagnostics(staple: (0, ""), validate: (65, ""))
        XCTAssertFalse(AppBuilder.stapleFailureMessage(appPath: "/tmp/X.app", output: d)
            .contains("stapler said:"))
    }
}
