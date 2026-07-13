import Foundation

struct AppBuilder {
    let url: String
    let name: String
    let outputDir: String
    let bundleId: String?
    let iconPath: String?
    let width: Int
    let height: Int
    /// Whether the generated app shows a navigation toolbar (back/forward/reload).
    let showToolbar: Bool
    /// The navigation toolbar's size (regular/compact). Only meaningful when `showToolbar`
    /// is on. (`--toolbar-size`.)
    var toolbarStyle: ToolbarStyle = .default
    /// Whether the generated app shows a thin page-load progress line at the top of the
    /// window. Off by default. (`--progress-bar`.)
    var progressBar: Bool = false
    let force: Bool
    /// Whether to sign at all. When false (`--no-sign`), the bundle is left unsigned.
    let sign: Bool
    /// A Developer ID identity to sign with, e.g. "Developer ID Application: Name (TEAMID)".
    /// When set, the bundle is signed with this identity and the hardened runtime instead
    /// of an ad-hoc signature. When nil (and `sign` is true), an ad-hoc signature is used.
    var signIdentity: String? = nil
    /// Whether to notarize the signed bundle with Apple and staple the ticket. Requires
    /// `signIdentity` and `notaryProfile`.
    var notarize: Bool = false
    /// Name of a `notarytool store-credentials` keychain profile used to authenticate
    /// the notarization submission.
    var notaryProfile: String? = nil
    /// An icon already resolved from the site (e.g. by the interactive flow, which
    /// resolves up front to show the source in its summary). When set, the builder
    /// uses these bytes instead of fetching again. `iconPath` still takes precedence.
    var resolvedIcon: IconResolver.Resolved? = nil
    /// Window background color (a CSS color string) baked into the bundle so the host
    /// can paint the window before first paint. Nil when unknown. Typically the site's
    /// manifest `background_color`/`theme_color`, resolved at create time.
    var backgroundColor: String? = nil
    /// User-agent setting baked into the bundle: a preset token (safari/chrome/edge)
    /// or a literal UA string. Nil means the default (Safari-equivalent UA). The host
    /// resolves it via `UserAgent`. (`--user-agent`.)
    var userAgent: String? = nil
    /// Whether the app registers as an http/https handler (CFBundleURLTypes) and
    /// navigates to URLs it's opened with. Off by default. (`--handle-urls`.)
    var handleURLs: Bool = false
    /// When `handleURLs` is on, whether to accept off-domain incoming URLs too. When
    /// false, only same-site URLs are loaded. (`--open-any-url`.)
    var openAnyURL: Bool = false

    private let fm = FileManager.default

    /// Builds the bundle and returns its final path.
    func build() throws -> String {
        let appPath = (outputDir as NSString).appendingPathComponent("\(name).app")

        if fm.fileExists(atPath: appPath) {
            guard force else {
                throw RuntimeError("\(appPath) already exists. Pass --force to overwrite.")
            }
            try fm.removeItem(atPath: appPath)
        }

        let contents = (appPath as NSString).appendingPathComponent("Contents")
        let macOS = (contents as NSString).appendingPathComponent("MacOS")
        let resources = (contents as NSString).appendingPathComponent("Resources")

        for dir in [contents, macOS, resources] {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        // Copy our own binary in as the app's executable. The same binary
        // detects WEBWRAP_HOST=1 (set via LSEnvironment below) and runs in host mode.
        let selfPath = try ownExecutablePath()
        let execName = "webwrap-host"
        let destExec = (macOS as NSString).appendingPathComponent(execName)
        try fm.copyItem(atPath: selfPath, toPath: destExec)
        try makeExecutable(destExec)

        // Icon
        let iconFileName = "AppIcon.icns"
        try installIcon(into: resources, named: iconFileName)

        // Info.plist
        let plist = makeInfoPlist(executable: execName, iconFile: iconFileName)
        let plistPath = (contents as NSString).appendingPathComponent("Info.plist")
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)

        // PkgInfo (harmless, expected by some tooling)
        let pkgInfo = (contents as NSString).appendingPathComponent("PkgInfo")
        try "APPL????".write(toFile: pkgInfo, atomically: true, encoding: .utf8)

        if sign {
            try codesign(appPath)
        }

        if notarize {
            try notarizeAndStaple(appPath)
        }

        return appPath
    }

    // MARK: - Bundle identifier

    private func resolvedBundleId() -> String {
        Self.defaultBundleId(name: name, override: bundleId)
    }

