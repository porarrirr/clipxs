# ClipXS

English | [日本語](README.ja.md)

A lightweight clipboard-history app for macOS, inspired by the Windows `Win + V` workflow. Press `Option + Command + V` to open recent clipboard items and paste one without leaving the current app.

## Features

- Clipboard history for text, images, and files
- Menu-bar app with no Dock icon
- Keyboard-first history panel
- Up to 100 locally stored items
- Optional launch at login
- English and Japanese interface following the macOS language

## First-time setup

1. Launch `ClipXS.app`.
2. Enable ClipXS under **System Settings > Privacy & Security > Accessibility**. This permission is required to paste the selected item into another app.
3. Optionally enable **Launch at Login** from the menu-bar menu.
4. Copy something, press `Option + Command + V`, and choose an item.

## Controls

| Action | Result |
|---|---|
| `Option + Command + V` | Open or close history |
| `↑` / `↓` | Move through items |
| `Return` | Paste the selected item |
| `Esc` | Close the panel |

Clipboard history is stored locally under `~/Library/Application Support/ClipXS/`.

## Build

```bash
git clone https://github.com/porarrirr/clipxs.git
cd clipxs
xcodegen generate
xcodebuild -scheme ClipXS -configuration Release -derivedDataPath build build
```

## License

[MIT License](LICENSE)
