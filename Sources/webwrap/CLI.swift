import Foundation
import ArgumentParser

struct WebWrap: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "webwrap",
        abstract: "Wrap any website into a standalone macOS .app.",
        version: "0.3.0",
        subcommands: [Create.self, List.self, Update.self],
        defaultSubcommand: Create.self
    )
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the webwrap apps installed on this Mac."
    )

    func run() throws {
        let apps = AppRegistry.discover()
        print(AppRegistry.renderTable(apps))
    }
}

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a previously created webwrap app in place.",
        discussion: """
        Refreshes the app's embedded engine with the current webwrap (so apps built \
        with an older version get the latest fixes) and optionally changes its URL, \
        name, window size, or icon. The app's login session is preserved.
        """
    )

    @Argument(help: "Path to the .app bundle to update.")
    var path: String

    @Option(name: [.short, .long], help: "New URL for the app.")
    var url: String?

    @Option(name: [.short, .long], help: "New display name for the app.")
    var name: String?

    @Option(name: .long, help: "New icon (.png or .icns). If omitted, the existing icon is kept.")
    var icon: String?

    @Option(name: .long, help: "New initial window width in points.")
    var width: Int?

    @Option(name: .long, help: "New initial window height in points.")
    var height: Int?

    @Flag(name: .long, inversion: .prefixedNo,
          help: "Show or hide the navigation toolbar (back/forward/reload). If omitted, the current setting is kept.")
    var toolbar: Bool?

    @Flag(name: .long, help: "Skip ad-hoc code signing.")
    var noSign: Bool = false

    @Option(name: .long, help: "Sign with a Developer ID identity (enables the hardened runtime).")
    var sign: String?

    @Flag(name: .long, help: "Notarize and staple. Requires --sign and --notary-profile.")
    var notarize: Bool = false

    @Option(name: .long, help: "notarytool store-credentials profile for --notarize.")
    var notaryProfile: String?

    @Flag(name: .long, help: "Don't prompt for confirmation before modifying the app.")
    var force: Bool = false

    func run() throws {
        try Create.validateSigning(noSign: noSign, sign: sign, notarize: notarize, notaryProfile: notaryProfile)

        let appPath = (path as NSString).standardizingPath
        let fm = FileManager.default
        guard fm.fileExists(atPath: appPath) else {
            throw ValidationError("No such app: \(appPath)")
        }
        // Refuse anything that isn't a webwrap app, so we never clobber other bundles.
        guard let existing = AppConfig.read(fromBundle: appPath) else {
            throw ValidationError("\(appPath) is not a webwrap app (no WebWrapURL in its Info.plist).")
        }

        if let url { try Create.validate(url: url) }
        if let name { try Create.validate(name: name) }

        let merged = existing.applying(url: url, name: name, width: width, height: height,
                                       showToolbar: toolbar)
        let outputDir = (appPath as NSString).deletingLastPathComponent
        let renamed = merged.name != existing.name

        // Summary of what will change.
        var changes: [String] = ["Refresh the embedded webwrap engine"]
        if url != nil, merged.url != existing.url { changes.append("URL → \(merged.url)") }
        if renamed { changes.append("Name → \(merged.name) (bundle renamed)") }
        if merged.width != existing.width || merged.height != existing.height {
            changes.append("Size → \(merged.width)×\(merged.height)")
        }
        if merged.showToolbar != existing.showToolbar {
            changes.append("Toolbar → \(merged.showToolbar ? "shown" : "hidden")")
        }
        if icon != nil { changes.append("Icon → \(icon!)") }
        print("Updating \(existing.name) at \(appPath):")
        for c in changes { print("  • \(c)") }

        if !force {
            guard Prompt.isInteractive else {
                throw ValidationError("Pass --force to update non-interactively.")
            }
            guard Prompt.confirm("\nApply these changes?", defaultYes: true) else {
                throw CleanExit.message("Aborted — no changes made.")
            }
        }

        // When no new icon is given, preserve the existing one by copying the bundle's
        // AppIcon.icns to a temp file and feeding it back as the icon path (the build
        // removes and recreates the bundle, so we must capture it first).
        var iconForBuild = icon
        var tmpIcon: String?
        if icon == nil {
            let icns = (appPath as NSString).appendingPathComponent("Contents/Resources/AppIcon.icns")
            if let data = fm.contents(atPath: icns) {
                let tmp = (NSTemporaryDirectory() as NSString)
                    .appendingPathComponent("webwrap-keepicon-\(UUID().uuidString).icns")
                try data.write(to: URL(fileURLWithPath: tmp))
                iconForBuild = tmp
                tmpIcon = tmp
            }
        }
        defer { if let tmpIcon { try? fm.removeItem(atPath: tmpIcon) } }

        // Rebuild in place. Passing the EXISTING bundle id keeps the data store key
        // stable, so the app's login session survives. force:true because we're
        // intentionally overwriting the bundle we just read.
        let builder = AppBuilder(
            url: merged.url,
            name: merged.name,
            outputDir: outputDir,
            bundleId: existing.bundleId,
            iconPath: iconForBuild,
            width: merged.width,
            height: merged.height,
            showToolbar: merged.showToolbar,
            force: true,
            sign: !noSign,
            signIdentity: sign,
            notarize: notarize,
            notaryProfile: notaryProfile,
            backgroundColor: merged.backgroundColor
        )
        let newPath = try builder.build()

        // On rename the new bundle has a different name; remove the old one.
        if renamed, (newPath as NSString).standardizingPath != appPath {
            try? fm.removeItem(atPath: appPath)
        }
        print("✓ Updated \(newPath)")
    }
}

struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a standalone .app bundle for a website.",
        discussion: """
        Run with no --url/--name to be prompted interactively (when stdin is a \
        terminal). Provide both to create non-interactively.
        """
    )

    @Option(name: [.short, .long], help: "The URL the app should open, e.g. https://outlook.office.com")
    var url: String?

    @Option(name: [.short, .long], help: "The display name of the app, e.g. \"Outlook\".")
    var name: String?

    @Option(name: [.short, .long], help: "Where to write the .app bundle. Defaults to /Applications.")
    var output: String = "/Applications"

    @Option(name: .long, help: "Bundle identifier. Defaults to dk.yepz.webwrap.<slug>.")
    var bundleId: String?

    @Option(name: .long, help: "Path to a .png or .icns icon. If omitted, an icon is resolved from the site.")
    var icon: String?

    @Option(name: .long, help: "Initial window width in points.")
    var width: Int = 1200

    @Option(name: .long, help: "Initial window height in points.")
    var height: Int = 800

    @Flag(name: .long, inversion: .prefixedNo,
          help: "Show a navigation toolbar (back/forward/reload) in the window. Off by default.")
    var toolbar: Bool = false

    @Flag(name: .long, help: "Overwrite the destination .app if it already exists.")
    var force: Bool = false

    @Flag(name: .long, help: "Skip ad-hoc code signing (codesign --sign -).")
    var noSign: Bool = false

    @Option(name: .long, help: "Sign with a Developer ID identity, e.g. \"Developer ID Application: Name (TEAMID)\". Enables the hardened runtime.")
    var sign: String?

    @Flag(name: .long, help: "Notarize and staple the signed app with Apple. Requires --sign and --notary-profile.")
    var notarize: Bool = false

    @Option(name: .long, help: "Name of a `notarytool store-credentials` keychain profile, used with --notarize.")
    var notaryProfile: String?

    func run() throws {
        try Self.validateSigning(noSign: noSign, sign: sign, notarize: notarize, notaryProfile: notaryProfile)

        if let url, let name {
            // Both supplied — non-interactive path. Validate, then build directly.
            try Self.validate(url: url)
            try Self.validate(name: name)
            // Resolve icon + manifest metadata in one pass (skipped when an explicit
            // --icon is given). We still want the manifest's background color even when
            // the name came from a flag.
            let site = resolveSite(url: url)
            try build(url: url, name: name,
                      resolvedIcon: site.icon, metadata: site.metadata)
            return
        }

        // At least one of url/name is missing.
        guard Prompt.isInteractive else {
            // Non-TTY (piped/CI): never prompt — fail clearly, as before.
            let missing = [url == nil ? "--url" : nil, name == nil ? "--name" : nil]
                .compactMap { $0 }.joined(separator: " and ")
            throw ValidationError("Missing required option(s): \(missing). "
                + "Provide them as flags, or run interactively from a terminal.")
        }

        try runInteractive(presetURL: url, presetName: name)
    }

    // MARK: - Interactive flow

    private func runInteractive(presetURL: String?, presetName: String?) throws {
        print("webwrap — create a macOS app from a website\n")

        // 1. URL (re-prompt until valid).
        let resolvedURL: String
        if let presetURL { resolvedURL = presetURL } else {
            guard let entered = Prompt.ask("URL: ", validate: { input -> Prompt.Validation<String> in
                do { try Self.validate(url: input); return .valid(input) }
                catch { return .invalid("\(error)") }
            }) else { throw CleanExit.message("Aborted.") }
            resolvedURL = entered
        }

        // 2. Resolve the icon + manifest metadata up front (one network pass) so the
        // name step can default from the manifest and the summary can report the icon.
        print("Resolving icon…")
        let site = resolveSite(url: resolvedURL)
        let iconDescription: String
        if icon != nil {
            iconDescription = "from \(icon!)"
        } else if let resolved = site.icon {
            iconDescription = resolved.source.rawValue
        } else {
            iconDescription = "none found — default icon"
        }

        // 3. Name. Prefer an explicit --name; otherwise suggest from the manifest
        // (short_name/name), then fall back to the host-label guess.
        let resolvedName: String
        if let presetName { resolvedName = presetName } else {
            let suggestion = site.metadata.preferredName
                ?? Self.suggestName(fromURL: resolvedURL)
                ?? ""
            if suggestion.isEmpty {
                guard let entered = Prompt.ask("Name: ", validate: { input -> Prompt.Validation<String> in
                    input.isEmpty ? .invalid("Name must not be empty.") : .valid(input)
                }) else { throw CleanExit.message("Aborted.") }
                resolvedName = entered
            } else {
                resolvedName = Prompt.lineWithDefault("Name", default: suggestion)
            }
        }

        // 4. Summary + confirm.
        let bundleIdentifier = AppBuilder.defaultBundleId(name: resolvedName, override: bundleId)
        let destination = (output as NSString).appendingPathComponent("\(resolvedName).app")
        let bgDescription = site.metadata.launchBackgroundColor.map { "\($0) (from manifest)" } ?? "default"
        print("""

        Summary
          Name:        \(resolvedName)
          URL:         \(resolvedURL)
          Bundle ID:   \(bundleIdentifier)
          Icon:        \(iconDescription)
          Toolbar:     \(toolbar ? "yes" : "no")
          Background:  \(bgDescription)
          Signing:     \(Self.signingDescription(noSign: noSign, sign: sign, notarize: notarize))
          Destination: \(destination)
        """)

        guard Prompt.confirm("\nCreate this app?", defaultYes: true) else {
            throw CleanExit.message("Aborted — nothing was written.")
        }

        try build(url: resolvedURL, name: resolvedName,
                  resolvedIcon: site.icon, metadata: site.metadata)
    }

    /// Resolves the site's icon and manifest metadata in a single network pass. When an
    /// explicit `--icon` is given, the icon isn't fetched (the file is used instead), but
    /// the manifest is still consulted for metadata (name/background).
    private func resolveSite(url: String) -> (icon: IconResolver.Resolved?, metadata: IconResolver.SiteMetadata) {
        guard let resolver = IconResolver(urlString: url) else { return (nil, IconResolver.SiteMetadata()) }
        let result = resolver.resolveWithMetadata()
        // Discard the resolved icon when the user supplied their own file.
        return (icon == nil ? result.icon : nil, result.metadata)
    }

    // MARK: - Build

    private func build(url: String, name: String,
                       resolvedIcon: IconResolver.Resolved?,
                       metadata: IconResolver.SiteMetadata) throws {
        let builder = AppBuilder(
            url: url,
            name: name,
            outputDir: output,
            bundleId: bundleId,
            iconPath: icon,
            width: width,
            height: height,
            showToolbar: toolbar,
            force: force,
            sign: !noSign,
            signIdentity: sign,
            notarize: notarize,
            notaryProfile: notaryProfile,
            resolvedIcon: resolvedIcon,
            backgroundColor: metadata.launchBackgroundColor
        )
        let appPath = try builder.build()
        print("✓ Created \(appPath)")
    }

    // MARK: - Pure validation / derivation (shared by interactive and flag paths)

    /// Validates that a string is an absolute URL with a scheme and host.
    static func validate(url: String) throws {
        guard let parsed = URL(string: url), parsed.scheme != nil, parsed.host != nil else {
            throw ValidationError("URL must be absolute and include a scheme, e.g. https://example.com")
        }
    }

    static func validate(name: String) throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError("Name must not be empty.")
        }
    }

    /// A short human description of what the signing flags will do, for the summary.
    static func signingDescription(noSign: Bool, sign: String?, notarize: Bool) -> String {
        if noSign { return "none (--no-sign)" }
        guard let sign else { return "ad-hoc" }
        return notarize ? "Developer ID + notarized (\(sign))" : "Developer ID (\(sign))"
    }

    /// Validates the signing/notarization flag combination. Pure — no I/O.
    static func validateSigning(noSign: Bool, sign: String?, notarize: Bool, notaryProfile: String?) throws {
        if noSign && sign != nil {
            throw ValidationError("`--no-sign` and `--sign` are mutually exclusive.")
        }
        if notarize && sign == nil {
            throw ValidationError("`--notarize` requires `--sign` (a Developer ID identity).")
        }
        if notarize && (notaryProfile?.isEmpty ?? true) {
            throw ValidationError("`--notarize` requires `--notary-profile` "
                + "(a `notarytool store-credentials` profile name).")
        }
    }

    /// Suggests a display name from a URL's host: drops a leading "www.", takes the
    /// first label, and capitalizes it. "https://outlook.office.com" → "Outlook";
    /// "https://www.example.com" → "Example". Returns nil if no host.
    static func suggestName(fromURL url: String) -> String? {
        guard var host = URL(string: url)?.host else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        guard let label = host.split(separator: ".").first, !label.isEmpty else { return nil }
        return label.prefix(1).uppercased() + label.dropFirst()
    }
}
