import Foundation
import ArgumentParser

struct WebWrap: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "webwrap",
        abstract: "Wrap any website into a standalone macOS .app.",
        version: "0.5.0",
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

    @Flag(name: .long, inversion: .prefixedNo,
          help: "Show or hide the page-load progress line. If omitted, the current setting is kept.")
    var progressBar: Bool?

    @Flag(name: .long, inversion: .prefixedNo,
          help: "Register as an http/https handler and open URLs the app is launched with. If omitted, the current setting is kept.")
    var handleUrls: Bool?

    @Flag(name: .long, inversion: .prefixedNo,
          help: "With --handle-urls, also accept off-domain URLs (default: only same-site). If omitted, the current setting is kept.")
    var openAnyUrl: Bool?

    @Option(name: .long, help: "Set the window background color (hex, e.g. #1a73e8). If omitted, it follows the new --url's manifest, else the current setting is kept.")
    var backgroundColor: String?

    @Flag(name: .long, help: "Clear the window background color (no color painted on launch).")
    var noBackgroundColor: Bool = false

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
        if backgroundColor != nil && noBackgroundColor {
            throw ValidationError("`--background-color` and `--no-background-color` are mutually exclusive.")
        }
        if let backgroundColor { try Create.validate(backgroundColor: backgroundColor) }

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

        // Decide flag-driven vs. interactive. A bare `update <app>` on a TTY edits all
        // options interactively, seeded from the app's current settings; any option flag
        // (or --force) keeps the existing flag-driven path.
        let anyOptionFlag = url != nil || name != nil || icon != nil || width != nil
            || height != nil || toolbar != nil || progressBar != nil || handleUrls != nil
            || openAnyUrl != nil || backgroundColor != nil || noBackgroundColor
            || sign != nil || noSign || notarize
        let mode = OptionDefaults.updateMode(isInteractive: Prompt.isInteractive,
                                             anyOptionFlag: anyOptionFlag, force: force)

        // The resolved new config + the icon path / signing to build with. Filled by
        // whichever path runs below.
        let merged: AppConfig
        var iconOverride = icon
        var buildNoSign = noSign
        var buildSign = sign
        var buildNotarize = notarize
        var buildNotaryProfile = notaryProfile

        if mode == .interactive {
            Prompt.intro("Updating \(existing.name) — current settings shown as defaults.")
            // Steps 1–2 — URL + name, seeded from the current values.
            Prompt.step(1, of: interactiveStepCount, title: "Website URL",
                        help: "The address the app opens.")
            guard let resolvedURL = Prompt.lineWithDefault("URL", default: existing.url) else {
                throw CleanExit.message("Aborted — no changes made.")
            }
            try Create.validate(url: resolvedURL)
            Prompt.step(2, of: interactiveStepCount, title: "App name",
                        help: "The display name; changing it renames the .app (session is kept).")
            guard let resolvedName = Prompt.lineWithDefault("Name", default: existing.name) else {
                throw CleanExit.message("Aborted — no changes made.")
            }
            try Create.validate(name: resolvedName)
            // If the URL changed, default the background prompt to the new site's manifest
            // color so re-resolution is the interactive default too (still editable).
            var updateSeed = OptionDefaults.forUpdate(existing: existing)
            if resolvedURL != existing.url {
                updateSeed.backgroundColor = Self.resolveManifestBackground(forURL: resolvedURL)
            }
            guard let seed = promptForOptions(seed: updateSeed, context: .update) else {
                throw CleanExit.message("Aborted — no changes made.")
            }
            merged = existing.applying(
                url: resolvedURL, name: resolvedName, width: seed.width, height: seed.height,
                showToolbar: seed.toolbar, progressBar: seed.progressBar,
                backgroundColor: .some(seed.backgroundColor),
                handleURLs: seed.handleURLs,
                openAnyURL: OptionDefaults.resolveOpenAnyURL(handleURLs: seed.handleURLs,
                                                             openAnyURL: seed.openAnyURL))
            iconOverride = seed.iconPath
            buildNoSign = seed.noSign
            buildSign = seed.signIdentity
            buildNotarize = seed.notarize
            buildNotaryProfile = seed.notaryProfile
        } else {
            // --open-any-url implies URL handling, so turning it on also turns handling on
            // (otherwise the setting would be inert). Only forces it when the user is
            // enabling open-any-url, never overriding an explicit --no-handle-urls intent.
            let effectiveHandleURLs = (openAnyUrl == true && handleUrls == nil) ? true : handleUrls

            // Background precedence: an explicit flag wins; otherwise a changed URL adopts
            // the new site's manifest color (re-resolved here); otherwise it's carried over.
            // Only re-resolve when no flag overrides it — otherwise the fetch is discarded.
            let urlChanged = url != nil && url != existing.url
            let needsReResolve = urlChanged && backgroundColor == nil && !noBackgroundColor
            let reResolved = needsReResolve ? Self.resolveManifestBackground(forURL: url!) : nil
            let background = OptionDefaults.resolveUpdateBackground(
                explicit: backgroundColor, clear: noBackgroundColor,
                urlChanged: urlChanged, reResolved: reResolved)

            merged = existing.applying(url: url, name: name, width: width, height: height,
                                       showToolbar: toolbar, progressBar: progressBar,
                                       backgroundColor: background,
                                       handleURLs: effectiveHandleURLs, openAnyURL: openAnyUrl)
        }

        try Create.validateSigning(noSign: buildNoSign, sign: buildSign,
                                   notarize: buildNotarize, notaryProfile: buildNotaryProfile)
        let outputDir = (appPath as NSString).deletingLastPathComponent
        let renamed = merged.name != existing.name

        // Summary of what will change. (Compares the merged config against the existing
        // one, so it's accurate whether values came from flags or interactive prompts.)
        var changes: [String] = ["Refresh the embedded webwrap engine"]
        if merged.url != existing.url { changes.append("URL → \(merged.url)") }
        if renamed { changes.append("Name → \(merged.name) (bundle renamed)") }
        if merged.width != existing.width || merged.height != existing.height {
            changes.append("Size → \(merged.width)×\(merged.height)")
        }
        if merged.showToolbar != existing.showToolbar {
            changes.append("Toolbar → \(merged.showToolbar ? "shown" : "hidden")")
        }
        if merged.progressBar != existing.progressBar {
            changes.append("Progress line → \(merged.progressBar ? "shown" : "hidden")")
        }
        if merged.handleURLs != existing.handleURLs {
            changes.append("Handle URLs → \(merged.handleURLs ? "on" : "off")")
        }
        if merged.openAnyURL != existing.openAnyURL {
            changes.append("Open any URL → \(merged.openAnyURL ? "on" : "off")")
        }
        if merged.backgroundColor != existing.backgroundColor {
            changes.append("Background → \(merged.backgroundColor ?? "default")")
        }
        if let iconOverride { changes.append("Icon → \(iconOverride)") }
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
        var iconForBuild = iconOverride
        var tmpIcon: String?
        if iconOverride == nil {
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
            progressBar: merged.progressBar,
            force: true,
            sign: !buildNoSign,
            signIdentity: buildSign,
            notarize: buildNotarize,
            notaryProfile: buildNotaryProfile,
            backgroundColor: merged.backgroundColor,
            handleURLs: merged.handleURLs,
            openAnyURL: merged.openAnyURL
        )
        let newPath = try builder.build()

        // On rename the new bundle has a different name; remove the old one.
        if renamed, (newPath as NSString).standardizingPath != appPath {
            try? fm.removeItem(atPath: appPath)
        }
        print("✓ Updated \(newPath)")
    }

    /// Re-resolves a site's manifest launch background color (nil if the site has none or
    /// the URL can't be resolved). Used to make the background follow a changed `--url`.
    private static func resolveManifestBackground(forURL url: String) -> String? {
        IconResolver(urlString: url)?.resolveWithMetadata().metadata.launchBackgroundColor
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

    @Flag(name: .long, inversion: .prefixedNo,
          help: "Show a thin page-load progress line at the top of the window. Off by default.")
    var progressBar: Bool = false

    @Flag(name: .long, help: "Register as an http/https handler and open URLs the app is launched with (e.g. from Choosy). Off by default.")
    var handleUrls: Bool = false

    @Flag(name: .long, help: "With --handle-urls, also accept off-domain URLs (default: only same-site).")
    var openAnyUrl: Bool = false

    @Option(name: .long, help: "Hex color painted behind the page on launch (e.g. #1a73e8). Overrides the site manifest's color.")
    var backgroundColor: String?

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

    /// `--open-any-url` only means anything when URL handling is on, so it implies
    /// `--handle-urls` — otherwise the flag would bake an inert setting. The effective
    /// handle-urls value used everywhere in `create`.
    private var effectiveHandleURLs: Bool { handleUrls || openAnyUrl }

    func run() throws {
        try Self.validateSigning(noSign: noSign, sign: sign, notarize: notarize, notaryProfile: notaryProfile)
        if let backgroundColor { try Self.validate(backgroundColor: backgroundColor) }
        // Note the implication so `--open-any-url` alone isn't silently inert.
        if openAnyUrl && !handleUrls {
            FileHandle.standardError.write(Data(
                "Note: --open-any-url implies --handle-urls; enabling URL handling.\n".utf8))
        }

        switch OptionDefaults.createMode(isInteractive: Prompt.isInteractive,
                                         hasURL: url != nil, hasName: name != nil) {
        case .nonInteractive:
            // Both supplied — non-interactive path. Validate, then build directly.
            try Self.validate(url: url!)
            try Self.validate(name: name!)
            // Resolve icon + manifest metadata in one pass (skipped when an explicit
            // --icon is given). We still want the manifest's background color even when
            // the name came from a flag.
            let site = resolveSite(url: url!)
            try build(url: url!, name: name!, seed: seedFromFlags(manifest: site.metadata),
                      resolvedIcon: site.icon)

        case .missingInput:
            // Non-TTY (piped/CI): never prompt — fail clearly, as before.
            let missing = [url == nil ? "--url" : nil, name == nil ? "--name" : nil]
                .compactMap { $0 }.joined(separator: " and ")
            throw ValidationError("Missing required option(s): \(missing). "
                + "Provide them as flags, or run interactively from a terminal.")

        case .interactive:
            try runInteractive(presetURL: url, presetName: name)
        }
    }

    /// The seed built from `create`'s flags (used for the non-interactive build and as the
    /// starting point for the interactive prompts). Background defaults to the manifest's
    /// color when no explicit value is known.
    private func seedFromFlags(manifest: IconResolver.SiteMetadata) -> OptionSeed {
        // `--open-any-url` implies `--handle-urls`, so the seed's handleURLs reflects that.
        OptionDefaults.forCreate(
            width: width, height: height, toolbar: toolbar, progressBar: progressBar,
            handleURLs: effectiveHandleURLs, openAnyURL: openAnyUrl,
            iconPath: icon, manifestBackground: manifest.launchBackgroundColor,
            explicitBackground: backgroundColor,
            noSign: noSign, signIdentity: sign, notarize: notarize, notaryProfile: notaryProfile)
    }

    // MARK: - Interactive flow

    private func runInteractive(presetURL: String?, presetName: String?) throws {
        Prompt.intro("webwrap — create a macOS app from a website")

        // Step 1 — URL (re-prompt until valid).
        let resolvedURL: String
        if let presetURL { resolvedURL = presetURL } else {
            Prompt.step(1, of: interactiveStepCount, title: "Website URL",
                        help: "The address the app opens, e.g. https://github.com.")
            guard let entered = Prompt.ask("URL: ", validate: { input -> Prompt.Validation<String> in
                do { try Self.validate(url: input); return .valid(input) }
                catch { return .invalid("\(error)") }
            }) else { throw CleanExit.message("Aborted — nothing was written.") }
            resolvedURL = entered
        }

        // Resolve the icon + manifest metadata up front (one network pass) so the name step
        // can default from the manifest and the summary can report the icon.
        print("Resolving icon…")
        let site = resolveSite(url: resolvedURL)

        // Step 2 — Name. Prefer an explicit --name; otherwise suggest from the manifest
        // (short_name/name), then fall back to the host-label guess.
        let resolvedName: String
        if let presetName { resolvedName = presetName } else {
            Prompt.step(2, of: interactiveStepCount, title: "App name",
                        help: "The display name and the .app filename.")
            let suggestion = site.metadata.preferredName
                ?? Self.suggestName(fromURL: resolvedURL)
                ?? ""
            if suggestion.isEmpty {
                guard let entered = Prompt.ask("Name: ", validate: { input -> Prompt.Validation<String> in
                    input.isEmpty ? .invalid("Name must not be empty.") : .valid(input)
                }) else { throw CleanExit.message("Aborted — nothing was written.") }
                resolvedName = entered
            } else {
                guard let entered = Prompt.lineWithDefault("Name", default: suggestion) else {
                    throw CleanExit.message("Aborted — nothing was written.")
                }
                resolvedName = entered
            }
        }

        // Steps 3–8 — the remaining options, seeded from the flags (and the manifest
        // background). An explicit --icon seeds the icon prompt; otherwise it auto-resolves.
        guard let seed = promptForOptions(seed: seedFromFlags(manifest: site.metadata),
                                          context: .create) else {
            throw CleanExit.message("Aborted — nothing was written.")
        }
        // The summary reports the actual resolved icon source when none was entered.
        let resolvedIcon = seed.iconPath == nil ? site.icon : nil

        // Summary + confirm.
        let bundleIdentifier = AppBuilder.defaultBundleId(name: resolvedName, override: bundleId)
        let destination = (output as NSString).appendingPathComponent("\(resolvedName).app")
        print("""

        Summary
          Name:        \(resolvedName)
          URL:         \(resolvedURL)
          Bundle ID:   \(bundleIdentifier)
          Icon:        \(iconSummary(seed: seed, resolvedIcon: resolvedIcon))
          Size:        \(seed.width)×\(seed.height)
          Toolbar:     \(seed.toolbar ? "yes" : "no")
          Progress:    \(seed.progressBar ? "yes" : "no")
          Handle URLs: \(handleURLsSummary(seed: seed))
          Background:  \(seed.backgroundColor ?? "default")
          Signing:     \(Self.signingDescription(noSign: seed.noSign, sign: seed.signIdentity, notarize: seed.notarize))
          Destination: \(destination)
        """)

        guard Prompt.confirm("\nCreate this app?", defaultYes: true) else {
            throw CleanExit.message("Aborted — nothing was written.")
        }

        try build(url: resolvedURL, name: resolvedName, seed: seed, resolvedIcon: resolvedIcon)
    }

    /// Human description of the icon choice for the summary.
    private func iconSummary(seed: OptionSeed, resolvedIcon: IconResolver.Resolved?) -> String {
        if let path = seed.iconPath { return "from \(path)" }
        if let resolved = resolvedIcon { return resolved.source.rawValue }
        return "none found — default icon"
    }

    /// Human description of the URL-handling choice for the summary.
    private func handleURLsSummary(seed: OptionSeed) -> String {
        guard seed.handleURLs else { return "no" }
        return seed.openAnyURL ? "yes (any domain)" : "yes (same site)"
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

    private func build(url: String, name: String, seed: OptionSeed,
                       resolvedIcon: IconResolver.Resolved?) throws {
        let builder = AppBuilder(
            url: url,
            name: name,
            outputDir: output,
            bundleId: bundleId,
            iconPath: seed.iconPath,
            width: seed.width,
            height: seed.height,
            showToolbar: seed.toolbar,
            progressBar: seed.progressBar,
            force: force,
            sign: !seed.noSign,
            signIdentity: seed.signIdentity,
            notarize: seed.notarize,
            notaryProfile: seed.notaryProfile,
            resolvedIcon: resolvedIcon,
            backgroundColor: seed.backgroundColor,
            handleURLs: seed.handleURLs,
            openAnyURL: OptionDefaults.resolveOpenAnyURL(handleURLs: seed.handleURLs,
                                                         openAnyURL: seed.openAnyURL)
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

    /// Validates a window background color: must parse as a CSS color (e.g. #1a73e8).
    /// Shared by `create --background-color` and `update --background-color`.
    static func validate(backgroundColor: String) throws {
        guard CSSColor.parse(backgroundColor) != nil else {
            throw ValidationError("Background color must be a hex color like #1a73e8.")
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
