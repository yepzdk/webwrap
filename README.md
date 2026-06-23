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
| `--force` | Overwrite an existing `.app` | off |
| `--no-sign` | Skip ad-hoc code signing | off |

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

## Sharing generated apps with other Macs

Generated apps are **ad-hoc signed** (`codesign --sign -`), which lets them run on the machine that built them. Apps you send to *other* Macs will trip Gatekeeper on first launch ("can't be opened because Apple cannot check it for malware"). Recipients have two easy options:

- **Right-click the app → Open**, then confirm in the dialog (only needed once), or
- Strip the quarantine flag: `xattr -dr com.apple.quarantine "/Applications/Whatever.app"`

This is the same friction as any un-notarized indie app. To remove it entirely you'd need a paid Apple Developer account, a Developer ID certificate, and notarization — not currently built in (see the roadmap in `CLAUDE.md`). Pass `--no-sign` to skip ad-hoc signing altogether.

## License

MIT
