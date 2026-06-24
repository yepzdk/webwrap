import Cocoa
import WebKit
import CryptoKit

// Host mode: launched by macOS when the user opens a generated .app.
// Reads its configuration from the bundle's Info.plist (baked in at create time)
// and presents a single WKWebView window. Cookies/sessions are persisted to a
// per-app data store so each wrapped app stays logged in independently.

private final class HostDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, NSToolbarDelegate {
    var window: NSWindow!
    var webView: WKWebView!

    /// KVO observations on the web view's navigation state, kept alive so the toolbar
    /// back/forward buttons can enable/disable themselves. Empty when no toolbar.
    private var navObservers: [NSKeyValueObservation] = []
    // The embedded buttons themselves, not their NSToolbarItems: for a custom-view
    // toolbar item, NSToolbarItem.isEnabled does NOT propagate to the embedded control,
    // so enable/disable must target the NSButton directly.
    private weak var backButton: NSButton?
    private weak var forwardButton: NSButton?

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

        // Paint the window (and the web view's own backing) with the manifest's
        // background color so the first frame isn't a white flash before the page
        // renders. Skipped when there's no color or it isn't a form we parse.
        if let raw = info("WebWrapBackgroundColor"), let rgba = CSSColor.parse(raw) {
            let color = NSColor(red: rgba.red, green: rgba.green,
                                blue: rgba.blue, alpha: rgba.alpha)
            window.backgroundColor = color
            webView.setValue(false, forKey: "drawsBackground") // let the window color show through
        }

        // A real main menu is required for the standard editing shortcuts (⌘C/⌘V/⌘X/⌘A)
        // to reach the focused web content — without it, paste silently does nothing.
        // It also provides Quit and the About panel.
        NSApp.mainMenu = buildMainMenu(appName: title)

