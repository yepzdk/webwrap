import Foundation
import ArgumentParser

struct WebWrap: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "webwrap",
        abstract: "Wrap any website into a standalone macOS .app.",
        version: "0.1.0",
        subcommands: [Create.self, List.self],
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
            try build(url: url, name: name, resolvedIcon: nil)
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

        // 2. Name (default suggested from the host; re-prompt if blank).
        let resolvedName: String
        if let presetName { resolvedName = presetName } else {
            let suggestion = Self.suggestName(fromURL: resolvedURL) ?? ""
            if suggestion.isEmpty {
                guard let entered = Prompt.ask("Name: ", validate: { input -> Prompt.Validation<String> in
                    input.isEmpty ? .invalid("Name must not be empty.") : .valid(input)
                }) else { throw CleanExit.message("Aborted.") }
                resolvedName = entered
            } else {
                resolvedName = Prompt.lineWithDefault("Name", default: suggestion)
            }
        }

        // 3. Resolve the icon up front so the summary can report its source.
        print("Resolving icon…")
        let resolvedIcon = icon == nil ? IconResolver(urlString: resolvedURL)?.resolve() : nil
        let iconDescription: String
        if icon != nil {
            iconDescription = "from \(icon!)"
        } else if let resolvedIcon {
            iconDescription = resolvedIcon.source.rawValue
        } else {
            iconDescription = "none found — default icon"
        }

        // 4. Summary + confirm.
        let bundleIdentifier = AppBuilder.defaultBundleId(name: resolvedName, override: bundleId)
        let destination = (output as NSString).appendingPathComponent("\(resolvedName).app")
        print("""

        Summary
          Name:        \(resolvedName)
          URL:         \(resolvedURL)
          Bundle ID:   \(bundleIdentifier)
          Icon:        \(iconDescription)
          Signing:     \(Self.signingDescription(noSign: noSign, sign: sign, notarize: notarize))
          Destination: \(destination)
        """)

        guard Prompt.confirm("\nCreate this app?", defaultYes: true) else {
            throw CleanExit.message("Aborted — nothing was written.")
        }

        try build(url: resolvedURL, name: resolvedName, resolvedIcon: resolvedIcon)
    }

    // MARK: - Build

    private func build(url: String, name: String, resolvedIcon: IconResolver.Resolved?) throws {
        let builder = AppBuilder(
            url: url,
            name: name,
            outputDir: output,
            bundleId: bundleId,
            iconPath: icon,
            width: width,
            height: height,
            force: force,
            sign: !noSign,
            signIdentity: sign,
            notarize: notarize,
            notaryProfile: notaryProfile,
            resolvedIcon: resolvedIcon
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
