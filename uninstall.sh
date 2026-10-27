#!/usr/bin/env bash
# Removes Zoomarchy: the hotkey loader in bindings.lua, the generated hotkey
# file, the bar widget and the plugin itself. Settings in
# ~/.config/zoomarchy are kept unless --purge is given.
set -euo pipefail

PLUGIN_ID="regin.zoomarchy"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
TARGET="$CONFIG_HOME/omarchy/plugins/$PLUGIN_ID"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '==> %s\n' "$*"; }

omarchy-shell -q zoomarchy liveOff || true
omarchy-shell -q zoomarchy stop || true

say "Removing the hotkey loader"
bash "$SRC/bin/zoomarchy-hook" uninstall || true

if omarchy plugin list 2>/dev/null | grep -q "^$PLUGIN_ID\b"; then
  say "Disabling $PLUGIN_ID"
  omarchy plugin disable "$PLUGIN_ID" || true
fi

if [[ -L $TARGET ]]; then
  rm "$TARGET"
elif [[ -d $TARGET ]]; then
  rm -rf "$TARGET"
fi
omarchy-shell -q shell rescanPlugins || true

if [[ ${1:-} == --purge ]]; then
  rm -rf "$CONFIG_HOME/zoomarchy"
  say "Removed settings"
fi
say "Zoomarchy removed"
