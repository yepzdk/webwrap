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

        // A real main menu is required for the standard editing shortcuts (⌘C/⌘V/⌘X/⌘A)
        // to reach the focused web content — without it, paste silently does nothing.
        // It also provides Quit and the About panel.
        NSApp.mainMenu = buildMainMenu(appName: title)

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu

    private func buildMainMenu(appName: String) -> NSMenu {
        let mainMenu = NSMenu()

        // App menu: About, Hide, Quit.
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(showAbout(_:)), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu: the standard responder-chain editing actions (this is what makes
        // copy/paste/cut/select-all work inside the web view).
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // View menu: reload and back/forward for the wrapped site.
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Reload", action: #selector(reloadPage(_:)), keyEquivalent: "r").target = self
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Back", action: #selector(goBack(_:)), keyEquivalent: "[").target = self
        viewMenu.addItem(withTitle: "Forward", action: #selector(goForward(_:)), keyEquivalent: "]").target = self

        // Window menu: Minimize/Zoom, registered so macOS manages window items.
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    @objc private func showAbout(_ sender: Any?) {
        let appName = info("CFBundleName") ?? "WebWrap"
        let version = info("CFBundleShortVersionString") ?? "1.0"
        let credits = HostAbout.credits(url: info("WebWrapURL"),
                                        creatorVersion: info("WebWrapCreatorVersion"))
        let attributed = NSAttributedString(
            string: credits,
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appName,
            .applicationVersion: version,
            .credits: attributed,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func reloadPage(_ sender: Any?) { webView.reload() }
    @objc private func goBack(_ sender: Any?) { webView.goBack() }
    @objc private func goForward(_ sender: Any?) { webView.goForward() }

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

/// Pure text for the generated app's About panel. Kept free of AppKit so it's
/// unit-testable.
enum HostAbout {
    static func credits(url: String?, creatorVersion: String?) -> String {
        var lines: [String] = []
        if let url, !url.isEmpty {
            lines.append("Opens: \(url)")
        }
        if let creatorVersion, !creatorVersion.isEmpty {
            lines.append("Created with webwrap \(creatorVersion)")
        } else {
            lines.append("Created with webwrap")
        }
        return lines.joined(separator: "\n")
    }
}
