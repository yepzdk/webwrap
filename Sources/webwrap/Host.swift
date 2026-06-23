import Cocoa
import WebKit
import CryptoKit

// Host mode: launched by macOS when the user opens a generated .app.
// Reads its configuration from the bundle's Info.plist (baked in at create time)
// and presents a single WKWebView window. Cookies/sessions are persisted to a
// per-app data store so each wrapped app stays logged in independently.

private final class HostDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var webView: WKWebView!

    private func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    /// Returns a persistent, on-disk data store so logins/cookies survive relaunch.
    ///
    /// On macOS 14+ each app gets its OWN isolated store, keyed to a stable UUID
    /// derived from the bundle identifier — so two webwrap apps can hold two
    /// independent logins (e.g. two Microsoft accounts) without colliding.
    ///
    /// On macOS 13 the per-identifier API doesn't exist, so we fall back to the
    /// shared persistent default store. Sessions still persist; they're just not
    /// isolated between apps on that older OS.
    static func makeDataStore() -> WKWebsiteDataStore {
        if #available(macOS 14.0, *) {
            let bundleId = Bundle.main.bundleIdentifier ?? "dk.yepz.webwrap.app"
            return WKWebsiteDataStore(forIdentifier: stableUUID(from: bundleId))
        } else {
            return .default()
        }
    }

    /// Deterministically maps a string to a UUID (RFC-4122 v5-style, SHA-256
    /// truncated to 16 bytes with version/variant bits set). The same bundle ID
    /// always yields the same store identifier across launches.
    private static func stableUUID(from string: String) -> UUID {
        var hasher = SHA256()
        hasher.update(data: Data(string.utf8))
        let digest = Array(hasher.finalize())
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        let uuid = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                    bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                    bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: uuid)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let urlString = info("WebWrapURL") ?? "about:blank"
        let title = info("CFBundleName") ?? "WebWrap"
        let width = Double(info("WebWrapWidth") ?? "1200") ?? 1200
        let height = Double(info("WebWrapHeight") ?? "800") ?? 800

        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.makeDataStore()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.setFrameAutosaveName("WebWrapMainWindow") // remembers size/position per app

        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        window.contentView!.addSubview(webView)

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // Handle target=_blank / window.open by loading in the same view rather than
    // silently dropping the navigation.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

func runHost() {
    let app = NSApplication.shared
    let delegate = HostDelegate()
    app.delegate = delegate
    // Retain the delegate for the lifetime of the process.
    _ = Unmanaged.passRetained(delegate)
    app.run()
}
