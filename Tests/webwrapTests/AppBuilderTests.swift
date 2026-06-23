import XCTest
import Foundation
@testable import webwrap

// Tests for AppBuilder's pure plist/escaping helpers — string generation only, no
// filesystem or process side effects.

final class XMLEscapeTests: XCTestCase {
    func testEscapesAllFiveEntities() {
        XCTAssertEqual(AppBuilder.xmlEscape("&"), "&amp;")
        XCTAssertEqual(AppBuilder.xmlEscape("<"), "&lt;")
        XCTAssertEqual(AppBuilder.xmlEscape(">"), "&gt;")
        XCTAssertEqual(AppBuilder.xmlEscape("\""), "&quot;")
        XCTAssertEqual(AppBuilder.xmlEscape("'"), "&apos;")
    }

    func testAmpersandEscapedFirstNoDoubleEscaping() {
        // "<" must become "&lt;", not "&amp;lt;" — i.e. the '&' from other entities
        // is not itself re-escaped.
        XCTAssertEqual(AppBuilder.xmlEscape("a < b & c"), "a &lt; b &amp; c")
    }

    func testPlainStringUntouched() {
        XCTAssertEqual(AppBuilder.xmlEscape("Outlook"), "Outlook")
    }
}

final class InfoPlistTests: XCTestCase {
    private func plist(name: String = "Outlook",
                       url: String = "https://outlook.office.com",
                       bundleId: String = "dk.yepz.webwrap.outlook",
                       width: Int = 1200,
                       height: Int = 800) -> String {
        AppBuilder.makeInfoPlist(
            name: name, url: url, bundleId: bundleId,
            executable: "webwrap-host", iconFile: "AppIcon.icns",
            width: width, height: height)
    }

    func testContainsExpectedKeysAndValues() {
        let xml = plist()
        XCTAssertTrue(xml.contains("<key>CFBundleExecutable</key>\n    <string>webwrap-host</string>"))
        XCTAssertTrue(xml.contains("<key>CFBundleIdentifier</key>\n    <string>dk.yepz.webwrap.outlook</string>"))
        XCTAssertTrue(xml.contains("<key>WebWrapURL</key>\n    <string>https://outlook.office.com</string>"))
        XCTAssertTrue(xml.contains("<key>WebWrapWidth</key>\n    <string>1200</string>"))
        XCTAssertTrue(xml.contains("<key>WebWrapHeight</key>\n    <string>800</string>"))
        // Host-mode marker must be present so the launched bundle runs as the web host.
        XCTAssertTrue(xml.contains("<key>WEBWRAP_HOST</key>"))
    }

    func testEscapesNameAndURL() {
        let xml = plist(name: "Tom & Jerry", url: "https://x.test/?a=1&b=<2>")
        XCTAssertTrue(xml.contains("<string>Tom &amp; Jerry</string>"))
        XCTAssertTrue(xml.contains("https://x.test/?a=1&amp;b=&lt;2&gt;"))
        // The raw, unescaped ampersand must not leak into the XML.
        XCTAssertFalse(xml.contains("Tom & Jerry"))
    }

    func testParsesAsValidPlistAndRoundTrips() throws {
        let xml = plist(name: "Tom & Jerry", url: "https://x.test/?a=1&b=2")
        let data = Data(xml.utf8)
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dict = try XCTUnwrap(obj as? [String: Any])

        XCTAssertEqual(dict["CFBundleName"] as? String, "Tom & Jerry")
        XCTAssertEqual(dict["WebWrapURL"] as? String, "https://x.test/?a=1&b=2")
        XCTAssertEqual(dict["CFBundleExecutable"] as? String, "webwrap-host")
        let env = try XCTUnwrap(dict["LSEnvironment"] as? [String: Any])
        XCTAssertEqual(env["WEBWRAP_HOST"] as? String, "1")
    }
}
