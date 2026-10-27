#!/usr/bin/env bash
# Installs Zoomarchy from this checkout into the Omarchy shell.
#
#   ./install.sh            link this checkout as the plugin (edits apply live)
#   ./install.sh --copy     copy it instead, for a checkout you will delete
#
# Then: enables the plugin with its bar icon, adds the hotkey loader to
# ~/.config/hypr/bindings.lua (backed up first) and writes the default
# hotkeys. Everything is undone by ./uninstall.sh.
#
# Alternatively `omarchy plugin add <git-url>` installs the plugin alone; the
# bar widget's settings screen then offers to enable the hotkeys.
#
# Overrides:
#   ZOOMARCHY_SECTION=left|center|right   where the bar icon lands
set -euo pipefail

PLUGIN_ID="regin.zoomarchy"
SECTION="${ZOOMARCHY_SECTION:-right}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
TARGET="$PLUGINS_DIR/$PLUGIN_ID"

say() { printf '==> %s\n' "$*"; }

command -v omarchy >/dev/null || { echo "This needs Omarchy (the omarchy CLI is not on PATH)." >&2; exit 1; }
command -v omarchy-shell >/dev/null || { echo "This needs the Omarchy shell (omarchy-shell)." >&2; exit 1; }
for tool in hyprctl jq wl-copy notify-send; do
  command -v "$tool" >/dev/null || { echo "Missing dependency: $tool" >&2; exit 1; }
done

omarchy plugin validate "$SRC"

mkdir -p "$PLUGINS_DIR"
if [[ -L $TARGET || -e $TARGET ]]; then
  if [[ -L $TARGET && $(readlink -f "$TARGET") == "$SRC" ]]; then
    say "$PLUGIN_ID already links to this checkout"
  else
    echo "$TARGET already exists; remove it first (./uninstall.sh)." >&2
    exit 1
  fi
elif [[ ${1:-} == --copy ]]; then
  say "Copying the plugin to $TARGET"
  mkdir -p "$TARGET"
  tar -C "$SRC" --exclude=.git -cf - . | tar -C "$TARGET" -xf -
else
  say "Linking $TARGET -> $SRC"
  ln -s "$SRC" "$TARGET"
fi

omarchy-shell shell rescanPlugins >/dev/null
# The scan runs in the background; give it a moment before enabling.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  omarchy plugin list 2>/dev/null | grep -q "^$PLUGIN_ID\b" && break
  sleep 0.3
done

say "Enabling $PLUGIN_ID in the $SECTION bar section"
# The shell reloads its plugins while enabling and can miss the IPC reply,
# so trust the resulting state rather than the exit code.
omarchy plugin enable "$PLUGIN_ID" --section "$SECTION" || true
sleep 1
omarchy plugin list 2>/dev/null | grep -qE "^$PLUGIN_ID[[:space:]]+enabled" ||
  { echo "Could not enable $PLUGIN_ID; try: omarchy plugin enable $PLUGIN_ID --section $SECTION" >&2; exit 1; }

say "Loading the hotkeys from ~/.config/hypr/bindings.lua"
bash "$TARGET/bin/zoomarchy-hook" install
# Writes ~/.config/hypr/zoomarchy.lua from the current settings and reloads.
sleep 0.5
omarchy-shell -q zoomarchy writeBindings

say "Done. SUPER+Z zooms, SUPER+SHIFT+Z draws, SUPER+ALT+Z toggles live zoom."
say "Change hotkeys and defaults from the bar icon -> settings."
