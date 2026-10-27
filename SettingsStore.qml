import QtQuick
import Quickshell
import Quickshell.Io
import "Config.js" as Config

// Shared settings for the overlay and the bar widget. Both instantiate one;
// the file watch keeps them in sync, so a save in the settings screen applies
// to the next zoom without a reload.
Item {
  id: store
  visible: false

  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  readonly property string path: configHome + "/zoomarchy/settings.json"
  readonly property string luaPath: configHome + "/hypr/zoomarchy.lua"
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string hookScript: pluginDir + "/bin/zoomarchy-hook"

  property var values: Config.defaults()
  property bool loaded: false
  property bool hookInstalled: false
  property bool busy: false

  // ok=false carries Hyprland's config errors or the failing step's stderr.
  signal saved(bool ok, string message)

  FileView {
    id: file
    path: store.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      store.values = Config.merge(text())
      store.loaded = true
    }
    onLoadFailed: {
      store.values = Config.defaults()
      store.loaded = true
    }
  }

  function refreshHookStatus() {
    if (!hookProc.running) {
      hookProc.command = ["bash", store.hookScript, "status"]
      hookProc.running = true
    }
  }

  Process {
    id: hookProc
    onExited: function(exitCode) { store.hookInstalled = exitCode === 0 }
  }

  // Writes settings.json and, with `bindings`, regenerates zoomarchy.lua and
  // reloads Hyprland so new hotkeys take effect at once.
  function save(next, bindings) {
    var merged = Config.merge(next)
    store.values = merged
    var script = [
      "set -e",
      "mkdir -p \"$(dirname \"$1\")\"",
      "printf '%s\\n' \"$2\" > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"",
      "[ \"$5\" = 1 ] || exit 0",
      "mkdir -p \"$(dirname \"$3\")\"",
      "printf '%s' \"$4\" > \"$3.tmp\" && mv \"$3.tmp\" \"$3\"",
      "hyprctl reload >/dev/null",
      "sleep 0.3",
      "hyprctl configerrors | sed '/^[[:space:]]*$/d'"
    ].join("\n")
    saveProc.command = ["bash", "-c", script, "zoomarchy-save", store.path,
      JSON.stringify(merged, null, 2), store.luaPath, Config.luaFile(merged), bindings ? "1" : "0"]
    store.busy = true
    saveProc.running = true
  }

  function installHook() {
    hookInstallProc.command = ["bash", store.hookScript, "install"]
    store.busy = true
    hookInstallProc.running = true
  }

  Process {
    id: saveProc
    stdout: StdioCollector { id: saveOut; waitForEnd: true }
    stderr: StdioCollector { id: saveErr; waitForEnd: true }
    onExited: function(exitCode) {
      store.busy = false
      var errors = String(saveOut.text || "").trim()
      if (exitCode !== 0) store.saved(false, String(saveErr.text || "").trim() || "Could not write the settings")
      else if (errors !== "") store.saved(false, errors)
      else store.saved(true, "")
    }
  }

  Process {
    id: hookInstallProc
    stderr: StdioCollector { id: hookErr; waitForEnd: true }
    onExited: function(exitCode) {
      store.busy = false
      store.refreshHookStatus()
      if (exitCode === 0) store.save(store.values, true)
      else store.saved(false, String(hookErr.text || "").trim() || "Could not update bindings.lua")
    }
  }

  // First run: make sure the generated hotkey file exists, so the loader in
  // bindings.lua has something to load.
  FileView {
    id: luaFile
    path: store.luaPath
    printErrors: false
    property bool checked: false
    onLoadFailed: function(error) {
      if (checked) return
      checked = true
      store.ensureLuaPending = true
    }
    onLoaded: checked = true
  }

  property bool ensureLuaPending: false
  property bool writesLua: false

  onLoadedChanged: maybeEnsureLua()
  onEnsureLuaPendingChanged: maybeEnsureLua()

  function maybeEnsureLua() {
    if (store.writesLua && store.loaded && store.ensureLuaPending) {
      store.ensureLuaPending = false
      store.save(store.values, true)
    }
  }

  Component.onCompleted: refreshHookStatus()
}
