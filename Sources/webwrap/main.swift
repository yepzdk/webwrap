import Foundation
import ArgumentParser

// webwrap runs in one of two modes from a single binary:
//
//  1. CLI mode (default): invoked from a shell with arguments like
//     `webwrap create --url https://... --name "My App"`. Generates a .app bundle.
//
//  2. Host mode: invoked by macOS when the user launches a generated .app.
//     The generated bundle's Info.plist sets the environment variable
//     WEBWRAP_HOST=1 (via LSEnvironment) and carries the target URL in a custom
//     Info.plist key (WebWrapURL). When we detect that variable on launch, we
//     skip argument parsing entirely and boot the WebKit window instead.
//
// This keeps everything in a single executable: the same binary that scaffolds
// the app is the binary copied into the app, where it acts as the web host.

if ProcessInfo.processInfo.environment["WEBWRAP_HOST"] == "1" {
    runHost()
} else {
    WebWrap.main()
}
