# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-06-23

### Added
- `webwrap create` command to wrap a website into a standalone macOS `.app`.
- Single-binary dual-mode design: the same executable acts as the CLI scaffolder
  and, when copied into a generated bundle, as the `WKWebView` host (detected via
  the `WEBWRAP_HOST` environment variable set in the bundle's `Info.plist`).
- Persistent login sessions across relaunches. On macOS 14+ each generated app
  gets an isolated `WKWebsiteDataStore` keyed to its bundle identifier (independent
  logins per app); on macOS 13 apps share the default persistent store.
- Automatic favicon fetching when no `--icon` is supplied.
- PNG/ICNS icon support via `sips` and `iconutil`.
- Window frame autosave (remembers size and position per app).
- Ad-hoc code signing of generated bundles (skippable with `--no-sign`).
- Configurable window size (`--width`, `--height`), output directory (`--output`),
  and bundle identifier (`--bundle-id`).
- Prebuilt universal (arm64 + x86_64) binary distribution via GitHub Actions
  (`.github/workflows/release.yml`) and a Homebrew formula that downloads it —
  no Xcode required for end users.
- CI workflow building and smoke-testing the CLI on every push and PR.

[Unreleased]: https://github.com/yepzdk/webwrap/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yepzdk/webwrap/releases/tag/v0.1.0
