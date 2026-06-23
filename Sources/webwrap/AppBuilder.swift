import Foundation

struct AppBuilder {
    let url: String
    let name: String
    let outputDir: String
    let bundleId: String?
    let iconPath: String?
    let width: Int
    let height: Int
    let force: Bool
    let sign: Bool

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

        return appPath
    }

    // MARK: - Bundle identifier

    private func resolvedBundleId() -> String {
        if let bundleId { return bundleId }
        let slug = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "dk.yepz.webwrap.\(slug.isEmpty ? "app" : slug)"
    }

    // MARK: - Info.plist

    private func makeInfoPlist(executable: String, iconFile: String) -> String {
        let escapedName = xmlEscape(name)
        let escapedURL = xmlEscape(url)
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
            <string>\(resolvedBundleId())</string>
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

        // No icon supplied: try to fetch the site's favicon. On failure, skip
        // (the app simply gets the default bundle icon).
        if let png = try? fetchFavicon() {
            let tmpPNG = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("webwrap-favicon-\(UUID().uuidString).png")
            try png.write(to: URL(fileURLWithPath: tmpPNG))
            defer { try? fm.removeItem(atPath: tmpPNG) }
            if (try? convertPNGtoICNS(png: tmpPNG, icns: dest)) == nil {
                // Conversion failed (e.g. favicon too small / not square) — skip icon.
            }
        }
    }

    private func fetchFavicon() throws -> Data? {
        guard let host = URL(string: url)?.host else { return nil }
        // Google's favicon service returns a clean, reliably-sized PNG.
        let endpoint = "https://www.google.com/s2/favicons?sz=256&domain=\(host)"
        guard let favURL = URL(string: endpoint) else { return nil }
        return try Data(contentsOf: favURL)
    }

    /// Converts a PNG to .icns using the built-in `sips` + `iconutil` tools.
    private func convertPNGtoICNS(png: String, icns dest: String) throws {
        let work = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("webwrap-\(UUID().uuidString).iconset")
        try fm.createDirectory(atPath: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: work) }

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
            try run("/usr/bin/sips", ["-z", "\(size)", "\(size)", png, "--out", out], quiet: true)
        }

        try run("/usr/bin/iconutil", ["-c", "icns", work, "-o", dest], quiet: true)
    }

    // MARK: - Signing

    private func codesign(_ appPath: String) throws {
        // Ad-hoc signature (no Developer ID). Enough to satisfy Gatekeeper for a
        // locally-built app; for distribution to others, sign with a real identity
        // and notarize instead.
        try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", appPath], quiet: true)
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

    private func xmlEscape(_ s: String) -> String {
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
}

struct RuntimeError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
