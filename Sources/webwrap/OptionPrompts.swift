import Foundation

/// The resolved starting values for the interactive option prompts. Built from `create`'s
/// flags (`OptionDefaults.forCreate`) or an existing app's config (`OptionDefaults.forUpdate`),
/// then used both to seed each prompt's default and — after `promptForOptions` fills it in —
/// to drive the build. Mirrors the `AppBuilder` option surface.
struct OptionSeed: Equatable {
    var width: Int
    var height: Int
    var toolbar: Bool
    var toolbarStyle: ToolbarStyle
    var progressBar: Bool
    var handleURLs: Bool
    var openAnyURL: Bool
    /// Whether links that leave the site open in the system default browser.
    var externalLinks: Bool
    /// Explicit icon path, or nil meaning "resolve from site" (create) / "keep existing" (update).
    var iconPath: String?
    /// CSS background color, or nil meaning "none / from manifest".
    var backgroundColor: String?
    /// User-agent token (safari/chrome/edge) or a custom UA string; nil = default (Safari).
    var userAgent: String?
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
    /// background seed prefers an explicit `--background-color`, falling back to the
    /// manifest's color when the site provided one.
    static func forCreate(width: Int, height: Int, toolbar: Bool, toolbarStyle: ToolbarStyle,
                          progressBar: Bool,
                          handleURLs: Bool, openAnyURL: Bool, externalLinks: Bool,
                          iconPath: String?, manifestBackground: String?,
                          explicitBackground: String?, userAgent: String?,
                          noSign: Bool, signIdentity: String?,
                          notarize: Bool, notaryProfile: String?) -> OptionSeed {
        OptionSeed(
            width: width, height: height, toolbar: toolbar, toolbarStyle: toolbarStyle,
            progressBar: progressBar,
            handleURLs: handleURLs, openAnyURL: openAnyURL, externalLinks: externalLinks,
            iconPath: iconPath, backgroundColor: explicitBackground ?? manifestBackground,
            userAgent: userAgent,
            noSign: noSign, signIdentity: signIdentity,
            notarize: notarize, notaryProfile: notaryProfile)
    }

    /// Seed for interactive `update`, taken from the app's persisted config. Icon and signing
    /// aren't persisted, so the icon seed is nil ("keep existing") and signing defaults to
    /// ad-hoc — re-entered each time.
    static func forUpdate(existing: AppConfig) -> OptionSeed {
        OptionSeed(
            width: existing.width, height: existing.height, toolbar: existing.showToolbar,
            toolbarStyle: existing.toolbarStyle,
            progressBar: existing.progressBar,
            handleURLs: existing.handleURLs, openAnyURL: existing.openAnyURL,
            externalLinks: existing.externalLinks,
            iconPath: nil, backgroundColor: existing.backgroundColor,
            userAgent: existing.userAgent,
            noSign: false, signIdentity: nil, notarize: false, notaryProfile: nil)
    }

    /// Resolves what background color a flag-driven `update` should apply, as the
    /// double-optional `AppConfig.applying(backgroundColor:)` expects: `nil` keeps the
    /// existing color, `.some(nil)` clears it, `.some(x)` sets it. Pure — the `reResolved`
    /// value is fetched by the caller, so precedence is unit-testable without I/O.
    ///
    /// Precedence: an explicit clear or color wins; otherwise a changed URL adopts the new
    /// site's re-resolved manifest color (which may itself be nil → clear, so the color
    /// follows the new site); otherwise the existing color is carried over.
    static func resolveUpdateBackground(explicit: String?, clear: Bool,
                                        urlChanged: Bool, reResolved: String?) -> String?? {
        if clear { return .some(nil) }
        if let explicit { return .some(explicit) }
        if urlChanged { return .some(reResolved) }
        return nil
    }

