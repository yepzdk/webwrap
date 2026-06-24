import Foundation

/// The resolved starting values for the interactive option prompts. Built from `create`'s
/// flags (`OptionDefaults.forCreate`) or an existing app's config (`OptionDefaults.forUpdate`),
/// then used both to seed each prompt's default and — after `promptForOptions` fills it in —
/// to drive the build. Mirrors the `AppBuilder` option surface.
struct OptionSeed: Equatable {
    var width: Int
    var height: Int
    var toolbar: Bool
    var handleURLs: Bool
    var openAnyURL: Bool
    /// Explicit icon path, or nil meaning "resolve from site" (create) / "keep existing" (update).
    var iconPath: String?
    /// CSS background color, or nil meaning "none / from manifest".
    var backgroundColor: String?
    var noSign: Bool
    var signIdentity: String?
    var notarize: Bool
    var notaryProfile: String?
}

/// Which path `create` / `update` take, derived from the TTY state and which flags were
/// passed. Keeps the boundary rules as pure, testable predicates rather than inline `if`s.
enum CommandMode: Equatable {
    /// Build straight from flags, no prompts (scripts/CI, or `create --url X --name Y`).
    case nonInteractive
    /// Walk the interactive prompts.
    case interactive
    /// Non-TTY but required input is missing — caller should error.
    case missingInput
}

/// Pure derivation of seeds and command modes. No I/O — unit-tested; the stdin orchestration
/// lives in `promptForOptions` below (hand-verified, like `Prompt`).
enum OptionDefaults {
    /// Seed for interactive `create`, coalescing the flags to their effective defaults. The
    /// background seed comes from the manifest when the site provided one.
    static func forCreate(width: Int, height: Int, toolbar: Bool,
                          handleURLs: Bool, openAnyURL: Bool,
                          iconPath: String?, manifestBackground: String?,
                          noSign: Bool, signIdentity: String?,
                          notarize: Bool, notaryProfile: String?) -> OptionSeed {
        OptionSeed(
            width: width, height: height, toolbar: toolbar,
            handleURLs: handleURLs, openAnyURL: openAnyURL,
            iconPath: iconPath, backgroundColor: manifestBackground,
            noSign: noSign, signIdentity: signIdentity,
            notarize: notarize, notaryProfile: notaryProfile)
    }

    /// Seed for interactive `update`, taken from the app's persisted config. Icon and signing
    /// aren't persisted, so the icon seed is nil ("keep existing") and signing defaults to
    /// ad-hoc — re-entered each time.
    static func forUpdate(existing: AppConfig) -> OptionSeed {
        OptionSeed(
            width: existing.width, height: existing.height, toolbar: existing.showToolbar,
            handleURLs: existing.handleURLs, openAnyURL: existing.openAnyURL,
            iconPath: nil, backgroundColor: existing.backgroundColor,
            noSign: false, signIdentity: nil, notarize: false, notaryProfile: nil)
    }

    /// `--open-any-url` only means anything when URL handling is on, so off-domain access is
    /// allowed only when both are true. Generalizes the `effectiveHandleURLs` implication.
    static func resolveOpenAnyURL(handleURLs: Bool, openAnyURL: Bool) -> Bool {
        handleURLs && openAnyURL
    }

    /// The mode for `create`: non-TTY needs both url+name (else `missingInput`); on a TTY,
    /// having both means build straight from flags, otherwise prompt.
    static func createMode(isInteractive: Bool, hasURL: Bool, hasName: Bool) -> CommandMode {
        if hasURL && hasName { return .nonInteractive }
        return isInteractive ? .interactive : .missingInput
    }

    /// The mode for `update`: `--force` or any passed option flag keeps the flag-driven path;
    /// only a bare `update <app>` on a TTY goes interactive. Non-TTY is never interactive.
    static func updateMode(isInteractive: Bool, anyOptionFlag: Bool, force: Bool) -> CommandMode {
        if force || anyOptionFlag { return .nonInteractive }
        return isInteractive ? .interactive : .nonInteractive
    }
}

/// What `promptForOptions` is editing — only affects prompt wording (e.g. the icon prompt
/// says "resolve from site" on create, "keep existing" on update).
enum PromptContext {
    case create
    case update
}

