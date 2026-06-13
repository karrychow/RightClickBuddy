# RightClickBuddy

A lightweight macOS Finder extension that lets you build your own right-click menu — add custom actions, "Open With" shortcuts, and quick file operations, all configurable from a clean settings UI.

> Native macOS app built with SwiftUI + FinderSync. No Electron, no background bloat.

## Features

- 🖱️ **Custom right-click actions** — define your own menu items with full create / edit / delete (CRUD) management
- 📂 **Open With** — quickly open selected files with your chosen apps, backed by a fast app cache
- 🧩 **FinderSync extension** — integrates directly into the native Finder context menu
- 🌐 **Localization** — multi-language support built in
- 🚀 **Launch at login** — runs quietly and stays out of your way
- 🪶 **Lightweight** — pure native Swift, minimal footprint

## Requirements

- macOS 13.0 or later

## Build

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`.

```bash
# Generate the Xcode project
xcodegen generate

# Build & run from Xcode, or use the dev scripts
bash scripts/dev-build-debug.sh
```

> Note: set your own `DEVELOPMENT_TEAM` in `project.yml` before signing.

## Architecture

- `App/` — the host SwiftUI app (settings, IPC server, launch-at-login)
- `FinderSync/` — the Finder Sync extension that renders the context menu
- `Shared/` — shared code (IPC protocol, settings, logging, localization)

The host app and the Finder extension communicate over a local IPC channel.

## License

[MIT](./LICENSE) © karry