    /// Resolves what user agent a flag-driven `update` should apply, as the
    /// double-optional `AppConfig.applying(userAgent:)` expects: `nil` keeps the
    /// existing setting, `.some(nil)` resets to the default, `.some(x)` sets it.
    static func resolveUpdateUserAgent(explicit: String?, clear: Bool) -> String?? {
        if clear { return .some(nil) }
        if let explicit { return .some(explicit) }
        return nil
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

/// Total steps in the full interactive flow, used for the `[Step n/total]` indicator.
/// URL (1) and Name (2) are prompted by the caller; `promptForOptions` covers 3–10.
/// Conditional follow-ups (off-domain, notarize) nest under their parent step rather than
/// taking their own number, so the denominator is stable.
let interactiveStepCount = 10

/// Walks the option prompts (steps 3–10) in order, each seeded from `seed`, with a step
/// header + help text, and returns the filled-in values. Returns nil if the user cancels
/// (types q / Ctrl-D) at any step. Reads real stdin via `Prompt`, so — like `Prompt`
/// itself — it carries no business logic worth unit-testing; the seed/implication logic it
/// relies on lives in the pure `OptionDefaults` above.
func promptForOptions(seed: OptionSeed, context: PromptContext,
                      handlerOnly: Bool = false) -> OptionSeed? {
    var result = seed
    let total = interactiveStepCount

    // Step 3 — window size.
    Prompt.step(3, of: total, title: "Window size",
                help: "The window's initial width and height in points.")
    guard let width = Prompt.askWithDefault(
        "Window width (points)", default: seed.width, defaultDisplay: "\(seed.width)",
        validate: intValidator) else { return nil }
    result.width = width
    guard let height = Prompt.askWithDefault(
        "Window height (points)", default: seed.height, defaultDisplay: "\(seed.height)",
        validate: intValidator) else { return nil }
    result.height = height

    // Step 4 — toolbar.
    Prompt.step(4, of: total, title: "Toolbar",
                help: "A back/forward/reload/home bar in the title area.\nOff keeps the chromeless look.")
    guard let toolbar = Prompt.confirmOrCancel(
        "Show navigation toolbar?", defaultYes: seed.toolbar) else { return nil }
    result.toolbar = toolbar
    if toolbar {
        // Only ask about size when the toolbar is shown — it's inert otherwise.
        guard let compact = Prompt.confirmOrCancel(
            "  └ Use the compact (smaller) toolbar?",
            defaultYes: seed.toolbarStyle == .compact) else { return nil }
        result.toolbarStyle = compact ? .compact : .regular
    } else {
        result.toolbarStyle = seed.toolbarStyle
    }

    // Step 5 — progress line.
    Prompt.step(5, of: total, title: "Progress line",
                help: "A thin accent line at the top edge that tracks page loads\nand fades out when done.")
    guard let progressBar = Prompt.confirmOrCancel(
        "Show page-load progress line?", defaultYes: seed.progressBar) else { return nil }
    result.progressBar = progressBar

    // Step 6 — URL handling: links leaving the app, incoming URLs, and the conditional
    // off-domain follow-up. Handler-only apps exist to receive links, so there's
    // nothing to ask — handling is forced on (and external links are moot: an app
    // that accepts any domain browses everything in-window).
    if handlerOnly {
        Prompt.step(6, of: total, title: "URL handling",
                    help: "Handler-only app: it receives any URL routed to it, so URL\nhandling is enabled automatically.")
        result.handleURLs = true
        result.openAnyURL = true
    } else {
        Prompt.step(6, of: total, title: "URL handling",
                    help: "How URLs flow out of and into the app: links that leave the\nsite can open in your default browser, and the app can register\nas an http/https handler so links from other apps (e.g. Choosy)\nload in it.")
        guard let externalLinks = Prompt.confirmOrCancel(
            "Open links that leave the site in your default browser?",
            defaultYes: seed.externalLinks) else { return nil }
        result.externalLinks = externalLinks
        guard let handleURLs = Prompt.confirmOrCancel(
            "Open URLs the app is launched with?", defaultYes: seed.handleURLs) else { return nil }
        result.handleURLs = handleURLs
        if handleURLs {
            guard let openAny = Prompt.confirmOrCancel(
                "  └ Accept off-domain URLs too (default: only same-site)?",
                defaultYes: seed.openAnyURL) else { return nil }
            result.openAnyURL = openAny
        } else {
            result.openAnyURL = false
        }
    }

    // Step 7 — background color.
    Prompt.step(7, of: total, title: "Background color",
                help: "A hex color (e.g. #1a73e8) painted behind the page to avoid\na white flash on launch. Blank for none.")
    let bgDefaultDisplay = seed.backgroundColor ?? "none"
    guard let background = Prompt.askWithDefault(
        "Window background color", default: seed.backgroundColor, defaultDisplay: bgDefaultDisplay,
        validate: colorValidator) else { return nil }
    result.backgroundColor = background

    // Step 8 — user agent (browser identity).
    Prompt.step(8, of: total, title: "Browser identity",
                help: "The user agent the app reports: safari (default), chrome, edge,\nor a full custom UA string. Helps with \"browser not supported\" pages.")
    guard let userAgent = Prompt.askWithDefault(
        "User agent", default: seed.userAgent, defaultDisplay: seed.userAgent ?? "safari",
        validate: { .valid($0) }) else { return nil }
    result.userAgent = userAgent

    // Step 9 — icon.
    let iconBlankMeans = context == .create ? "resolve from the site" : "keep the existing icon"
    Prompt.step(9, of: total, title: "Icon",
                help: "Path to a .png or .icns file. Blank to \(iconBlankMeans).")
    let iconDefaultDisplay = seed.iconPath ?? (context == .create ? "resolve from site" : "keep existing")
    guard let iconPath = Prompt.askWithDefault(
        "Icon path", default: seed.iconPath, defaultDisplay: iconDefaultDisplay,
        validate: iconValidator) else { return nil }
    result.iconPath = iconPath

    // Step 10 — signing.
    Prompt.step(10, of: total, title: "Signing",
                help: "Ad-hoc signing works for local use. Developer ID + notarization\nis for distributing the app to others.")
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
    guard let wantDevID = Prompt.confirmOrCancel(
        "Sign with a Developer ID identity (otherwise ad-hoc)?",
        defaultYes: seed.signIdentity != nil) else { return nil }
    guard wantDevID else {
        // Ad-hoc is the default; nothing more to ask.
        return (noSign: false, signIdentity: nil, notarize: false, notaryProfile: nil)
    }

    guard let identity = Prompt.askWithDefault(
        "  └ Developer ID identity",
        default: seed.signIdentity, defaultDisplay: seed.signIdentity ?? "(required)",
        validate: { input in
            input.isEmpty ? .invalid("Identity must not be empty.") : .valid(input)
        }) else { return nil }
    guard let identity, !identity.isEmpty else {
        // User accepted an empty default — treat as ad-hoc rather than an invalid sign.
        return (noSign: false, signIdentity: nil, notarize: false, notaryProfile: nil)
    }

    guard let wantNotarize = Prompt.confirmOrCancel(
        "  └ Notarize and staple with Apple?", defaultYes: seed.notarize) else { return nil }
    guard wantNotarize else {
        return (noSign: false, signIdentity: identity, notarize: false, notaryProfile: nil)
    }

    guard let profile = Prompt.askWithDefault(
        "  └ notarytool store-credentials profile",
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
