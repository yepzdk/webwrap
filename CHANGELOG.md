# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Developer ID signing and notarization for generated apps. `--sign "Developer ID
  Application: …"` signs with a real identity and the hardened runtime; `--notarize`
  (with `--notary-profile`) submits to Apple's notary service and staples the ticket,
  so the app passes Gatekeeper on other Macs without a right-click or `xattr`. Without
  these flags, ad-hoc signing is unchanged.
- `og:image` / `twitter:image` as an icon source, slotted above the favicon
  fallbacks. Only used when the image is close to square (within ~15% of 1:1) so
  wide sharing banners don't get distorted into an icon.

### Fixed
- Generated apps no longer end up icon-less for sites whose only icon is a
  multi-image `.ico` (e.g. a 64×64 `/favicon.ico`). The source is now normalized
  to a flat PNG before building the iconset, which `sips` can upscale reliably.
- A failed icon conversion now prints a warning instead of silently producing an
  app with the default icon.
- Placeholder `data:` icon links (e.g. `<link rel="icon" href="data:,">`, as on
  `example.com`) are now skipped rather than fetched and failed, so the resolver
  falls through cleanly to the next source without a spurious warning.

## [0.1.0] - 2026-06-23

### Added
- `webwrap create` command to wrap a website into a standalone macOS `.app`.
- Interactive `webwrap create`: run it without `--url`/`--name` and it prompts for
  them, validates the URL, suggests a name from the site host, shows the resolved
  icon source, and asks for confirmation before writing. Non-interactive input
  (pipes, CI) still requires the flags and never prompts.
- `webwrap list` subcommand: shows the wrapped apps installed in `/Applications`
  and `~/Applications` along with the URL each opens. Apps are identified by a
  marker in their `Info.plist`, so there's no separate registry to maintain.
- Single-binary dual-mode design: the same executable acts as the CLI scaffolder
  and, when copied into a generated bundle, as the `WKWebView` host (detected via
  the `WEBWRAP_HOST` environment variable set in the bundle's `Info.plist`).
- Persistent login sessions across relaunches. On macOS 14+ each generated app
  gets an isolated `WKWebsiteDataStore` keyed to its bundle identifier (independent
  logins per app); on macOS 13 apps share the default persistent store.
- Smart icon resolution when no `--icon` is supplied: walks a chain of sources —
  web app manifest, `apple-touch-icon`, `<link rel="icon">`, `/favicon.ico`, and
  finally a favicon service — picking the highest-quality icon available.
- PNG/ICNS icon support via `sips` and `iconutil`.
- Window frame autosave (remembers size and position per app).
- Ad-hoc code signing of generated bundles (skippable with `--no-sign`).
- Configurable window size (`--width`, `--height`), output directory (`--output`),
  and bundle identifier (`--bundle-id`).
- Prebuilt universal (arm64 + x86_64) binary distribution via GitHub Actions
  (`.github/workflows/release.yml`) and a Homebrew formula that downloads it —
  no Xcode required for end users.
- CI workflow building, testing, and smoke-testing the CLI on every push and PR.
- Test suite (`swift test`) covering `AppBuilder`'s pure helpers (slug, bundle id,
  `Info.plist` generation, XML escaping) plus the icon-resolution and CLI helpers.

[Unreleased]: https://github.com/yepzdk/webwrap/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yepzdk/webwrap/releases/tag/v0.1.0
