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
                       height: Int = 800,
                       showToolbar: Bool = false,
                       toolbarStyle: ToolbarStyle = .default,
                       progressBar: Bool = false,
                       backgroundColor: String? = nil,
                       userAgent: String? = nil,
                       handleURLs: Bool = false,
                       openAnyURL: Bool = false,
                       externalLinks: Bool = true,
                       creatorVersion: String = "0.3.0") -> String {
        AppBuilder.makeInfoPlist(
            name: name, url: url, bundleId: bundleId,
            executable: "webwrap-host", iconFile: "AppIcon.icns",
            width: width, height: height, showToolbar: showToolbar,
            toolbarStyle: toolbarStyle,
            progressBar: progressBar,
            backgroundColor: backgroundColor, userAgent: userAgent,
            handleURLs: handleURLs,
            openAnyURL: openAnyURL, externalLinks: externalLinks,
            creatorVersion: creatorVersion)
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
        // Creator version is baked in for the generated app's About panel.
        XCTAssertTrue(xml.contains("<key>WebWrapCreatorVersion</key>\n    <string>0.3.0</string>"))
        // Toolbar defaults off.
        XCTAssertTrue(xml.contains("<key>WebWrapToolbar</key>\n    <string>0</string>"))
    }

    func testProgressBarKeyReflectsFlag() {
        XCTAssertTrue(plist(progressBar: true).contains("<key>WebWrapProgressBar</key>\n    <string>1</string>"))
        XCTAssertTrue(plist(progressBar: false).contains("<key>WebWrapProgressBar</key>\n    <string>0</string>"))
    }

    func testToolbarKeyReflectsFlag() {
        XCTAssertTrue(plist(showToolbar: true).contains("<key>WebWrapToolbar</key>\n    <string>1</string>"))
        XCTAssertTrue(plist(showToolbar: false).contains("<key>WebWrapToolbar</key>\n    <string>0</string>"))
    }

    func testToolbarStyleKeyReflectsValue() {
        XCTAssertTrue(plist(toolbarStyle: .regular).contains("<key>WebWrapToolbarStyle</key>\n    <string>regular</string>"))
        XCTAssertTrue(plist(toolbarStyle: .compact).contains("<key>WebWrapToolbarStyle</key>\n    <string>compact</string>"))
    }

    func testURLHandlingKeysReflectFlags() {
        let on = plist(handleURLs: true, openAnyURL: true)
        XCTAssertTrue(on.contains("<key>WebWrapHandleURLs</key>\n    <string>1</string>"))
        XCTAssertTrue(on.contains("<key>WebWrapOpenAnyURL</key>\n    <string>1</string>"))
        let off = plist(handleURLs: false, openAnyURL: false)
        XCTAssertTrue(off.contains("<key>WebWrapHandleURLs</key>\n    <string>0</string>"))
        XCTAssertTrue(off.contains("<key>WebWrapOpenAnyURL</key>\n    <string>0</string>"))
    }

    func testHandlerOnlyPlistKeepsMarkerKeyAndURLTypes() {
        // An empty URL still bakes the WebWrapURL marker (it identifies webwrap apps
        // everywhere), and handler-only callers force URL handling on.
        let xml = plist(url: "", handleURLs: true, openAnyURL: true)
        XCTAssertTrue(xml.contains("<key>WebWrapURL</key>\n    <string></string>"))
        XCTAssertTrue(xml.contains("<key>WebWrapHandleURLs</key>\n    <string>1</string>"))
        XCTAssertTrue(xml.contains("<key>WebWrapOpenAnyURL</key>\n    <string>1</string>"))
        XCTAssertTrue(xml.contains("<key>CFBundleURLTypes</key>"))
    }

    func testExternalLinksKeyReflectsFlag() {
        // Default (on) bakes "1"; --no-external-links bakes "0".
        XCTAssertTrue(plist().contains("<key>WebWrapExternalLinks</key>\n    <string>1</string>"))
        XCTAssertTrue(plist(externalLinks: false).contains("<key>WebWrapExternalLinks</key>\n    <string>0</string>"))
    }

    func testCFBundleURLTypesOnlyWhenHandlingURLs() {
        XCTAssertFalse(plist(handleURLs: false).contains("CFBundleURLTypes"))
        let on = plist(handleURLs: true)
        XCTAssertTrue(on.contains("<key>CFBundleURLTypes</key>"))
        XCTAssertTrue(on.contains("<string>http</string>"))
        XCTAssertTrue(on.contains("<string>https</string>"))
        XCTAssertTrue(on.contains("<key>CFBundleTypeRole</key>"))
    }

    func testRemainsValidPlistWithURLTypes() throws {
        // Guard the conditional CFBundleURLTypes block against whitespace breakage.
        let xml = plist(backgroundColor: "#1a73e8", handleURLs: true, openAnyURL: true)
        let obj = try PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil)
        let dict = try XCTUnwrap(obj as? [String: Any])
        XCTAssertEqual(dict["WebWrapHandleURLs"] as? String, "1")
        XCTAssertEqual(dict["WebWrapOpenAnyURL"] as? String, "1")
        let types = try XCTUnwrap(dict["CFBundleURLTypes"] as? [[String: Any]])
        let first: [String: Any] = try XCTUnwrap(types.first)
        let schemesAny: Any = try XCTUnwrap(first["CFBundleURLSchemes"])
        let schemes = try XCTUnwrap(schemesAny as? [String])
        XCTAssertEqual(schemes, ["http", "https"])
    }

    func testBackgroundColorKeyOmittedWhenNil() {
        XCTAssertFalse(plist(backgroundColor: nil).contains("WebWrapBackgroundColor"))
    }

    func testBackgroundColorKeyEmittedWhenSet() {
        XCTAssertTrue(plist(backgroundColor: "#1a73e8")
            .contains("<key>WebWrapBackgroundColor</key>\n    <string>#1a73e8</string>"))
    }

    func testRemainsValidPlistWithBackgroundColor() throws {
        // Guards the conditional-line interpolation against stray-whitespace breakage.
        let xml = plist(backgroundColor: "#1a73e8")
        let obj = try PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil)
        let dict = try XCTUnwrap(obj as? [String: Any])
        XCTAssertEqual(dict["WebWrapBackgroundColor"] as? String, "#1a73e8")
        XCTAssertEqual(dict["WebWrapToolbar"] as? String, "0")
    }

    func testUserAgentKeyOmittedWhenNil() {
        XCTAssertFalse(plist(userAgent: nil).contains("WebWrapUserAgent"))
    }

    func testUserAgentKeyEmittedWhenSet() {
        XCTAssertTrue(plist(userAgent: "edge")
            .contains("<key>WebWrapUserAgent</key>\n    <string>edge</string>"))
    }

    func testRemainsValidPlistWithUserAgent() throws {
        // A custom UA can contain XML-significant characters; guard the escaping.
        let xml = plist(userAgent: "Custom <UA> & \"quotes\"")
        let obj = try PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil)
        let dict = try XCTUnwrap(obj as? [String: Any])
        XCTAssertEqual(dict["WebWrapUserAgent"] as? String, "Custom <UA> & \"quotes\"")
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
