# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

`webwrap` is a macOS-only Swift command-line tool that wraps a website into a standalone `.app` bundle built around a `WKWebView`. It is a lightweight alternative to Unite/WebCatalog. Distributed via the `yepzdk/homebrew-tools` tap.

## Architecture

A **single binary** runs in two modes — this is the central design decision, do not split it into two executables:

- **CLI mode**: `webwrap create ...` scaffolds an `.app`. Entry: `main.swift` → `WebWrap.main()` → `Create.run()` → `AppBuilder.build()`.
- **Host mode**: the same binary is copied into the generated bundle's `Contents/MacOS/`. The bundle's `Info.plist` sets `WEBWRAP_HOST=1` via `LSEnvironment`. On launch, `main.swift` detects that variable and calls `runHost()` instead of parsing arguments.

The target URL and window size are passed from CLI to host via custom `Info.plist` keys (`WebWrapURL`, `WebWrapWidth`, `WebWrapHeight`, and `WebWrapCreatorVersion` for the About panel) baked in at create time.

### Files

- `Sources/webwrap/main.swift` — mode router (host vs CLI).
- `Sources/webwrap/CLI.swift` — `ParsableCommand` definitions (`WebWrap`, `Create`, `List`, `Update`).
- `Sources/webwrap/Host.swift` — the `WKWebView` host (`runHost()` + `HostDelegate`), including the app's main menu and About panel.
- `Sources/webwrap/AppBuilder.swift` — bundle scaffolding, `Info.plist`, icon conversion, signing, notarization.
- `Sources/webwrap/IconResolver.swift` — resolves a site's best icon (manifest → apple-touch-icon → link icon → og:image → favicon → favicon service); pure parsing behind an injectable fetch.
- `Sources/webwrap/AppConfig.swift` — reads a generated app's config back from its `Info.plist`; used by `update`.
- `Sources/webwrap/AppRegistry.swift` — discovers installed webwrap apps; used by `list`.
- `Sources/webwrap/Prompt.swift` — interactive stdin/stdout helpers for `create`'s prompt flow.

## Build & test

```sh
swift build                 # debug
swift build -c release      # release
swift run webwrap create -u https://example.com -n "Example Test" -o /tmp --force
open /tmp/Example\ Test.app
```

Tests live in `Tests/webwrapTests` and run with `swift test` (XCTest — not swift-testing, which isn't in the default `macos-14` CI runner toolchain). The pattern is to keep pure logic (slug/plist/xml-escape, icon URL parsing, squareness, config merge, signing-flag validation, About credits) separate from filesystem/process/network side effects, and unit-test the pure parts; AppKit menu wiring and real signing/notarization are verified by hand. CI runs the suite on every push/PR.

## Conventions (itk-dev)

- **Never commit to main.** Branch as `feature/issue-{number}-{description}`.
- **Conventional Commits**: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, etc.
- **CHANGELOG.md** follows Keep a Changelog. Update `[Unreleased]` with every PR (`Added`/`Changed`/`Fixed`/...).
- PRs reference their issue and close it with `Closes #XX`.

## External tools used at runtime

`sips` and `iconutil` (icon → `.icns`), `codesign` (ad-hoc signing). All ship with macOS. The favicon fallback fetches from Google's favicon service.

## Release process

Distribution is via **prebuilt universal binary**, not build-from-source:

1. Bump the version in `CLI.swift` (`CommandConfiguration.version`), the `version` line in `dist/homebrew/webwrap.rb`, and the URL/filename in the formula. Move `[Unreleased]` changelog entries under a new version heading.
2. Commit, then tag `vX.Y.Z` and push the tag. The `.github/workflows/release.yml` workflow builds a universal (arm64 + x86_64) binary on a `macos-14` runner, tarballs it as `webwrap-X.Y.Z-macos-universal.tar.gz`, and attaches it (plus a `.sha256`) to the GitHub release.
3. The same workflow's `update-tap` job then bumps `Formula/webwrap.rb` in the `yepzdk/homebrew-tools` tap to the new release (recomputing the sha from the published asset) and pushes it — so `brew upgrade webwrap` picks it up with no manual step. The in-repo `dist/homebrew/webwrap.rb` is the canonical copy kept in sync by hand in step 1; the tap copy is what users install from. Requires a `HOMEBREW_TAP_TOKEN` repo secret (a PAT with contents-write on the tap; the default `GITHUB_TOKEN` can't push cross-repo).

The release binary is built universal so a single bottle serves both Apple Silicon and Intel. The deployment target is macOS 13, but the runner is macOS 14 (newer SDK, lower target is fine).

## Signing & notarization

Generated apps are **ad-hoc signed by default**. For distribution, `create`/`update` accept `--sign "Developer ID Application: ..."` (signs with the hardened runtime) and `--notarize` with `--notary-profile <name>` (zips, submits via `notarytool submit --wait`, then staples on acceptance). See `AppBuilder.codesign`/`notarizeAndStaple`. The webwrap binary *itself* shipped via Homebrew is **not yet notarized** — that's a separate follow-up (issue #25); it's low-urgency since Homebrew CLI tools rarely trip Gatekeeper.

## Known limitations / future ideas

- The webwrap CLI binary distributed via Homebrew is not itself notarized (#25).
- Single window per app; no tabs.
- Per-app session isolation requires macOS 14+ (`WKWebsiteDataStore(forIdentifier:)`); on macOS 13 apps share the default persistent store. See `Host.makeDataStore()`. The session is keyed to the bundle identifier, which `update` keeps stable so logins survive an update/rename.
- No `remove` subcommand: `list` exists, but removing an app is left to the Trash (deliberate — see issue #5).
