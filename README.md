# RightClickBuddy

A lightweight macOS Finder extension that lets you build your own right-click menu — add custom actions, "Open With" shortcuts, and quick file operations, all configurable from a clean settings UI.

> Native macOS app built with SwiftUI + FinderSync. No Electron, no background bloat.

## Features

- 🖱️ **Custom right-click actions** — define your own menu items with full create / edit / delete (CRUD) management
- 📂 **Open With** — quickly open selected files/folders with your chosen apps
- 🆕 **New file / folder** — templates, Office (docx/xlsx/pptx), iWork, from-clipboard, and more
- 🧩 **FinderSync extension** — integrates directly into the native Finder context menu
- 🌐 **Localization** — multi-language support built in
- 🚀 **Launch at login** — runs quietly and stays out of your way
- 🪶 **Lightweight** — pure native Swift, minimal footprint

## Requirements

- macOS 13.0 or later
- [Xcode](https://apps.apple.com/app/xcode/id497799835) (with Command Line Tools)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build & install (from source)

There is no pre-built download — you build it yourself. The recommended path uses **ad-hoc
signing**, which needs **no Apple Developer account or certificate** and runs on your own Mac.

```bash
git clone https://github.com/karrychow/RightClickBuddy.git
cd RightClickBuddy

# Generate the Xcode project from project.yml
xcodegen generate

# Build + ad-hoc sign + install to /Applications + reload the Finder extension + launch
bash scripts/dev-deploy-adhoc.sh
```

`dev-deploy-adhoc.sh` asks for your **sudo password** (to place the app in `/Applications`).
It does not touch your keychain.

### Enable the Finder extension

The first install may need you to switch the extension on:

1. Open **System Settings ▸ General ▸ Login Items & Extensions**
2. Under **Extensions**, find **RightClickBuddy** and make sure its **Finder** extension is enabled
3. Right-click in Finder (Desktop, Downloads, …) — the **RightClickBuddy** menu should appear

Prefer signing with your own Apple Developer certificate instead of ad-hoc? Use
`bash scripts/dev-deploy.sh` (auto-picks your first *Apple Development* identity, or set
`SIGN_IDENTITY="Apple Development: you@example.com"`).

## Usage

Right-click any file, folder, or empty space in a Finder window in a supported location
(by default: Desktop, Downloads, Movies, Music, Pictures — add more under **Settings ▸ Scope**).
You get:

- **New** — text / markdown / json / shell / .env, templates, Office & iWork documents, from clipboard
- **Open With** — open the folder or the selected items in your chosen editor/terminal
- **Copy path / filename**, **Open in Terminal**, and more

Open **Settings** from the menu-bar icon to toggle menu groups, manage templates, choose which
"Open With" apps appear, and set which folders the menu is active in.

## How it works

- `App/` — the host SwiftUI app (settings UI, menu-bar item, launch-at-login, IPC **server**)
- `FinderSync/` — the sandboxed Finder Sync extension that renders the context menu
- `Shared/` — shared code (IPC protocol, settings, logging, localization)

Because the Finder extension is **sandboxed**, it cannot launch other apps or write files in
arbitrary locations itself. It delegates those operations to the non-sandboxed host app over a
**local TCP channel on a fixed loopback port** (`127.0.0.1:52847`, see `Shared/IPCProtocol.swift`).
If the host app isn't running when an action needs it, the extension auto-launches it and retries.

Settings flow the same way: the host app stores them in a normal file
(`~/Library/Application Support/RightClickBuddy/settings.json`) and the extension fetches them over
the same IPC channel. Nothing depends on an App Group container, which is why an **ad-hoc-signed
build has full functionality** (including persistent settings and custom scope folders) with no
Apple Developer account.

## Troubleshooting

- **"Main app is not running"** — should not happen anymore (the extension auto-launches the host
  app). If you ever see it, open **RightClickBuddy** once from `/Applications`.
- **Menu doesn't appear** — enable the extension (see *Enable the Finder extension* above), then
  open Settings and click **Reload Finder Extension** (or run `bash scripts/dev-reload-findersync.sh`).
  Re-enabling in System Settings is sometimes needed after re-signing with a different identity.
- **A custom scope folder shows the app's icon** — this is macOS marking folders the extension
  watches (system folders like Downloads are exempt). The folder itself isn't modified; remove it
  from **Settings ▸ Scope** to revert.
- **Rebuilding after code changes** — just re-run `bash scripts/dev-deploy-adhoc.sh`.

## Scripts

| Script | What it does |
| --- | --- |
| `scripts/dev-deploy-adhoc.sh` | Build → ad-hoc sign → install → reload → launch (**recommended**) |
| `scripts/dev-deploy.sh` | Same, but signs with your Apple Development certificate |
| `scripts/dev-build-debug.sh` | Build only (unsigned) |
| `scripts/dev-reload-findersync.sh` | Re-register the extension + restart Finder |
| `scripts/dev-reset-container.sh` | Reset the App Group container (needs Full Disk Access) |

## License

[MIT](./LICENSE) © karry
