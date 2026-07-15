import XCTest
import Foundation
@testable import webwrap

// Tests for AppRegistry: the pure plist parser and table renderer, plus the directory
// scan exercised against a temp directory.

final class AppRegistryParseTests: XCTestCase {
    private func plist(_ pairs: [String: String], includeURL: Bool = true) -> Data {
        var dict = pairs
        if includeURL, dict["WebWrapURL"] == nil { dict["WebWrapURL"] = "https://example.com" }
        return try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    func testParsesWebwrapApp() {
        let data = plist([
            "WebWrapURL": "https://outlook.office.com",
            "CFBundleName": "Outlook",
            "CFBundleIdentifier": "dk.yepz.webwrap.outlook",
        ])
        let app = AppRegistry.parse(plistData: data, appPath: "/Applications/Outlook.app")
        XCTAssertEqual(app, WebWrapApp(name: "Outlook",
                                       url: "https://outlook.office.com",
                                       bundleId: "dk.yepz.webwrap.outlook",
                                       path: "/Applications/Outlook.app"))
    }

    func testNilWhenNoWebWrapURL() {
        // A normal (non-webwrap) app: has a name but no WebWrapURL marker.
        let data = plist(["CFBundleName": "Safari"], includeURL: false)
        XCTAssertNil(AppRegistry.parse(plistData: data, appPath: "/Applications/Safari.app"))
    }

    func testNilForMalformedData() {
        XCTAssertNil(AppRegistry.parse(plistData: Data("not a plist".utf8),
                                       appPath: "/Applications/X.app"))
    }

    func testFallsBackToFilenameWhenNameMissing() {
        let data = plist(["WebWrapURL": "https://x.test"])
        let app = AppRegistry.parse(plistData: data, appPath: "/Applications/My Tool.app")
        XCTAssertEqual(app?.name, "My Tool")
    }
}

final class AppRegistryRenderTests: XCTestCase {
    func testEmptyStateMessage() {
        let out = AppRegistry.renderTable([])
        XCTAssertTrue(out.hasPrefix("No webwrap apps found"))
    }

    func testTableHasHeaderRowsAndCount() {
        let apps = [
            WebWrapApp(name: "Alpha", url: "https://a.test", bundleId: "x.a", path: "/Applications/Alpha.app"),
            WebWrapApp(name: "Beta", url: "https://b.test", bundleId: "x.b", path: "/Applications/Beta.app"),
        ]
        let out = AppRegistry.renderTable(apps)
        XCTAssertTrue(out.contains("NAME"))
        XCTAssertTrue(out.contains("URL"))
        XCTAssertTrue(out.contains("LOCATION"))
        XCTAssertTrue(out.contains("Alpha"))
        XCTAssertTrue(out.contains("https://b.test"))
        XCTAssertTrue(out.contains("/Applications"))
        XCTAssertTrue(out.hasSuffix("2 apps"))
    }

    func testSingularCount() {
        let apps = [WebWrapApp(name: "Solo", url: "https://s.test", bundleId: "x.s", path: "/Applications/Solo.app")]
        XCTAssertTrue(AppRegistry.renderTable(apps).hasSuffix("1 app"))
    }

    func testHandlerOnlyAppShowsLabelInsteadOfURL() {
        let apps = [WebWrapApp(name: "Reader", url: "", bundleId: "x.r", path: "/Applications/Reader.app")]
        XCTAssertTrue(AppRegistry.renderTable(apps).contains("(handler-only)"))
    }
}

final class AppRegistryAbbreviateTests: XCTestCase {
    func testAbbreviatesHomePrefix() {
        let home = NSHomeDirectory()
        XCTAssertEqual(AppRegistry.abbreviate(home + "/Applications"), "~/Applications")
        XCTAssertEqual(AppRegistry.abbreviate(home), "~")
    }

    func testLeavesNonHomePathsUntouched() {
        XCTAssertEqual(AppRegistry.abbreviate("/Applications"), "/Applications")
    }

    func testDirectoryOfBundle() {
        XCTAssertEqual(AppRegistry.directory(of: "/Applications/Foo.app"), "/Applications")
    }
}

final class AppRegistryDiscoverTests: XCTestCase {
    /// Writes a minimal .app with the given Info.plist dict into `dir`.
    private func makeApp(named name: String, plist: [String: String], in dir: String) throws {
        let contents = (dir as NSString)
            .appendingPathComponent("\(name).app/Contents")
        try FileManager.default.createDirectory(atPath: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: (contents as NSString).appendingPathComponent("Info.plist")))
    }

    func testDiscoversOnlyWebwrapAppsSortedByName() throws {
        let tmp = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("webwrap-discover-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        try makeApp(named: "Zeta", plist: ["WebWrapURL": "https://z.test", "CFBundleName": "Zeta"], in: tmp)
        try makeApp(named: "Alpha", plist: ["WebWrapURL": "https://a.test", "CFBundleName": "Alpha"], in: tmp)
        try makeApp(named: "NotOurs", plist: ["CFBundleName": "NotOurs"], in: tmp) // no WebWrapURL

        let found = AppRegistry.discover(in: [tmp])
        XCTAssertEqual(found.map(\.name), ["Alpha", "Zeta"]) // sorted, NotOurs excluded
        XCTAssertEqual(found.first?.url, "https://a.test")
    }

    func testSkipsMissingDirectories() {
        let found = AppRegistry.discover(in: ["/no/such/dir/here"])
        XCTAssertTrue(found.isEmpty)
    }
}
