import QtQuick
import Quickshell
import Quickshell.Io
import "Config.js" as Config
import "Strokes.js" as Strokes
import "ZoomMath.js" as ZoomMath

// Session controller. One ScreenOverlay window per monitor does the drawing;
// this item owns the mode, the shared drawing tool state, the IPC surface
// (`omarchy-shell zoomarchy <method>`) and live zoom.
//
// A session starts in two steps so the overlay never ends up in its own
// frozen frame: every monitor first maps a fully transparent, input-less
// window that captures its output, and only once all frames have arrived
// (or a short timeout passes) does the mode switch on and the frames show.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  // "off" | "zoom" | "draw"
  property string mode: "off"
  property string pendingMode: ""
  property bool capturing: false
  property string activeScreen: ""
  property real cursorX: 0
  property real cursorY: 0
  property var readyScreens: ({})

  property string tool: "pen"
  property int colorIndex: 0
  property int penWidth: 4
  property bool helpVisible: false

  property real liveFactor: 1

  readonly property var settings: store.values
  readonly property color penColor: Config.COLORS[colorIndex].value
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

  signal sessionStarting(string mode)
  signal sessionEnded()

  SettingsStore {
    id: store
    writesLua: true
  }

  // ------------------------------------------------------------ sessions

  function start(nextMode) {
    if (root.capturing || cursorProc.running) {
      root.pendingMode = nextMode
      return
    }
    root.pendingMode = nextMode
    cursorProc.running = true
  }

  function beginCapture(globalX, globalY) {
    var screens = Quickshell.screens
    var index = ZoomMath.screenIndexAt(screens, globalX, globalY)
    root.cursorX = globalX
    root.cursorY = globalY
    root.activeScreen = index >= 0 ? screens[index].name : (screens.length ? screens[0].name : "")
    root.tool = "pen"
    root.colorIndex = root.settings.penColor
    root.penWidth = root.settings.penWidth
    root.helpVisible = false
    root.readyScreens = ({})
    root.capturing = true
    captureTimeout.restart()
    root.sessionStarting(root.pendingMode)
  }

  function frameReady(screenName) {
    if (!root.capturing) return
    var next = ({})
    for (var k in root.readyScreens) next[k] = true
    next[screenName] = true
    root.readyScreens = next
    if (Object.keys(next).length >= Quickshell.screens.length) finishCapture()
  }

  function finishCapture() {
    if (!root.capturing) return
    captureTimeout.stop()
    root.capturing = false
    root.mode = root.pendingMode || "zoom"
    root.pendingMode = ""
    writeState()
  }

  function stop() {
    captureTimeout.stop()
    root.capturing = false
    root.pendingMode = ""
    if (root.mode === "off") return
    root.mode = "off"
    root.helpVisible = false
    root.sessionEnded()
    writeState()
  }

  // The hotkeys toggle: pressing the same one again leaves, the other one
  // switches mode inside the running session.
  function toggleZoom() {
    if (root.mode === "off") start("zoom")
    else stop()
  }

  function toggleDraw() {
    if (root.mode === "off") start("draw")
    else if (root.mode === "zoom") root.mode = "draw"
    else stop()
  }

  Timer {
    id: captureTimeout
    interval: 700
    onTriggered: root.finishCapture()
  }

  Process {
    id: cursorProc
    command: ["hyprctl", "-j", "cursorpos"]
    stdout: StdioCollector {
      id: cursorOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var pos = { x: 0, y: 0 }
      try { pos = JSON.parse(cursorOut.text) } catch (e) {}
      root.beginCapture(Number(pos.x) || 0, Number(pos.y) || 0)
    }
  }

  // ------------------------------------------------------------ drawing state

  function setTool(name) {
    if (Strokes.TOOLS.indexOf(name) !== -1) root.tool = name
  }

  function setColor(index) {
    if (index >= 0 && index < Config.COLORS.length) root.colorIndex = index
  }

  function adjustPen(delta) {
    root.penWidth = Math.max(1, Math.min(40, root.penWidth + delta))
  }

  // ------------------------------------------------------------ live zoom

  // Hyprland's own cursor zoom does the live magnification. The script reads
  // the current factor first, so Omarchy's SUPER+CTRL+Z zoom and ours stay in
  // step instead of fighting.
  readonly property string liveScript: [
    "op=$1 step=$2 def=$3 rigid=$4",
    "cur=$(hyprctl -j getoption cursor:zoom_factor | jq -r '.float // 1')",
    "case $op in",
    "  toggle) next=$(awk -v c=\"$cur\" -v d=\"$def\" 'BEGIN { print (c > 1.001) ? 1 : d }') ;;",
    "  in) next=$(awk -v c=\"$cur\" -v s=\"$step\" 'BEGIN { n = c + s; print (n > 10) ? 10 : n }') ;;",
    "  out) next=$(awk -v c=\"$cur\" -v s=\"$step\" 'BEGIN { n = c - s; print (n < 1.001) ? 1 : n }') ;;",
    "  off) next=1 ;;",
    "  *) echo \"$cur\"; exit 0 ;;",
    "esac",
    "hyprctl eval \"hl.config({ cursor = { zoom_factor = $next, zoom_rigid = $rigid } })\" >/dev/null",
    "echo \"$next\""
  ].join("\n")

  function live(op) {
    if (liveProc.running) return
    liveProc.command = ["bash", "-c", root.liveScript, "zoomarchy-live", op,
      String(root.settings.liveStep), String(root.settings.liveZoom), root.settings.liveRigid ? "true" : "false"]
    liveProc.running = true
  }

  Process {
    id: liveProc
    stdout: StdioCollector {
      id: liveOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var factor = parseFloat(String(liveOut.text || "").trim())
      if (isFinite(factor)) {
        root.liveFactor = factor
        root.writeState()
      }
    }
  }

  // Omarchy's reset bind or a Hyprland reload can drop the zoom behind our
  // back; while it is on, check now and then so the bar does not lie.
  Timer {
    interval: 3000
    repeat: true
    running: root.liveFactor > 1.001
    onTriggered: root.live("get")
  }

  // ------------------------------------------------------------ bar state

  // The bar widget is a separate plugin instance; it follows this file.
  FileView {
    id: stateFile
    path: root.runtimeDir + "/zoomarchy-state.json"
    printErrors: false
  }

  function writeState() {
    stateFile.setText(JSON.stringify({ mode: root.mode, live: root.liveFactor }))
  }

  // ------------------------------------------------------------ entry points

  // Shell summon (`omarchy-shell shell summon regin.zoomarchy '{"mode":"draw"}'`).
  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    var action = String(payload.mode || payload.action || "zoom")
    if (action === "draw") toggleDraw()
    else if (action === "live") live("toggle")
    else if (action === "stop") stop()
    else toggleZoom()
  }

  function close() {
    stop()
  }

  IpcHandler {
    target: "zoomarchy"

    function zoom(): string { root.toggleZoom(); return "ok" }
    function draw(): string { root.toggleDraw(); return "ok" }
    function stop(): string { root.stop(); return "ok" }
    function liveToggle(): string { root.live("toggle"); return "ok" }
    function liveIn(): string { root.live("in"); return "ok" }
    function liveOut(): string { root.live("out"); return "ok" }
    function liveOff(): string { root.live("off"); return "ok" }
    function state(): string { return JSON.stringify({ mode: root.mode, live: root.liveFactor }) }
    function writeBindings(): string { store.save(store.values, true); return "ok" }
    function ping(): string { return "ok" }
  }

  Component.onCompleted: {
    live("get")
    writeState()
  }

  Variants {
    model: Quickshell.screens

    ScreenOverlay {
      ctl: root
    }
  }
}
