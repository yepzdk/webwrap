# webwrap

Wrap any website into a standalone macOS `.app` — a lightweight, native alternative to Unite or WebCatalog. No Electron, no subscription. One small Swift binary that scaffolds a real `.app` bundle around a `WKWebView` host.

## How it works

`webwrap` is a single binary that runs in two modes:

- **CLI mode** — when you run `webwrap create ...`, it generates an `.app` bundle.
- **Host mode** — the same binary is copied into the generated bundle as its executable. When you launch the app, the bundle's `Info.plist` sets `WEBWRAP_HOST=1` (via `LSEnvironment`), so the binary boots a single WebKit window pointed at the baked-in URL instead of parsing CLI arguments.

Each generated app uses WebKit (the system web engine — same as Safari), persists its own login/cookie session, and remembers its window size and position. Apps identify as Safari by default — so UA-sniffing sites don't mistake them for an outdated browser — and can present as Chrome, Edge, or a custom user agent via `--user-agent`. If a page can't load (you're offline, the host is unreachable, or it times out), the app shows a clean fallback with a **Try Again** button rather than a generic browser error.

## Sessions & login

Generated apps keep you logged in across relaunches, just like a normal browser — cookies and web storage are written to disk in a persistent data store.

On **macOS 14+**, each app gets its *own isolated* session keyed to its bundle identifier, so two webwrap apps can hold two independent logins (e.g. two Microsoft 365 accounts) without interfering. On **macOS 13**, apps share the system default persistent store — logins still persist, they're just not isolated between apps.

## Install

Via the [yepzdk/homebrew-tools](https://github.com/yepzdk/homebrew-tools) tap (downloads a prebuilt universal binary — no Xcode needed):

```sh
brew install yepzdk/tools/webwrap
```

Or grab the tarball directly from [Releases](https://github.com/yepzdk/webwrap/releases) and drop `webwrap` somewhere on your `PATH`.

To build from source instead:

```sh
git clone https://github.com/yepzdk/webwrap.git
cd webwrap
swift build -c release
cp .build/release/webwrap /usr/local/bin/
```

Requires macOS 13 (Ventura) or later. Building from source additionally needs the Xcode command-line tools.

## Usage

```sh
webwrap create --url https://outlook.office.com --name "Outlook"
```

This writes `Outlook.app` to `/Applications`, resolving the best available icon for the site automatically — it checks the web app manifest, `apple-touch-icon`, `<link rel="icon">`, and `/favicon.ico` (in that order), falling back to a favicon service.

From the same web app manifest, `webwrap` also picks up a couple of smart defaults: it suggests the app name from the manifest's `short_name`/`name` (in interactive mode), and paints the window with the manifest's `background_color` (or `theme_color`) so launch doesn't flash white before the page loads. Both are overridable, and reading the manifest costs no extra request — it's shared with icon resolution.

### Interactive mode

Run `webwrap create` with no `--url`/`--name` and it walks you through **every** option as a numbered series of steps, each with a one-line explanation and pre-filled with a sensible default (or with any flag you did pass). Press Enter to accept a default, or type `q` to cancel at any point:

```sh
$ webwrap create
webwrap — create a macOS app from a website
Press Enter to accept the [default]. Type q to cancel.

[Step 1/11] Website URL
  The address the app opens, e.g. https://github.com.
URL: https://outlook.office.com
Resolving icon…

[Step 2/11] App name
  The display name and the .app filename.
Name [Outlook]:

[Step 4/11] Toolbar
  A back/forward/reload/home bar in the title area.
  Off keeps the chromeless look.
Show navigation toolbar? [y/N]:

[Step 5/11] Progress line
  A thin accent line at the top edge that tracks page loads
  and fades out when done.
Show page-load progress line? [y/N]:

… (steps 3, 6–11: window size, URL handling, reader mode, background, browser identity, icon, signing) …

Summary
  Name:        Outlook
  URL:         https://outlook.office.com
  Bundle ID:   dk.yepz.webwrap.outlook
  Icon:        web app manifest
  Size:        1200×800
  Toolbar:     no
  Progress:    no
  Handle URLs: no
  Ext. links:  default browser
  Reader:      manual (⇧⌘R)
  Background:  default
  User agent:  safari (default)
  Signing:     ad-hoc
  Destination: /Applications/Outlook.app

Create this app? [Y/n]:
```

Passing both `--url` and `--name` skips the prompts entirely and builds straight from the flags — handy for scripts. Piped/non-interactive input never prompts.

### Options

| Option | Description | Default |
| --- | --- | --- |
| `-u, --url` | URL the app opens (required, absolute) | — |
| `-n, --name` | Display name of the app (required) | — |
| `-o, --output` | Directory to write the `.app` into | `/Applications` |
| `--bundle-id` | Bundle identifier | `dk.yepz.webwrap.<slug>` |
| `--icon` | Path to a `.png` or `.icns` icon | resolved from site |
| `--width` | Initial window width (points) | `1200` |
| `--height` | Initial window height (points) | `800` |
| `--toolbar` | Show a navigation toolbar (back/forward/reload/home) | off |
| `--toolbar-size` | Navigation toolbar size: `regular` or `compact` (smaller) | `regular` |
| `--progress-bar` | Show a thin page-load progress line at the top of the window | off |
| `--handle-urls` | Register as an http/https handler and open URLs the app is launched with (e.g. from Choosy) | off |
| `--open-any-url` | With `--handle-urls`, also accept off-domain URLs (default: only same-site) | off |
| `--external-links` / `--no-external-links` | Open links that leave the site in the default browser | on |
| `--no-url` | Create a handler-only app: no home site, opens to a built-in start page, exists to receive links (implies `--handle-urls --open-any-url`) | — |
| `--reader` | Open pages in the distraction-free reader view automatically (⇧⌘R toggles it on any page either way) | off |
| `--background-color` | Hex color painted behind the page on launch (e.g. `#1a73e8`); overrides the site manifest's color | manifest |
| `--user-agent` | Browser identity the app reports: `safari`, `chrome`, `edge`, or a full custom UA string. Apps identify as Safari by default, which fixes most "browser not supported" pages | `safari` |
| `--force` | Overwrite an existing `.app` | off |
| `--no-sign` | Skip ad-hoc code signing | off |
| `--sign` | Sign with a Developer ID identity (enables the hardened runtime) | ad-hoc |
| `--notarize` | Notarize and staple with Apple (requires `--sign` + `--notary-profile`) | off |
| `--notary-profile` | `notarytool store-credentials` profile name for `--notarize` | — |

### Examples

```sh
# Custom icon and window size
webwrap create -u https://app.example.com -n "Example" \
  --icon ~/icons/example.png --width 1000 --height 700

# Write somewhere other than /Applications
webwrap create -u https://chat.openai.com -n "ChatGPT" -o ~/Applications --force
```

### Opening the app with a URL

With `--handle-urls`, a generated app registers as an `http`/`https` handler and navigates to URLs it's launched with — so you can route links to it from [Choosy](https://www.choosy.app/), `open -a "GitHub" https://github.com/...`, or anything that opens URLs in a chosen app:

```sh
webwrap create -u https://github.com -n "GitHub" --handle-urls
```

It's **off by default** so apps don't claim `http`/`https` system-wide unless you opt in. By default only **same-site** URLs are accepted (a GitHub app loads `github.com` links and ignores `example.com`); pass `--open-any-url` to let the app navigate to any URL it's handed. Rejected off-domain URLs are simply ignored — the app stays on its current page.

Incoming links are also **cleaned before navigating** (logic ported from [url-cleaner](https://github.com/yepzdk/url-cleaner)): tracking redirects that embed the real destination — newsletter wrappers like TLDR's, Google/Facebook/SafeLinks redirects, Postmark — are unwrapped so the app goes straight to the article without ever contacting the tracking host (which your DNS blocker may be blocking anyway), and tracking parameters (`utm_*`, `fbclid`, …) are stripped. Cleaning runs before the same-site check, so a tracking link wrapping a same-site URL is accepted.

There's also a keyboard path that needs no routing setup at all: **File → Open URL from Clipboard (⇧⌘O)** opens whatever URL is on the clipboard (a bare `example.com/…` works too), subject to the same same-site scoping. Handy for pages you're already viewing in a browser, which Choosy can't intercept: ⌘L ⌘C there, ⇧⌘O here.

#### Handler-only apps

You can go all the way and create an app that is *only* a link receiver — no home site at all:

```sh
webwrap create -n "Reader" --no-url
```

A handler-only app opens to a quiet built-in start page and waits for links; URL handling and off-domain acceptance are enabled automatically (that's the app's whole job), and Home (⌘⇧H) returns to the start page. Give it a URL later with `webwrap update --url …` to convert it into a normal site app.

### Reader mode

Every generated app has a **reader view**: press **⇧⌘R** (View → Toggle Reader View) on an article and the page is swapped for a clean, distraction-free rendering — title, byline, and body, no ads or site chrome. It's powered by [Readability](https://github.com/mozilla/readability), the library behind Firefox's reader view; because extraction runs on the rendered page inside the app's own session, articles behind logins you're signed in to extract correctly. Press ⇧⌘R again to return to the original page. **⌘+ / ⌘− / ⌘0** adjust the page zoom (any page, not just reader view) and persist across launches.

The reader's appearance is adjustable: click the **Aa** button in the top-right corner of a reader page to set font size, serif or sans-serif type, column width, line height, and theme (auto, light, sepia, dark, or black). Changes apply instantly and persist per app; the app's Settings window (⌘,) → Restore Defaults returns the stock design.

Pass `--reader` to make it automatic — every page that looks like an article opens as a reader page (pages that don't, load normally). Combined with a handler-only app, that's a standalone reading app for a browser picker like Choosy:

```sh
webwrap create -n "Reader" --reader --no-url
```

Two practical notes for a reader app: to get full text from sites that paywall logged-out visitors, **log in once inside the app** (⇧⌘R to the original page, sign in — the session persists). And to send an article over from the browser you're reading in (Choosy can't intercept pages you're already viewing): copy the URL and press **⇧⌘O** in the reader.

### Links that leave the site

By default, links you click that go **off-site** (and `target=_blank` popups) open in your **default browser** instead of navigating the app window — so a news link in an Outlook email doesn't strand the app on some article. Sign-in flows are unaffected: common SSO hosts (`login.microsoftonline.com`, `accounts.google.com`, …) and all automatic redirects stay inside the app, so logins land in the app's own session. `mailto:` and other app-scheme links are handed to macOS.

It's a per-app choice: answer the prompt in interactive mode, or pass `--no-external-links` to keep everything in-window. Apps created with `--open-any-url` always browse in-window (they explicitly handle any domain).

## Listing your apps

`webwrap list` shows the wrapped apps installed on your Mac and the URL each points at — handy when Finder can't tell a webwrap app apart from any other:

```sh
$ webwrap list
NAME      URL                          LOCATION
ChatGPT   https://chat.openai.com      ~/Applications
Outlook   https://outlook.office.com   /Applications

2 apps
```

It scans `/Applications` and `~/Applications`, identifying webwrap apps by a marker baked into their `Info.plist` — there's no separate registry to keep in sync. To remove an app, drag it to the Trash like any other.

## Updating an app

`webwrap update` refreshes an existing app in place — most usefully to give an app built by an older webwrap the latest engine (e.g. new menu/keyboard fixes), and optionally to change its settings. **The app's login session is preserved.**

```sh
# Edit every setting interactively, pre-filled with the app's current values
webwrap update "/Applications/Outlook.app"

# Or change settings directly with flags (anything omitted is kept)
webwrap update "/Applications/Outlook.app" --url https://outlook.office365.com --width 1400
```

Run with just the app path on a terminal and `update` walks the same prompts as `create`, each defaulting to the app's current setting — so you can, say, turn the toolbar on without remembering the flag. Pass any option flag (or `--force`) to take the direct, non-interactive path instead.

| Option | Description |
| --- | --- |
| `-u, --url` | New URL |
| `-n, --name` | New display name (renames the `.app`; session still carried over) |
| `--icon` | New `.png`/`.icns` icon (existing icon kept if omitted) |
| `--width`, `--height` | New window size |
| `--toolbar` / `--no-toolbar` | Show or hide the navigation toolbar (current setting kept if omitted) |
| `--toolbar-size` | Navigation toolbar size: `regular` or `compact` (current setting kept if omitted) |
| `--progress-bar` / `--no-progress-bar` | Show or hide the page-load progress line (current setting kept if omitted) |
| `--handle-urls` / `--no-handle-urls` | Turn URL handling on or off (current setting kept if omitted) |
| `--open-any-url` / `--no-open-any-url` | Allow or restrict off-domain URLs (current setting kept if omitted) |
| `--external-links` / `--no-external-links` | Open off-site links in the default browser, or in the window (current setting kept if omitted) |
| `--reader` / `--no-reader` | Open pages in the reader view automatically, or only via ⇧⌘R (current setting kept if omitted) |
| `--background-color` / `--no-background-color` | Set or clear the window background color. If omitted, it follows the new `--url`'s manifest color when the URL changes, otherwise the current setting is kept |
| `--user-agent` / `--no-user-agent` | Set the browser identity (`safari`/`chrome`/`edge` or a custom UA string) or reset it to the Safari default (current setting kept if omitted) |
| `--sign`, `--notarize`, `--notary-profile`, `--no-sign` | Signing, same as `create` |
| `--force` | Skip the confirmation prompt |

The session survives because it's keyed to the app's bundle identifier, which `update` keeps stable even across a URL or name change. `update` refuses any bundle that isn't a webwrap app.

### Settings inside the app

For the presentation-level options you don't need the terminal: every generated app has a **Settings** window (⌘, , or the app menu) to toggle the navigation toolbar (and its size, regular or compact), the page-load progress bar, the window background color, and the browser identity (Safari/Chrome/Edge or a custom user-agent string). Changes apply live — no relaunch — and persist across launches. **Restore Defaults** reverts to the values baked in at create/update time.

These in-app settings are overrides layered on top of the baked-in defaults, so an `update` that changes, say, the background color updates the default the app falls back to. Identity (URL, name, icon) and signing remain `create`/`update`-only.

## Sharing generated apps with other Macs

By default, generated apps are **ad-hoc signed** (`codesign --sign -`), which lets them run on the machine that built them. Apps you send to *other* Macs will trip Gatekeeper on first launch ("can't be opened because Apple cannot check it for malware"). Recipients can either **right-click the app → Open** (confirm once), or strip the quarantine flag with `xattr -dr com.apple.quarantine "/Applications/Whatever.app"`.

To remove that friction entirely, sign with a Developer ID and notarize. This requires a paid Apple Developer account.

### Sign with a Developer ID

```sh
webwrap create -u https://app.example.com -n "Example" \
  --sign "Developer ID Application: Your Name (TEAMID)"
```

`--sign` replaces the ad-hoc signature with your Developer ID identity and enables the hardened runtime. Find your identity string with:

```sh
security find-identity -v -p codesigning
```

A Developer-ID-signed-but-unnotarized app still trips Gatekeeper — notarize it to clear that.

### Notarize and staple

First, store your App Store Connect credentials once as a keychain profile named `webwrap` (you'll need an [App Store Connect API key](https://appstoreconnect.apple.com): a `.p8` file plus its Key ID and Issuer ID):

```sh
xcrun notarytool store-credentials webwrap \
  --key /path/to/AuthKey_XXXXXX.p8 \
  --key-id YOUR_KEY_ID \
  --issuer YOUR_ISSUER_ID
```

Then create with `--notarize`:

```sh
webwrap create -u https://app.example.com -n "Example" \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --notarize --notary-profile webwrap
```

webwrap signs the app, submits it to Apple's notary service (`notarytool submit --wait`), and on success staples the ticket. The result passes Gatekeeper with **no right-click and no `xattr`** on any Mac — verify with `spctl -a -vvv "Example.app"`. Notarization adds a few minutes while Apple processes the submission.

Pass `--no-sign` to skip signing altogether. `--no-sign`/`--sign` are mutually exclusive, and `--notarize` requires both `--sign` and `--notary-profile`.

## License

MIT
