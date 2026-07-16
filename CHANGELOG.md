# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Reader mode**: ⇧⌘R (View → Toggle Reader View) renders the current article as a
  clean, distraction-free page — powered by Mozilla's Readability, the library behind
  Firefox's reader view — in every generated app. `--reader` on `create`/`update`
  makes it automatic per app. (#70)
- Page zoom: ⌘+ / ⌘− / ⌘0 (View menu), persisted per app across launches.
- Links that leave the wrapped site (clicks and `target=_blank`) now open in the system
  default browser instead of navigating the app window. Sign-in flows stay in-app via a
  built-in SSO-host exception list, and `mailto:`-style links are handed to macOS. It's a
  per-app choice: a prompt in the interactive flow, `--external-links/--no-external-links`
  on `create`/`update` (default on; `--open-any-url` apps always browse in-window). (#68)
- `create --no-url` builds a **handler-only app**: no home site — it opens to a quiet
  built-in start page and exists to receive links (URL handling is enabled
  automatically). Convert to a site app later with `update --url`. `list` shows these
  as `(handler-only)`. (#71)
- Generated apps now get a **fallback icon** when no specific icon can be resolved: a
  solid square in the app's theme/background color with the app's initial as a monogram,
  instead of the generic macOS default icon. The interactive `create` flow notifies you
  when the fallback is applied. (WEBWRAP-FE-001)

### Fixed
- Reader view no longer gets wiped out on client-rendered sites (e.g. figma.com/blog):
  it now renders as its own document, so the article page's still-running framework JS
  can't re-render over it. (#76)
- The offline fallback page was unreadable in dark mode (light background under
  light text).
- The offline page's **Try Again** now retries the navigation that actually failed
  (e.g. an incoming link), instead of always reloading the start URL.

## [0.6.0] - 2026-07-14

### Added
- Generated apps now have an in-app **Settings** window (⌘,) to toggle the navigation
  toolbar, the page-load progress bar, and the window background color. Changes apply
  live without relaunch, persist across launches, and **Restore Defaults** reverts to the
  values baked in at create/update time.
- The navigation toolbar now has a **size** (regular or compact). Compact uses macOS's
  shorter unified-compact bar with smaller icons. Set it with `--toolbar-size` on
  `create`/`update`, or live in the Settings window. Defaults to regular.
- `--user-agent` on `create`/`update` (and a selector in the in-app Settings) sets the
  browser identity: `safari`, `chrome`, `edge`, or a custom UA string. `update
  --no-user-agent` resets to the default. (#60)
- **Home** action (View → Home, ⌘⇧H, and a toolbar button) that returns to the app's
  start page — a one-click escape from dead-end pages like "you have been signed
  out" screens. (#64)

### Changed
- Generated apps now identify as Safari by default (WKWebView's stock user agent lacks
  the `Safari/…` token), fixing "this browser is no longer supported" pages. (#60)

## [0.5.0] - 2026-06-25

### Added
- `create --background-color <hex>` overrides the window background color derived from
  the site manifest.

### Changed
- `update` can now change the window background color: `--background-color <hex>` sets it
  and `--no-background-color` clears it. When `--url` changes and neither flag is given,
  the color follows the new site's manifest (previously the old color was kept).

## [0.4.0] - 2026-06-25

### Added
- Optional navigation toolbar with back/forward/reload buttons. Opt in with
  `--toolbar` on `create` (off by default to keep the chromeless look); `update`
  accepts `--toolbar`/`--no-toolbar` to toggle it on an existing app. The back and
  forward buttons enable/disable with the page history.
- Optional page-load progress line: a thin accent-colored bar along the top edge that
  tracks load progress and fades out when done. Opt in with `--progress-bar` on `create`
  (off by default); `update` accepts `--progress-bar`/`--no-progress-bar`.
- **Copy Current URL** (Edit menu, ⌘⇧C) copies the current page's address — handy
  since the window has no address bar. Disabled when no page is loaded.
- `create` now reads the site's web app manifest for smart defaults: the app name
  is suggested from `short_name`/`name` (interactive flow), and the window is painted
  with the manifest's `background_color` (falling back to `theme_color`) to avoid a
  white first-paint flash. Both are still overridable, and the manifest fetch is
  shared with icon resolution (no extra request).
- When a page fails to load (offline, host unreachable, timeout), generated apps now
  show a clean branded fallback with a **Try Again** button instead of WebKit's generic
  error page. The message adapts to the failure, and the page picks up the manifest
  background color when set.
- `--handle-urls` lets an app open URLs it's launched with (e.g. routed from Choosy),
  registering as an http/https handler. Off by default; only same-site URLs are
  accepted unless `--open-any-url` is set. Available on `create` and `update`.
- Interactive `create` and `update` now prompt for **all** options (window size, toolbar,
  URL handling, background, icon, signing), each shown as a numbered `[Step n/8]` with a
  short help line and pre-filled from any flags you pass or, on update, from the app's
  current settings. Type `q` to cancel at any step. Scripts are unaffected: piped input
  never prompts and `create --url … --name …` stays non-interactive.

### Changed
- The View menu's **Back** and **Forward** items now disable when there's no history
  to go to, matching the navigation toolbar buttons.
- `webwrap update <app>` with no option flags on a terminal now opens the interactive
  editor (previously it silently refreshed the engine); pass a flag or `--force` for the
  direct path.

## [0.3.0] - 2026-06-24

### Added
- `webwrap update <path>` updates a previously created app in place: it refreshes
  the embedded engine (so apps built by an older webwrap get the latest fixes) and
  can optionally change the URL, name, window size, or icon. The app's login session
  is preserved, since the bundle identifier it's keyed to is kept stable. Refuses
  non-webwrap bundles and confirms before changing anything (skip with `--force`).
- Generated apps now have a standard macOS menu bar: an app menu with **Quit** and
  an **About** panel showing the wrapped URL and the webwrap version that created
  the app, plus a View menu (Reload, Back, Forward) and a Window menu.

### Fixed
- Clipboard shortcuts (⌘C/⌘V/⌘X/⌘A) now work inside generated apps. They previously
  did nothing because the app shipped without a menu bar, so the editing actions had
  nowhere to dispatch; the new Edit menu wires them into the responder chain.

## [0.2.0] - 2026-06-23

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

[Unreleased]: https://github.com/yepzdk/webwrap/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/yepzdk/webwrap/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/yepzdk/webwrap/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/yepzdk/webwrap/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/yepzdk/webwrap/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/yepzdk/webwrap/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/yepzdk/webwrap/releases/tag/v0.1.0