    /// Lowercases a display name and collapses runs of non-alphanumerics into single
    /// hyphens, e.g. "Microsoft Outlook!" → "microsoft-outlook". Empty input → "app".
    static func slug(from name: String) -> String {
        let slug = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return slug.isEmpty ? "app" : slug
    }

    /// The bundle identifier for an app: the explicit `override` if given, otherwise
    /// `dk.yepz.webwrap.<slug>` derived from the name.
    static func defaultBundleId(name: String, override: String?) -> String {
        if let override, !override.isEmpty { return override }
        return "dk.yepz.webwrap.\(slug(from: name))"
    }

    // MARK: - Info.plist

    private func makeInfoPlist(executable: String, iconFile: String) -> String {
        Self.makeInfoPlist(
            name: name,
            url: url,
            bundleId: resolvedBundleId(),
            executable: executable,
            iconFile: iconFile,
            width: width,
            height: height,
            showToolbar: showToolbar,
            toolbarStyle: toolbarStyle,
            progressBar: progressBar,
            backgroundColor: backgroundColor,
            userAgent: userAgent,
            handleURLs: handleURLs,
            openAnyURL: openAnyURL,
            creatorVersion: WebWrap.configuration.version
        )
    }

    /// Builds the bundle's `Info.plist` XML. Pure (no `self`, no I/O) so it can be
    /// unit-tested directly. `creatorVersion` is the webwrap version that created the
    /// bundle, baked in so the generated app's About panel can report it.
    static func makeInfoPlist(name: String,
                              url: String,
                              bundleId: String,
                              executable: String,
                              iconFile: String,
                              width: Int,
                              height: Int,
                              showToolbar: Bool,
                              toolbarStyle: ToolbarStyle = .default,
                              progressBar: Bool = false,
                              backgroundColor: String? = nil,
                              userAgent: String? = nil,
                              handleURLs: Bool = false,
                              openAnyURL: Bool = false,
                              creatorVersion: String) -> String {
        let escapedName = xmlEscape(name)
        let escapedURL = xmlEscape(url)
        let escapedCreator = xmlEscape(creatorVersion)
        // Optional key: emitted only when a color is known, so older/manifest-less apps
        // carry no WebWrapBackgroundColor at all. The newline keeps plist formatting tidy.
        let backgroundColorEntry: String
        if let backgroundColor, !backgroundColor.isEmpty {
            backgroundColorEntry = """
                <key>WebWrapBackgroundColor</key>
                <string>\(xmlEscape(backgroundColor))</string>

            """
        } else {
            backgroundColorEntry = ""
        }
        // Optional key, same shape as the background color: absent means "default
        // (Safari) user agent".
        let userAgentEntry: String
        if let userAgent, !userAgent.isEmpty {
            userAgentEntry = """
                <key>WebWrapUserAgent</key>
                <string>\(xmlEscape(userAgent))</string>

            """
        } else {
            userAgentEntry = ""
        }
        // Register as an http/https viewer ONLY when handling URLs is enabled, so apps
        // don't claim those schemes system-wide unless the user opted in. Emitted just
        // before the closing </dict>.
        let urlTypesEntry: String
        if handleURLs {
            urlTypesEntry = """
                <key>CFBundleURLTypes</key>
                <array>
                    <dict>
                        <key>CFBundleURLName</key>
                        <string>\(bundleId)</string>
                        <key>CFBundleTypeRole</key>
                        <string>Viewer</string>
                        <key>CFBundleURLSchemes</key>
                        <array>
                            <string>http</string>
                            <string>https</string>
                        </array>
                    </dict>
                </array>

            """
        } else {
            urlTypesEntry = ""
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>\(escapedName)</string>
            <key>CFBundleDisplayName</key>
            <string>\(escapedName)</string>
            <key>CFBundleExecutable</key>
            <string>\(executable)</string>
            <key>CFBundleIdentifier</key>
            <string>\(bundleId)</string>
            <key>CFBundleIconFile</key>
            <string>\(iconFile)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>LSMinimumSystemVersion</key>
            <string>13.0</string>
            <key>NSHighResolutionCapable</key>
            <true/>
            <key>LSEnvironment</key>
            <dict>
                <key>WEBWRAP_HOST</key>
                <string>1</string>
            </dict>
            <key>WebWrapURL</key>
            <string>\(escapedURL)</string>
            <key>WebWrapWidth</key>
            <string>\(width)</string>
            <key>WebWrapHeight</key>
            <string>\(height)</string>
            <key>WebWrapToolbar</key>
            <string>\(showToolbar ? "1" : "0")</string>
            <key>WebWrapToolbarStyle</key>
            <string>\(toolbarStyle.rawValue)</string>
            <key>WebWrapProgressBar</key>
            <string>\(progressBar ? "1" : "0")</string>
            <key>WebWrapHandleURLs</key>
            <string>\(handleURLs ? "1" : "0")</string>
            <key>WebWrapOpenAnyURL</key>
            <string>\(openAnyURL ? "1" : "0")</string>
            \(backgroundColorEntry)\(userAgentEntry)\(urlTypesEntry)<key>WebWrapCreatorVersion</key>
            <string>\(escapedCreator)</string>
        </dict>
        </plist>
        """
    }

    // MARK: - Icon

    private func installIcon(into resources: String, named iconFileName: String) throws {
        let dest = (resources as NSString).appendingPathComponent(iconFileName)

        if let iconPath {
            let ext = (iconPath as NSString).pathExtension.lowercased()
            if ext == "icns" {
                try fm.copyItem(atPath: iconPath, toPath: dest)
                return
            }
            if ext == "png" {
                try convertPNGtoICNS(png: iconPath, icns: dest)
                return
            }
            throw RuntimeError("Icon must be a .png or .icns file.")
        }

        // No icon path supplied: use a pre-resolved icon if the caller provided one
        // (the interactive flow does, to show the source in its summary), otherwise
        // resolve now (manifest → link icon → favicon). Every step is best-effort;
        // on any failure we skip the icon and the app gets the default bundle icon.
        guard let resolved = resolvedIcon ?? IconResolver(urlString: url)?.resolve() else { return }

        let tmpImage = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("webwrap-icon-\(UUID().uuidString).\(resolved.ext)")
        try resolved.data.write(to: URL(fileURLWithPath: tmpImage))
        defer { try? fm.removeItem(atPath: tmpImage) }
        do {
            try convertPNGtoICNS(png: tmpImage, icns: dest)
        } catch {
            // Conversion failed (e.g. a format sips can't read) — skip the icon rather
            // than failing the whole build, but make it visible instead of mysterious.
            FileHandle.standardError.write(Data(
                "⚠ Found an icon (\(resolved.source.rawValue)) but couldn't convert it to .icns — the app will use the default icon.\n".utf8))
        }
    }

    /// Converts a source image to .icns using the built-in `sips` + `iconutil` tools.
    private func convertPNGtoICNS(png: String, icns dest: String) throws {
        let work = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("webwrap-\(UUID().uuidString).iconset")
        try fm.createDirectory(atPath: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: work) }

        // Normalize the source to a flat PNG first. sips can fail to upscale the larger
        // iconset sizes (512/1024) directly from a multi-image .ico (e.g. a 64×64
        // /favicon.ico), which leaves the iconset incomplete and makes iconutil refuse
        // to build the .icns. Resizing from a single-image PNG avoids that entirely.
        let flat = (work as NSString).appendingPathComponent("source.png")
        try run("/usr/bin/sips", ["-s", "format", "png", png, "--out", flat], quiet: true)

        // Standard iconset sizes. sips upscales/downscales as needed.
        let sizes: [(Int, String)] = [
            (16, "icon_16x16.png"),
            (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),
            (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),
            (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),
            (1024, "icon_512x512@2x.png")
        ]

        for (size, fileName) in sizes {
            let out = (work as NSString).appendingPathComponent(fileName)
            try run("/usr/bin/sips", ["-z", "\(size)", "\(size)", flat, "--out", out], quiet: true)
        }

        // The flat source isn't a valid iconset entry name; remove it before iconutil.
        try? fm.removeItem(atPath: flat)
        try run("/usr/bin/iconutil", ["-c", "icns", work, "-o", dest], quiet: true)
    }

    // MARK: - Signing

    private func codesign(_ appPath: String) throws {
        if let signIdentity {
            // Developer ID signature with the hardened runtime — required for
            // notarization and standard for apps distributed to other Macs.
            try run("/usr/bin/codesign",
                    ["--force", "--deep", "--options", "runtime",
                     "--sign", signIdentity, appPath],
                    quiet: true)
        } else {
            // Ad-hoc signature (no Developer ID). Enough to satisfy Gatekeeper for a
            // locally-built app; for distribution to others, sign with a real identity
            // and notarize instead.
            try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", appPath], quiet: true)
        }
    }

    // MARK: - Notarization

    /// Submits the signed bundle to Apple's notary service and, on acceptance, staples
    /// the ticket so the app passes Gatekeeper offline. Zips the bundle for submission
    /// (notarytool requires an archive, not a raw `.app`).
    private func notarizeAndStaple(_ appPath: String) throws {
        guard let notaryProfile else {
            throw RuntimeError("Notarization requires a --notary-profile.")
        }

        let zipPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("webwrap-notarize-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(atPath: zipPath) }

        // ditto preserves the bundle structure/symlinks that a plain zip would mangle.
        print("Zipping for notarization…")
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", appPath, zipPath], quiet: true)

        print("Submitting to Apple notary service (this can take a few minutes)…")
        let (status, output) = try runCapturingAll(
            "/usr/bin/xcrun",
            ["notarytool", "submit", zipPath,
             "--keychain-profile", notaryProfile,
             "--wait"])

        // notarytool prints a human summary including a "status: Accepted/Invalid" line.
        guard status == 0, output.contains("status: Accepted") else {
            // Pull the submission id so we can fetch the detailed log for the user.
            let detail = submissionLog(from: output, profile: notaryProfile)
            throw RuntimeError("""
                Notarization failed.
                \(output.trimmingCharacters(in: .whitespacesAndNewlines))
                \(detail)
                """)
        }

        print("Notarized. Stapling ticket…")
        try run("/usr/bin/xcrun", ["stapler", "staple", appPath], quiet: true)
    }

    /// Best-effort retrieval of the detailed notary log for a failed submission, so the
    /// error message tells the user *why* it was rejected rather than just "Invalid".
    private func submissionLog(from submitOutput: String, profile: String) -> String {
        // notarytool's output contains a line like "  id: <uuid>".
        let id = submitOutput
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("id: ") else { return nil }
                return String(trimmed.dropFirst(4))
            }
            .first
        guard let id else { return "" }
        let (_, log) = (try? runCapturingAll(
            "/usr/bin/xcrun",
            ["notarytool", "log", id, "--keychain-profile", profile])) ?? (1, "")
        return log.isEmpty ? "" : "Notary log:\n\(log)"
    }

    // MARK: - Helpers

    private func ownExecutablePath() throws -> String {
        // Resolve the real, symlink-free path of the currently running binary.
        // This matters under Homebrew, where /opt/homebrew/bin/webwrap is a
        // symlink into the Cellar — copying the symlink itself would produce a
        // broken executable inside the bundle.
        let argv0 = CommandLine.arguments.first ?? "webwrap"

        var candidate: String
        if argv0.contains("/") {
            candidate = (argv0 as NSString).standardizingPath
        } else {
            // Bare name (ran from PATH): locate via `which`.
            let resolved = try runCapturing("/usr/bin/which", [argv0])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !resolved.isEmpty else {
                throw RuntimeError("Could not locate the running webwrap binary to copy into the bundle.")
            }
            candidate = resolved
        }

        // Follow symlinks to the real file.
        let real = (try? fm.destinationOfSymbolicLink(atPath: candidate)).map { dest -> String in
            dest.hasPrefix("/")
                ? dest
                : ((candidate as NSString).deletingLastPathComponent as NSString)
                    .appendingPathComponent(dest)
        } ?? candidate

        let resolved = (real as NSString).standardizingPath
        guard fm.fileExists(atPath: resolved) else {
            throw RuntimeError("Resolved webwrap binary path does not exist: \(resolved)")
        }
        return resolved
    }

    private func makeExecutable(_ path: String) throws {
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    /// Escapes the five XML predefined entities. Ampersand is replaced first so the
    /// `&` it introduces in the other replacements isn't double-escaped.
    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    @discardableResult
    private func run(_ launchPath: String, _ args: [String], quiet: Bool = false) throws -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        if quiet {
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
        }
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw RuntimeError("\(launchPath) exited with status \(proc.terminationStatus).")
        }
        return proc.terminationStatus
    }

    private func runCapturing(_ launchPath: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Runs a process, capturing stdout and stderr together, and returns the exit status
    /// alongside the combined output. Used for notarytool, where both the result summary
    /// and any error detail matter and we don't want a nonzero exit to throw before we've
    /// read the output.
    private func runCapturingAll(_ launchPath: String, _ args: [String]) throws -> (Int32, String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        // Read before waiting to avoid deadlock if the child fills the pipe buffer.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

struct RuntimeError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