        // Optional navigation toolbar (opt-in via WebWrapToolbar). Off keeps the
        // chromeless look; on shows back/forward/reload in the window's title bar.
        if info("WebWrapToolbar") == "1" {
            installToolbar()
        }

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
        editMenu.addItem(.separator())
        // Copy the current page's URL — useful because the chromeless window has no
        // address bar. ⌘C is already Copy (selected content), so this uses ⌘⇧C.
        let copyURL = editMenu.addItem(withTitle: "Copy Current URL",
                                       action: #selector(copyCurrentURL(_:)), keyEquivalent: "c")
        copyURL.keyEquivalentModifierMask = [.command, .shift]
        copyURL.target = self

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

    // MARK: - Toolbar

    /// Static description of one toolbar button. Drives both the item factory and the
    /// identifier lists, so adding a button is a single table entry.
    private struct ToolbarButton {
        let id: NSToolbarItem.Identifier
        let symbol: String       // SF Symbol name (macOS 11+)
        let fallbackTitle: String // text title on older systems lacking the symbol
        let action: Selector
    }

    private static let backItemID = NSToolbarItem.Identifier("WebWrapBack")
    private static let forwardItemID = NSToolbarItem.Identifier("WebWrapForward")
    private static let reloadItemID = NSToolbarItem.Identifier("WebWrapReload")

    private static let toolbarButtons: [ToolbarButton] = [
        ToolbarButton(id: backItemID, symbol: "chevron.backward",
                      fallbackTitle: "Back", action: #selector(goBack(_:))),
        ToolbarButton(id: forwardItemID, symbol: "chevron.forward",
                      fallbackTitle: "Forward", action: #selector(goForward(_:))),
        ToolbarButton(id: reloadItemID, symbol: "arrow.clockwise",
                      fallbackTitle: "Reload", action: #selector(reloadPage(_:))),
    ]

    /// Adds a navigation toolbar (back/forward/reload) to the window and wires the
    /// back/forward buttons to enable/disable as the web view's history changes.
    private func installToolbar() {
        let toolbar = NSToolbar(identifier: "WebWrapNavigationToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }

        // Refresh once the items exist (setting `window.toolbar` may not have built them
        // synchronously) so the initial enabled state matches a fresh, history-less view.
        updateNavEnablement()

        // Track history changes. No `.initial` option: the items may not be built yet
        // when this runs, so initial state is handled by the explicit call above and by
        // the refresh in the item factory.
        navObservers = [\WKWebView.canGoBack, \WKWebView.canGoForward].map { keyPath in
            webView.observe(keyPath) { [weak self] _, _ in self?.updateNavEnablement() }
        }
    }

    private func updateNavEnablement() {
        backButton?.isEnabled = webView.canGoBack
        forwardButton?.isEnabled = webView.canGoForward
    }

    /// Builds a borderless toolbar button backed by an SF Symbol, falling back to a
    /// text title on older systems that lack the symbol. Returns the item plus its
    /// embedded button so the caller can drive the button's enabled state directly.
    private func makeToolbarItem(_ spec: ToolbarButton) -> (item: NSToolbarItem, button: NSButton) {
        let label = spec.fallbackTitle // the title doubles as the accessibility label
        let item = NSToolbarItem(itemIdentifier: spec.id)
        item.label = label
        item.toolTip = label
        let button = NSButton(frame: .zero)
        button.bezelStyle = .texturedRounded
        button.target = self
        button.action = spec.action
        if #available(macOS 11.0, *),
           let image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: label) {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = spec.fallbackTitle
        }
        item.view = button
        return (item, button)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let spec = Self.toolbarButtons.first(where: { $0.id == itemIdentifier }) else {
            return nil
        }
        let (item, button) = makeToolbarItem(spec)
        // Capture weak refs to the history buttons so their enabled state can be updated,
        // then reflect the current (history-less) state now that the button exists.
        // (For a custom-view item, item.isEnabled wouldn't reach the button — see the
        // backButton/forwardButton declarations.)
        if itemIdentifier == Self.backItemID { backButton = button }
        if itemIdentifier == Self.forwardItemID { forwardButton = button }
        updateNavEnablement()
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.backItemID, Self.forwardItemID, .space, Self.reloadItemID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.backItemID, Self.forwardItemID, Self.reloadItemID, .space, .flexibleSpace]
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

    /// Copies the URL of the page currently shown to the system pasteboard. No-op (and
    /// disabled in the menu) when nothing is loaded.
    @objc private func copyCurrentURL(_ sender: Any?) {
        guard let url = HostNavigation.urlToCopy(currentURL: webView.url) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url, forType: .string)
    }

    // Enable/disable our self-targeted menu items to match what's actually possible:
    // Copy Current URL needs a loaded page; Back/Forward need history (consistent with
    // the toolbar buttons). Items targeting other responders fall through to `true`.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copyCurrentURL(_:)):
            return HostNavigation.urlToCopy(currentURL: webView?.url) != nil
        case #selector(goBack(_:)):
            return webView?.canGoBack ?? false
        case #selector(goForward(_:)):
            return webView?.canGoForward ?? false
        default:
            return true
        }
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

/// Pure navigation helpers, kept free of AppKit so they're unit-testable.
enum HostNavigation {
    /// The string to put on the pasteboard for "Copy Current URL", or nil if there's
    /// nothing to copy (no page loaded). Drives both the copy action and whether the
    /// menu item is enabled, so the two can't disagree.
    static func urlToCopy(currentURL: URL?) -> String? {
        currentURL?.absoluteString
    }
}

/// Pure CSS-color parsing for the manifest-derived window background, kept free of
/// AppKit so it's unit-testable. Supports hex forms (`#rgb`, `#rgba`, `#rrggbb`,
/// `#rrggbbaa`) — the forms web app manifests overwhelmingly use. Unrecognized
/// strings (named colors, `rgb()`, etc.) return nil and the app keeps its default
/// background rather than guessing.
enum CSSColor {
    /// Red, green, blue, alpha — each 0...1.
    struct RGBA: Equatable {
        let red, green, blue, alpha: Double
    }

    static func parse(_ string: String) -> RGBA? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard s.hasPrefix("#") else { return nil }
        let hex = String(s.dropFirst())
        guard hex.allSatisfy(\.isHexDigit) else { return nil }

        // Expand shorthand (#rgb / #rgba) to the full per-channel byte form.
        let full: String
        switch hex.count {
        case 3, 4:
            full = hex.map { "\($0)\($0)" }.joined()
        case 6, 8:
            full = hex
        default:
            return nil
        }

        func channel(_ offset: Int) -> Double {
            let start = full.index(full.startIndex, offsetBy: offset)
            let end = full.index(start, offsetBy: 2)
            return Double(Int(full[start..<end], radix: 16) ?? 0) / 255.0
        }
        return RGBA(
            red: channel(0),
            green: channel(2),
            blue: channel(4),
            alpha: full.count == 8 ? channel(6) : 1.0)
    }
}
