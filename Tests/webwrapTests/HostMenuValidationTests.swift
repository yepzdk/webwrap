import XCTest
import AppKit
@testable import webwrap

// The host's menu validation is AppKit wiring, verified by hand — except for the one
// part that silently broke it (#116): `validateMenuItem(_:)` was plain Swift, so the
// Objective-C runtime couldn't see it, AppKit's `respondsToSelector:` check failed, and
// every validated item stayed enabled. This asserts the exposure, not the decisions.

final class HostMenuValidationTests: XCTestCase {
    func testValidateMenuItemIsVisibleToTheObjectiveCRuntime() {
        // Exactly the check AppKit makes before consulting a menu item's target. It
        // passes because the class declares `NSMenuItemValidation`, which turns the
        // method into an @objc protocol requirement; drop that and this fails again.
        XCTAssertTrue(HostDelegate.instancesRespond(
            to: #selector(NSMenuItemValidation.validateMenuItem(_:))))
    }
}
