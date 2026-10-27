# Zoomarchy

Presentation zoom and screen annotation for [Omarchy](https://omarchy.org/).
Freeze any monitor and zoom in, draw arrows, boxes and text on it, and switch
Hyprland's live zoom on and off from the bar or a hotkey.

It is a plugin for the Omarchy shell, so it runs inside the existing bar
process, uses the active theme's colors, and adds an icon to the bar.

## Features

- **Still zoom** freezes all monitors and zooms the one under the pointer.
  Scroll or use ↑/↓ to change the zoom (1–16×). The view follows the pointer,
  so every edge can be reached. Each monitor keeps its own zoom, and HiDPI
  screens stay sharp because the frame is captured at native resolution.
- **Draw** on the frozen frame, zoomed or not, on any monitor: pen,
  highlighter, line, arrow, rectangle, ellipse and text, in six colors.
  Annotations are anchored to the picture, so they stay in place while you
  zoom. Also has undo, clear, and a whiteboard and blackboard.
- **Share**: Ctrl+C copies the annotated monitor to the clipboard. Ctrl+S
  saves it to `~/Pictures` (or `$OMARCHY_SCREENSHOT_DIR`).
- **Live zoom** uses Hyprland's built-in cursor zoom, so you can keep working
  while magnified. It works together with Omarchy's own SUPER+CTRL+Z zoom.
- **Bar widget**: click for zoom, draw and live zoom. Scroll on the icon to
  change the live zoom, and middle-click to stop it. The icon is highlighted
  while a zoom is active.
- **Settings screen** (gear icon in the popup) holds the hotkeys and defaults.
  To record a new hotkey, press it. Each one is checked against every bind
  Hyprland has loaded and against the other Zoomarchy actions. A conflict
  blocks saving until you pick another key or choose to replace the
  existing bind.

## Install

### Requirements

- Omarchy with the Quickshell-based Omarchy shell (the `omarchy-shell` command)
- Hyprland with Lua config (`~/.config/hypr/*.lua`)
- `jq`, `wl-clipboard` and `notify-send`. Omarchy ships all three; if one is
  missing, run `omarchy pkg add jq wl-clipboard libnotify`.

### Option A: install script (recommended)

```bash
git clone https://github.com/ulfendk/zoomarchy.git ~/.local/share/zoomarchy
~/.local/share/zoomarchy/install.sh
```

That is all. The magnifier icon appears in the right side of the bar, and
SUPER + Z works right away.

The script:

1. Links the checkout into `~/.config/omarchy/plugins/regin.zoomarchy`.
2. Enables the plugin and puts its icon in the bar. Set
   `ZOOMARCHY_SECTION=left|center|right` to choose where.
3. Backs up `~/.config/hypr/bindings.lua` to `bindings.lua.bak.<timestamp>`,
   then appends a small marked block (`-- zoomarchy:begin` … `-- zoomarchy:end`)
   that loads the generated hotkeys from `~/.config/hypr/zoomarchy.lua`.
4. Writes the default hotkeys and reloads Hyprland.

Keep the clone where it is, because the plugin is linked to it. If you would
rather delete the clone afterwards, install with `./install.sh --copy`.

To update a linked install, pull and restart the shell:

```bash
git -C ~/.local/share/zoomarchy pull && omarchy restart shell
```

### Option B: Omarchy plugin manager

```bash
omarchy plugin add https://github.com/ulfendk/zoomarchy.git --enable
```

Then click the magnifier icon in the bar, open settings (the gear icon) and
press **Enable hotkeys**. This adds the same `bindings.lua` block as the
script does. Update later with `omarchy plugin update regin.zoomarchy`.

### Uninstall

```bash
~/.local/share/zoomarchy/uninstall.sh          # keeps ~/.config/zoomarchy/settings.json
~/.local/share/zoomarchy/uninstall.sh --purge  # removes the settings too
```

This turns off live zoom, removes the `bindings.lua` block (after another
backup) and the generated hotkey file, disables the plugin and removes it.

### Troubleshooting

- **Hotkeys do nothing:** run `hyprctl configerrors` and check that
  `grep zoomarchy ~/.config/hypr/bindings.lua` finds the block. Then save
  once from the settings screen.
- **No bar icon:** check `omarchy plugin list | grep zoomarchy`, then run
  `omarchy restart shell`.

## Default hotkeys

| Keys | Action |
|---|---|
| SUPER + Z | Still zoom (press again to exit) |
| SUPER + SHIFT + Z | Draw (from zoom: freeze and draw) |
| SUPER + ALT + Z | Live zoom on/off |
| SUPER + CTRL + scroll | Live zoom in/out |

All of these can be changed in the settings screen. The commands behind them
can be used from anywhere, for example in the Omarchy menu or your own binds:

```bash
omarchy-shell zoomarchy zoom | draw | stop
omarchy-shell zoomarchy liveToggle | liveIn | liveOut | liveOff
omarchy-shell zoomarchy-settings open
```

## Keys inside the overlay

Press **?** inside the overlay for this list.

| Keys | Action |
|---|---|
| Scroll, ↑ ↓ | Zoom in / out |
| Left click | Freeze the view and start drawing |
| Right click | Drawing → back to zoom, zoom → exit |
| Esc | Exit |
| P H L A R O T | Pen, highlighter, line, arrow, rectangle, ellipse, text |
| 1 – 6 | Red, green, blue, yellow, orange, pink |
| Shift + drag | Straight / 45° lines, squares, circles |
| Ctrl + scroll, [ ] | Pen width |
| Ctrl + Z, Backspace | Undo |
| C | Clear |
| W, K | Whiteboard, blackboard |
| Ctrl + C, Ctrl + S | Copy, save |

## Files

| Path | Contents |
|---|---|
| `~/.config/zoomarchy/settings.json` | Settings (written by the settings screen) |
| `~/.config/hypr/zoomarchy.lua` | Generated hotkeys, loaded from `bindings.lua` |
| `$XDG_RUNTIME_DIR/zoomarchy-state.json` | Live state shared with the bar icon |

## Development

```bash
node tests/run.js                     # zoom math, strokes, hotkey parsing and conflicts
omarchy plugin validate .
omarchy restart shell                 # reload after editing QML (the shell does not watch linked plugins)
qs log --pid "$(pgrep -f 'quickshell -n -p /usr/share/omarchy/shell')" | grep -i zoomarchy
```

| File | Role |
|---|---|
| `Overlay.qml` | Session controller, IPC, live zoom |
| `ScreenOverlay.qml` | One window per monitor: frozen frame, zoom, drawing, export |
| `BarWidget.qml` | Bar icon, popup and settings screen |
| `SettingsStore.qml` | Shared settings file and hotkey file writer |
| `ZoomMath.js`, `Strokes.js`, `Keys.js`, `Config.js` | Pure logic, covered by `tests/` |

## Credits

Zoomarchy is inspired by the kind of presentation tool that
[ZoomIt](https://learn.microsoft.com/sysinternals/downloads/zoomit) made
popular on Windows. It is an independent implementation written from
scratch for Omarchy and Hyprland. It contains no code, artwork, text or
other material from ZoomIt, and it is not affiliated with or endorsed by
Microsoft. ZoomIt and Sysinternals are trademarks of Microsoft Corporation.

## Support

If Zoomarchy is useful to you, you can support its development:

- [GitHub Sponsors](https://github.com/sponsors/ulfendk)
- [Buy Me a Coffee](https://buymeacoffee.com/ulfendk)

## License

[MIT](LICENSE)