/// Walks the option prompts in order, each seeded from `seed`, and returns the filled-in
/// values. Returns nil if the user aborts (EOF). Reads real stdin via `Prompt`, so — like
/// `Prompt` itself — it carries no business logic worth unit-testing; the seed/implication
/// logic it relies on lives in the pure `OptionDefaults` above.
func promptForOptions(seed: OptionSeed, context: PromptContext) -> OptionSeed? {
    var result = seed

    // Window size.
    guard let width = Prompt.askWithDefault(
        "Window width (points)", default: seed.width, defaultDisplay: "\(seed.width)",
        validate: intValidator) else { return nil }
    result.width = width

    guard let height = Prompt.askWithDefault(
        "Window height (points)", default: seed.height, defaultDisplay: "\(seed.height)",
        validate: intValidator) else { return nil }
    result.height = height

    // Toolbar.
    result.toolbar = Prompt.confirm("Show navigation toolbar (back/forward/reload)?",
                                    defaultYes: seed.toolbar)

    // URL handling, and the conditional off-domain follow-up.
    result.handleURLs = Prompt.confirm(
        "Open URLs the app is launched with (register as an http/https handler)?",
        defaultYes: seed.handleURLs)
    if result.handleURLs {
        result.openAnyURL = Prompt.confirm(
            "Accept off-domain URLs too (default: only same-site)?",
            defaultYes: seed.openAnyURL)
    } else {
        result.openAnyURL = false
    }

    // Background color (hex), validated through CSSColor. Empty keeps the seed/none.
    let bgDefaultDisplay = seed.backgroundColor ?? "none"
    guard let background = Prompt.askWithDefault(
        "Window background color (hex, blank for none)",
        default: seed.backgroundColor, defaultDisplay: bgDefaultDisplay,
        validate: colorValidator) else { return nil }
    result.backgroundColor = background

    // Icon path. Empty means resolve-from-site (create) or keep-existing (update).
    let iconDefaultDisplay: String
    if let iconPath = seed.iconPath {
        iconDefaultDisplay = iconPath
    } else {
        iconDefaultDisplay = context == .create ? "resolve from site" : "keep existing"
    }
    guard let iconPath = Prompt.askWithDefault(
        "Icon path (.png or .icns, blank to \(context == .create ? "auto-resolve" : "keep"))",
        default: seed.iconPath, defaultDisplay: iconDefaultDisplay,
        validate: iconValidator) else { return nil }
    result.iconPath = iconPath

    // Signing: ad-hoc by default; opt into Developer ID, then notarization.
    guard let signing = promptForSigning(seed: seed) else { return nil }
    result.noSign = signing.noSign
    result.signIdentity = signing.signIdentity
    result.notarize = signing.notarize
    result.notaryProfile = signing.notaryProfile

    return result
}

// MARK: - Signing sub-flow

private func promptForSigning(seed: OptionSeed)
    -> (noSign: Bool, signIdentity: String?, notarize: Bool, notaryProfile: String?)? {
    // Default posture: ad-hoc (sign with `-`), unless the seed says otherwise.
    let wantDevID = Prompt.confirm(
        "Sign with a Developer ID identity (otherwise ad-hoc)?",
        defaultYes: seed.signIdentity != nil)
    guard wantDevID else {
        // Ad-hoc is the default; nothing more to ask. (noSign stays whatever the seed had,
        // which is false for both create and update — i.e. ad-hoc sign.)
        return (noSign: seed.noSign && seed.signIdentity == nil ? seed.noSign : false,
                signIdentity: nil, notarize: false, notaryProfile: nil)
    }

    guard let identity = Prompt.askWithDefault(
        "Developer ID identity",
        default: seed.signIdentity, defaultDisplay: seed.signIdentity ?? "(required)",
        validate: { input in
            input.isEmpty ? .invalid("Identity must not be empty.") : .valid(input)
        }) else { return nil }
    guard let identity, !identity.isEmpty else {
        // User accepted an empty default — treat as ad-hoc rather than an invalid sign.
        return (noSign: false, signIdentity: nil, notarize: false, notaryProfile: nil)
    }

    let wantNotarize = Prompt.confirm("Notarize and staple with Apple?", defaultYes: seed.notarize)
    guard wantNotarize else {
        return (noSign: false, signIdentity: identity, notarize: false, notaryProfile: nil)
    }

    guard let profile = Prompt.askWithDefault(
        "notarytool store-credentials profile",
        default: seed.notaryProfile, defaultDisplay: seed.notaryProfile ?? "(required)",
        validate: { input in
            input.isEmpty ? .invalid("Profile name must not be empty.") : .valid(input)
        }) else { return nil }
    return (noSign: false, signIdentity: identity, notarize: true, notaryProfile: profile)
}

// MARK: - Validators (closures kept here so Prompt stays free of business logic)

private func intValidator(_ input: String) -> Prompt.Validation<Int> {
    guard let value = Int(input), value > 0 else {
        return .invalid("Enter a positive whole number.")
    }
    return .valid(value)
}

/// Accepts an empty-able hex color. Non-empty input must parse via `CSSColor`; the parsed
/// presence is what matters — the original string is returned so it's stored verbatim.
private func colorValidator(_ input: String) -> Prompt.Validation<String?> {
    guard CSSColor.parse(input) != nil else {
        return .invalid("Use a hex color like #1a73e8 (or leave blank).")
    }
    return .valid(input)
}

private func iconValidator(_ input: String) -> Prompt.Validation<String?> {
    let ext = (input as NSString).pathExtension.lowercased()
    guard ext == "png" || ext == "icns" else {
        return .invalid("Icon must be a .png or .icns file.")
    }
    guard FileManager.default.fileExists(atPath: (input as NSString).expandingTildeInPath) else {
        return .invalid("No such file: \(input)")
    }
    return .valid(input)
}
