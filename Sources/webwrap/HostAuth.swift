import Foundation

/// Pure handling of HTTP authentication challenges (Basic, Digest, NTLM), kept free of
/// AppKit/WebKit so the decision and prompt text are unit-testable. The host feeds it the
/// challenge's fields and acts on the result; the login sheet itself lives in `HostDelegate`.
///
/// Without a handler WKWebView answers these challenges with default handling, which sends
/// no credential and shows the server's 401 body (#127). Safari's login sheet is Safari's
/// own, not WebKit's.
///
/// Saving is left to WebKit: a credential answered with `.permanent` persistence lands in
/// the login keychain scoped to the app's website data store, and WebKit sends it up front
/// on later launches — so a remembered login raises no challenge at all. A challenge only
/// reaches us again when nothing is saved or the saved password was rejected.
enum HostAuth {
    /// The authentication schemes that take a user name and password from a prompt.
    /// Everything else — server trust, client certificates, Negotiate/Kerberos — keeps
    /// WebKit's default handling.
    static let promptedMethods: Set<String> = [
        NSURLAuthenticationMethodHTTPBasic,
        NSURLAuthenticationMethodHTTPDigest,
        NSURLAuthenticationMethodNTLM,
    ]

    /// What the login sheet should show.
    struct Prompt: Equatable {
        /// The host as shown to the user, with the port only when it isn't the scheme's default.
        let site: String
        /// User name to pre-fill: the rejected one on a retry, so only the password needs retyping.
        let username: String?
        /// True when a previous attempt (typed or saved) was rejected.
        let rejected: Bool
        /// False when the credential would cross the network in the clear (Basic over http).
        let secure: Bool
    }

    enum Action: Equatable {
        /// Answer with the credential WebKit already proposes (saved, not yet tried).
        case useProposed
        /// Ask the user.
        case prompt(Prompt)
        /// Not a password challenge: let WebKit handle it as before.
        case performDefaultHandling
    }

    /// Decides how to answer a challenge. `proposedUser`/`proposedHasPassword` describe
    /// `challenge.proposedCredential`; on a retry that is the credential just rejected.
    static func action(method: String,
                       host: String,
                       port: Int,
                       scheme: String?,
                       previousFailureCount: Int,
                       proposedUser: String?,
                       proposedHasPassword: Bool,
                       receivesCredentialSecurely: Bool) -> Action {
        guard promptedMethods.contains(method) else { return .performDefaultHandling }
        let rejected = previousFailureCount > 0
        if !rejected, proposedHasPassword {
            return .useProposed
        }
        let user = proposedUser.flatMap { $0.isEmpty ? nil : $0 }
        return .prompt(Prompt(site: site(host: host, port: port, scheme: scheme),
                              username: user,
                              rejected: rejected,
                              secure: receivesCredentialSecurely))
    }

    /// `host`, plus `:port` when the port isn't the default for the scheme.
    static func site(host: String, port: Int, scheme: String?) -> String {
        let defaultPort: Int?
        switch scheme?.lowercased() {
        case "https": defaultPort = 443
        case "http": defaultPort = 80
        default: defaultPort = nil
        }
        return port > 0 && port != defaultPort ? "\(host):\(port)" : host
    }

    /// The sheet's heading.
    static func title(for prompt: Prompt) -> String {
        "Log in to \(prompt.site)"
    }

    /// The sheet's explanatory line: why it's asking again, and a warning when the
    /// password would be sent unencrypted.
    static func message(for prompt: Prompt) -> String {
        var lines: [String] = []
        if prompt.rejected {
            lines.append("The user name or password was not accepted. Try again.")
        } else {
            lines.append("This site requires a user name and password.")
        }
        if !prompt.secure {
            lines.append("Your password will be sent unencrypted.")
        }
        return lines.joined(separator: " ")
    }

    /// Persistence for the answered credential: `.permanent` saves it to the keychain,
    /// `.forSession` keeps it until the app quits.
    static func persistence(remember: Bool) -> URLCredential.Persistence {
        remember ? .permanent : .forSession
    }
}
