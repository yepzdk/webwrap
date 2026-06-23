# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

`webwrap` is a macOS-only Swift command-line tool that wraps a website into a standalone `.app` bundle built around a `WKWebView`. It is a lightweight alternative to Unite/WebCatalog. Distributed via the `yepzdk/homebrew-tools` tap.

## Architecture

A **single binary** runs in two modes — this is the central design decision, do not split it into two executables:

- **CLI mode**: `webwrap create ...` scaffolds an `.app`. Entry: `main.swift` → `WebWrap.main()` → `Create.run()` → `AppBuilder.build()`.
- **Host mode**: the same binary is copied into the generated bundle's `Contents/MacOS/`. The bundle's `Info.plist` sets `WEBWRAP_HOST=1` via `LSEnvironment`. On launch, `main.swift` detects that variable and calls `runHost()` instead of parsing arguments.

The target URL and window size are passed from CLI to host via custom `Info.plist` keys (`WebWrapURL`, `WebWrapWidth`, `WebWrapHeight`) baked in at create time.

### Files

- `Sources/webwrap/main.swift` — mode router (host vs CLI).
- `Sources/webwrap/CLI.swift` — `ParsableCommand` definitions (`WebWrap`, `Create`).
- `Sources/webwrap/Host.swift` — the `WKWebView` host (`runHost()` + `HostDelegate`).
- `Sources/webwrap/AppBuilder.swift` — bundle scaffolding, `Info.plist`, icon conversion, signing.

## Build & test

```sh
swift build                 # debug
swift build -c release      # release
swift run webwrap create -u https://example.com -n "Example Test" -o /tmp --force
open /tmp/Example\ Test.app
```

There is no test suite yet. When adding one, use `swift test` with an `xcunit`/`Testing` target and keep `AppBuilder`'s pure helpers (slug, plist generation, xml escaping) unit-testable by separating them from filesystem side effects.

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
3. Copy the published `sha256` into `dist/homebrew/webwrap.rb` and commit the formula to the `yepzdk/homebrew-tools` tap.

The release binary is built universal so a single bottle serves both Apple Silicon and Intel. The deployment target is macOS 13, but the runner is macOS 14 (newer SDK, lower target is fine).

## Signing & notarization

Generated apps are ad-hoc signed only. Notarization (Developer ID + `xcrun notarytool`) is **not** implemented — it's the top roadmap item. When adding it: a `--sign "Developer ID Application: ..."` option on `Create`, then a `--notarize` flag that staples after `notarytool submit --wait`. The webwrap binary itself shipped via Homebrew should ideally also be notarized for the smoothest install, but that's separate from the apps it generates.

## Known limitations / future ideas

- Ad-hoc signing only; no notarization helper yet (top roadmap item — see above).
- No `list`/`remove` subcommands for managing generated apps.
- Single window per app; no tabs.
- Per-app session isolation requires macOS 14+ (`WKWebsiteDataStore(forIdentifier:)`); on macOS 13 apps share the default persistent store. See `Host.makeDataStore()`.
- Favicon fallback can fail silently for sites with tiny/non-square icons.
