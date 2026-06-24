# webwrap

Wrap any website into a standalone macOS `.app` — a lightweight, native alternative to Unite or WebCatalog. No Electron, no subscription. One small Swift binary that scaffolds a real `.app` bundle around a `WKWebView` host.

## How it works

`webwrap` is a single binary that runs in two modes:

- **CLI mode** — when you run `webwrap create ...`, it generates an `.app` bundle.
- **Host mode** — the same binary is copied into the generated bundle as its executable. When you launch the app, the bundle's `Info.plist` sets `WEBWRAP_HOST=1` (via `LSEnvironment`), so the binary boots a single WebKit window pointed at the baked-in URL instead of parsing CLI arguments.

Each generated app uses WebKit (the system web engine — same as Safari), persists its own login/cookie session, and remembers its window size and position.

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

Run `webwrap create` with no `--url`/`--name` and it prompts you:

```sh
$ webwrap create
URL: https://outlook.office.com
Name [Outlook]:
Resolving icon…

Summary
  Name:        Outlook
  URL:         https://outlook.office.com
  Bundle ID:   dk.yepz.webwrap.outlook
  Icon:        web app manifest
  Destination: /Applications/Outlook.app

Create this app? [Y/n]:
```

It validates the URL (re-prompting if it's not absolute), suggests a name from the site's host, shows where the icon came from, and asks you to confirm before writing anything. Piped or non-interactive input never prompts — pass `--url` and `--name` as flags there.

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
| `--toolbar` | Show a navigation toolbar (back/forward/reload) | off |
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
# Refresh the embedded engine, keep everything else
webwrap update "/Applications/Outlook.app"

# Change settings (anything omitted is kept)
webwrap update "/Applications/Outlook.app" --url https://outlook.office365.com --width 1400
```

| Option | Description |
| --- | --- |
| `-u, --url` | New URL |
| `-n, --name` | New display name (renames the `.app`; session still carried over) |
| `--icon` | New `.png`/`.icns` icon (existing icon kept if omitted) |
| `--width`, `--height` | New window size |
| `--toolbar` / `--no-toolbar` | Show or hide the navigation toolbar (current setting kept if omitted) |
| `--sign`, `--notarize`, `--notary-profile`, `--no-sign` | Signing, same as `create` |
| `--force` | Skip the confirmation prompt |

The session survives because it's keyed to the app's bundle identifier, which `update` keeps stable even across a URL or name change. `update` refuses any bundle that isn't a webwrap app.

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
