import XCTest
@testable import webwrap

// Tests for how the host answers HTTP authentication challenges (pure, no WebKit).

final class HostAuthTests: XCTestCase {
    private func action(method: String = NSURLAuthenticationMethodHTTPBasic,
                        port: Int = 443,
                        scheme: String? = "https",
                        failures: Int = 0,
                        proposedUser: String? = nil,
                        proposedHasPassword: Bool = false,
                        secure: Bool = true) -> HostAuth.Action {
        HostAuth.action(method: method, host: "webtop.example.test", port: port, scheme: scheme,
                        previousFailureCount: failures, proposedUser: proposedUser,
                        proposedHasPassword: proposedHasPassword,
                        receivesCredentialSecurely: secure)
    }

    func testPasswordSchemesPrompt() {
        for method in [NSURLAuthenticationMethodHTTPBasic,
                       NSURLAuthenticationMethodHTTPDigest,
                       NSURLAuthenticationMethodNTLM] {
            XCTAssertEqual(action(method: method),
                           .prompt(.init(site: "webtop.example.test", username: nil,
                                         rejected: false, secure: true)),
                           method)
        }
    }

    func testOtherChallengesKeepDefaultHandling() {
        // Server trust must never be answered by us, and client certificates / Kerberos
        // have no user name and password to ask for.
        for method in [NSURLAuthenticationMethodServerTrust,
                       NSURLAuthenticationMethodClientCertificate,
                       NSURLAuthenticationMethodNegotiate] {
            XCTAssertEqual(action(method: method), .performDefaultHandling, method)
        }
    }

    func testUntriedSavedCredentialIsUsedWithoutPrompting() {
        XCTAssertEqual(action(proposedUser: "alice", proposedHasPassword: true), .useProposed)
    }

    func testRejectedCredentialPromptsAgainWithUserName() {
        // Re-sending the rejected credential would loop against the server; ask instead,
        // keeping the user name so only the password needs retyping.
        XCTAssertEqual(action(failures: 1, proposedUser: "alice", proposedHasPassword: true),
                       .prompt(.init(site: "webtop.example.test", username: "alice",
                                     rejected: true, secure: true)))
    }

    func testEmptyProposedUserIsNotPrefilled() {
        XCTAssertEqual(action(failures: 1, proposedUser: ""),
                       .prompt(.init(site: "webtop.example.test", username: nil,
                                     rejected: true, secure: true)))
    }

    func testSiteShowsPortOnlyWhenNotDefault() {
        XCTAssertEqual(HostAuth.site(host: "h.test", port: 443, scheme: "https"), "h.test")
        XCTAssertEqual(HostAuth.site(host: "h.test", port: 80, scheme: "HTTP"), "h.test")
        XCTAssertEqual(HostAuth.site(host: "h.test", port: 8443, scheme: "https"), "h.test:8443")
        XCTAssertEqual(HostAuth.site(host: "h.test", port: 443, scheme: "http"), "h.test:443")
        XCTAssertEqual(HostAuth.site(host: "h.test", port: 0, scheme: "https"), "h.test")
    }
}
