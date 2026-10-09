import Foundation

/// How an existing `.app` bundle is signed, read back so `update` can rebuild it
/// without silently downgrading a distributed app to an ad-hoc signature (#117).
///
/// Signing is the one part of an app's configuration that isn't baked into the
/// `Info.plist` — it lives in the signature itself — so it's read from `codesign`
/// and `stapler`. The parsing is pure and unit-tested; the two process calls are
/// hand-verified like the rest of the external-tool code.
enum BundleSigning {
    struct Info: Equatable {
        /// The Developer ID identity the bundle is signed with, or nil when it's
        /// ad-hoc signed, unsigned, or signed with some other kind of identity.
        var identity: String? = nil
        /// Whether a notarization ticket is stapled to the bundle.
        var isStapled: Bool = false
    }

    /// Reads the bundle's signing state. Anything unreadable — an unsigned bundle,
    /// a missing tool — reads as "no Developer ID, not stapled", which is the same
    /// answer as before this existed, so a probe failure can't break an update.
    static func read(bundlePath: String) -> Info {
        // codesign writes its report to stderr, hence the merged capture.
        let (status, output) = capture("/usr/bin/codesign", ["-dvv", bundlePath])
        guard status == 0, let identity = developerIDIdentity(inCodesignOutput: output) else {
            return Info()
        }
        // Only a Developer-ID-signed app can carry a notary ticket, so the `xcrun` probe
        // is kept behind that: on a Mac without the command line tools installed it would
        // otherwise prompt to install them during an ordinary update.
        let (stapleStatus, _) = capture("/usr/bin/xcrun", ["stapler", "validate", bundlePath])
        return Info(identity: identity, isStapled: stapleStatus == 0)
    }

    /// The Developer ID identity in `codesign -dvv` output, or nil if there isn't one.
    ///
    /// The report lists the certificate chain as `Authority=` lines, leaf first:
    /// the leaf is the signing identity and the rest are Apple's intermediates. An
    /// ad-hoc signature (`Signature=adhoc`) has no `Authority=` lines at all. Only a
    /// Developer ID Application identity is returned, because that's the only kind
    /// that can be handed back to `codesign --sign` and notarized. Pure.
    static func developerIDIdentity(inCodesignOutput output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(authorityPrefix) else { continue }
            let authority = String(trimmed.dropFirst(authorityPrefix.count))
            if authority.hasPrefix("Developer ID Application:") { return authority }
        }
        return nil
    }

    private static let authorityPrefix = "Authority="

    /// Whether this Mac can actually sign with `identity` — the certificate *and* its
    /// private key have to be in the running user's keychain. An identity read off a
    /// bundle says who signed it, not that we can re-sign it: on a second Mac, or on a
    /// recipient's, `codesign --sign` would fail after `build()` has already removed the
    /// old bundle, leaving no app at all. A probe that can't run reads as "not
    /// available", so the update falls back to ad-hoc rather than failing (#117).
    static func isAvailableForSigning(_ identity: String) -> Bool {
        let (status, output) = capture("/usr/bin/security",
                                       ["find-identity", "-v", "-p", "codesigning"])
        guard status == 0 else { return false }
        return codesigningIdentities(inSecurityOutput: output).contains(identity)
    }

    /// The identity names in `security find-identity -v -p codesigning` output.
    ///
    /// Each usable identity is one line — `  1) A1B2… "Developer ID Application: X (TEAM)"`
    /// — and the trailing `1 valid identities found` summary has no quotes, so quoting is
    /// what separates them. Pure.
    static func codesigningIdentities(inSecurityOutput output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard let open = line.firstIndex(of: "\""),
                  let close = line.lastIndex(of: "\""), open < close else { return nil }
            return String(line[line.index(after: open)..<close])
        }
    }

    /// Runs a tool and returns its exit status with stdout and stderr merged. Never
    /// throws: a tool that can't be launched reports a non-zero status like one that
    /// failed, and every caller treats both the same way.
    private static func capture(_ launchPath: String, _ args: [String]) -> (Int32, String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { return (-1, "") }
        // Read before waiting: a full pipe buffer would otherwise deadlock the tool.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
