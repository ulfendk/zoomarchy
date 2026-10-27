import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "Config.js" as Config
import "Strokes.js" as Strokes
import "ZoomMath.js" as ZoomMath

// One monitor's overlay: the frozen frame, its zoom transform and the
// annotations drawn on it. Annotations live in image coordinates inside the
// scaled `content` item, so they stay put on the picture while zooming.
PanelWindow {
  id: win

  required property var modelData
  property var ctl: null

  readonly property string screenName: modelData ? modelData.name : ""
  readonly property bool isActive: ctl && ctl.activeScreen === screenName
  readonly property bool sessionOn: ctl && ctl.mode !== "off"
  readonly property bool drawing: ctl && ctl.mode === "draw"
  readonly property var settings: ctl ? ctl.settings : Config.defaults()

  // View state. `zoom` animates; the anchor is the screen point the zoom is
  // centred on (see ZoomMath.js).
  property real zoom: 1
  property bool animateZoom: false
  property real anchorX: width / 2
  property real anchorY: height / 2
  property real mouseX: width / 2
  property real mouseY: height / 2
  property bool mouseInside: false

  // Drawing state.
  property var points: []
  property var liveStroke: null
  property bool shiftHeld: false
  property bool editingText: false
  property real textX: 0
  property real textY: 0
  property real textSize: 24
  // "" | "white" | "black"
  property string board: ""
  property bool hintVisible: true

  screen: modelData
  visible: ctl && (ctl.capturing || sessionOn)
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "zoomarchy"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: sessionOn && isActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  // Input-less while capturing, so a stray click cannot land on a window
  // that is not drawn yet.
  mask: sessionOn ? null : noInput

  Region { id: noInput }

  ListModel { id: strokes }

  Connections {
    target: win.ctl
    function onSessionStarting(mode) { win.reset(mode) }
    function onSessionEnded() { win.commitText() }
    function onModeChanged() {
      if (!win.ctl) return
      if (win.ctl.mode === "off") {
        strokes.clear()
        win.liveStroke = null
        win.points = []
        win.editingText = false
        return
      }
      if (win.isActive) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      win.showHint()
      if (win.ctl.mode === "zoom") win.commitText()
    }
    function onToolChanged() { win.showHint() }
    function onColorIndexChanged() { win.showHint() }
  }

  onIsActiveChanged: if (isActive && sessionOn) Qt.callLater(function() { keyCatcher.forceActiveFocus() })

  function reset(mode) {
    animateZoom = false
    zoom = 1
    board = ""
    editingText = false
    strokes.clear()
    liveStroke = null
    points = []
    var localX = ctl.cursorX - modelData.x
    var localY = ctl.cursorY - modelData.y
    if (isActive) {
      mouseX = localX
      mouseY = localY
      anchorX = localX
      anchorY = localY
    } else {
      anchorX = width / 2
      anchorY = height / 2
    }
    if (isActive && mode === "zoom") zoomIntro.restart()
  }

  // Start at 1x and grow into the default zoom once the frame is visible.
  Timer {
    id: zoomIntro
    interval: 16
    repeat: true
    onTriggered: {
      if (win.ctl.capturing) return
      stop()
      win.animateZoom = win.settings.animateZoom
      win.zoom = ZoomMath.clampZoom(win.settings.zoomDefault)
    }
  }

  function stepZoom(steps) {
    animateZoom = settings.animateZoom
    zoom = ZoomMath.stepZoom(zoom, steps, settings.zoomStep)
  }

  function toImage(sx, sy) {
    return ZoomMath.toImagePoint(sx, sy, anchorX, anchorY, zoom)
  }

  function showHint() {
    hintVisible = true
    hintTimer.restart()
  }

  Timer {
    id: hintTimer
    interval: 2600
    onTriggered: win.hintVisible = false
  }

  // ------------------------------------------------------------ strokes

  function beginStroke(sx, sy) {
    var p = toImage(sx, sy)
    if (ctl.tool === "text") {
      commitText()
      textX = p.x
      textY = p.y
      textSize = (ctl.penWidth * 4 + 14) / zoom
      textInput.text = ""
      editingText = true
      Qt.callLater(function() { textInput.forceActiveFocus() })
      return
    }
    commitText()
    points = [p]
    updateLiveStroke()
  }

  function extendStroke(sx, sy) {
    if (points.length === 0) return
    var p = toImage(sx, sy)
    var freehand = ctl.tool === "pen" || ctl.tool === "highlighter"
    var next = points.slice()
    if (freehand) {
      if (!Strokes.appendPoint(next, p, 0.75 / zoom)) return
    } else {
      next = [next[0], p]
    }
    points = next
    updateLiveStroke()
  }

  function updateLiveStroke() {
    liveStroke = Strokes.makeStroke(ctl.tool, points, ctl.penColor, ctl.penWidth / zoom, shiftHeld)
  }

  function endStroke() {
    if (points.length === 0) return
    updateLiveStroke()
    if (!Strokes.isEmpty(liveStroke)) strokes.append({ json: JSON.stringify(liveStroke) })
    liveStroke = null
    points = []
  }

  function commitText() {
    if (!editingText) return
    editingText = false
    var stroke = Strokes.makeText(textX, textY, textInput.text, ctl.penColor, textSize)
    if (!Strokes.isEmpty(stroke)) strokes.append({ json: JSON.stringify(stroke) })
    textInput.text = ""
    keyCatcher.forceActiveFocus()
  }

  function undo() {
    if (editingText) {
      editingText = false
      textInput.text = ""
      keyCatcher.forceActiveFocus()
    } else if (strokes.count > 0) {
      strokes.remove(strokes.count - 1)
    }
  }

  function clearAll() {
    editingText = false
    strokes.clear()
  }

  function toggleBoard(kind) {
    board = board === kind ? "" : kind
  }

  // Right click steps back: drawing returns to the zoom it came from, a plain
  // zoom (or an unzoomed drawing) ends the session.
  function back() {
    if (drawing && zoom > 1.001) ctl.mode = "zoom"
    else ctl.stop()
  }

  // ------------------------------------------------------------ export

  readonly property string pictureDir: Quickshell.env("OMARCHY_SCREENSHOT_DIR")
    || Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")

  function timestamp() {
    return Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss")
  }

  // Grabs the frame plus annotations (not the hint, help or cursor ring),
  // then copies or saves it. The grab already renders at the window's device
  // pixel ratio, so it comes out at the monitor's native resolution.
  function exportImage(save) {
    commitText()
    var path = save
      ? pictureDir + "/zoomarchy-" + timestamp() + ".png"
      : ctl.runtimeDir + "/zoomarchy-copy.png"
    stage.grabToImage(function(result) {
      // Detached: wl-copy keeps serving the clipboard after its parent exits,
      // and a Process would take it down on exit.
      if (save) {
        result.saveToFile(path + ".part.png")
        Quickshell.execDetached(["bash", "-c",
          "mkdir -p \"$(dirname \"$1\")\" && mv \"$2\" \"$1\" && wl-copy --type image/png < \"$1\" && notify-send -a Zoomarchy 'Saved annotated screenshot' \"$1\"",
          "zoomarchy-save", path, path + ".part.png"])
      } else {
        result.saveToFile(path)
        Quickshell.execDetached(["bash", "-c",
          "wl-copy --type image/png < \"$1\" && notify-send -a Zoomarchy -t 1500 'Copied to clipboard'",
          "zoomarchy-copy", path])
      }
    })
  }


  // ------------------------------------------------------------ scene

  Item {
    id: stage
    anchors.fill: parent
    clip: true
    // Transparent until the session is live, so the capture never sees it.
    opacity: win.sessionOn ? 1 : 0

    Item {
      id: content
      width: stage.width
      height: stage.height
      transformOrigin: Item.TopLeft
      scale: win.zoom
      x: ZoomMath.offset(win.anchorX, win.zoom)
      y: ZoomMath.offset(win.anchorY, win.zoom)

      Loader {
        id: frameLoader
        anchors.fill: parent
        active: win.ctl && (win.ctl.capturing || win.sessionOn)
        sourceComponent: ScreencopyView {
          captureSource: win.modelData
          live: false
          paintCursor: false
          smooth: win.settings.smoothScaling
          onHasContentChanged: if (hasContent && win.ctl) win.ctl.frameReady(win.screenName)
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: win.board !== ""
        color: win.board === "black" ? "#16181d" : "#fbfbf8"
      }

      Repeater {
        model: strokes
        delegate: StrokeView {
          required property string json
          stroke: JSON.parse(json)
        }
      }

      StrokeView {
        stroke: win.liveStroke
      }

      TextInput {
        id: textInput
        visible: win.editingText
        x: win.textX
        y: win.textY - font.pixelSize / 2
        color: win.ctl ? win.ctl.penColor : "white"
        font.family: Style.font.family
        font.pixelSize: Math.max(1, win.textSize)
        font.bold: true
        cursorVisible: true
        selectByMouse: false
        Keys.onReturnPressed: win.commitText()
        Keys.onEnterPressed: win.commitText()
        Keys.onEscapePressed: win.commitText()
      }
    }
  }

  component StrokeView: Item {
    id: strokeView
    property var stroke: null
    readonly property bool isText: stroke !== null && stroke.kind === "text"

    Repeater {
      model: strokeView.stroke && !strokeView.isText ? strokeView.stroke.polylines : []

      Shape {
        required property var modelData
        preferredRendererType: Shape.CurveRenderer
        opacity: strokeView.stroke ? strokeView.stroke.alpha : 1

        ShapePath {
          strokeColor: strokeView.stroke ? strokeView.stroke.color : "transparent"
          strokeWidth: strokeView.stroke ? strokeView.stroke.width : 1
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap
          joinStyle: ShapePath.RoundJoin

          PathPolyline {
            path: modelData.map(function(p) { return Qt.point(p.x, p.y) })
          }
        }
      }
    }

    Text {
      visible: strokeView.isText
      x: strokeView.isText ? strokeView.stroke.x : 0
      y: strokeView.isText ? strokeView.stroke.y - strokeView.stroke.size / 2 : 0
      text: strokeView.isText ? strokeView.stroke.text : ""
      color: strokeView.isText ? strokeView.stroke.color : "transparent"
      font.family: Style.font.family
      font.pixelSize: strokeView.isText ? Math.max(1, strokeView.stroke.size) : 1
      font.bold: true
      textFormat: Text.PlainText
    }
  }

  // ------------------------------------------------------------ input

  MouseArea {
    id: pointer
    anchors.fill: parent
    enabled: win.sessionOn
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: !win.drawing ? Qt.ArrowCursor
      : (win.ctl && win.ctl.tool === "text" ? Qt.IBeamCursor : Qt.BlankCursor)

    function track(mouse) {
      win.mouseX = mouse.x
      win.mouseY = mouse.y
      win.mouseInside = true
      if (win.ctl && !win.isActive) win.ctl.activeScreen = win.screenName
      if (!win.drawing) {
        win.anchorX = mouse.x
        win.anchorY = mouse.y
      }
    }

    onEntered: win.mouseInside = true
    onExited: win.mouseInside = false

    onPositionChanged: function(mouse) {
      track(mouse)
      win.shiftHeld = (mouse.modifiers & Qt.ShiftModifier) !== 0
      if (pressedButtons & Qt.LeftButton) win.extendStroke(mouse.x, mouse.y)
    }

    onPressed: function(mouse) {
      track(mouse)
      win.shiftHeld = (mouse.modifiers & Qt.ShiftModifier) !== 0
      if (mouse.button === Qt.RightButton) {
        win.back()
      } else if (mouse.button === Qt.LeftButton) {
        // A click while zooming freezes the view here and starts drawing.
        if (!win.drawing) win.ctl.mode = "draw"
        else win.beginStroke(mouse.x, mouse.y)
      }
    }

    onReleased: function(mouse) {
      if (mouse.button === Qt.LeftButton) win.endStroke()
    }

    onWheel: function(wheel) {
      var steps = wheel.angleDelta.y / 120
      if (steps === 0) return
      if (win.drawing && (wheel.modifiers & Qt.ControlModifier)) {
        win.ctl.adjustPen(steps > 0 ? 1 : -1)
        return
      }
      if (!win.drawing) {
        win.anchorX = wheel.x
        win.anchorY = wheel.y
      }
      win.stepZoom(steps)
    }
  }

  // Pen-sized ring in place of the pointer while drawing.
  Rectangle {
    readonly property real size: Math.max(6, win.ctl ? win.ctl.penWidth * (win.ctl.tool === "highlighter" ? 4 : 1) : 6)
    visible: win.drawing && win.mouseInside && win.ctl.tool !== "text"
    x: win.mouseX - size / 2
    y: win.mouseY - size / 2
    width: size
    height: size
    radius: size / 2
    color: "transparent"
    border.width: 1.5
    border.color: win.ctl ? win.ctl.penColor : "white"

    Rectangle {
      anchors.fill: parent
      anchors.margins: -1.5
      radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.45)
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true

    Keys.onPressed: function(event) { win.handleKey(event) }
    Keys.onReleased: function(event) {
      if (event.key === Qt.Key_Shift) {
        win.shiftHeld = false
        if (win.points.length) win.updateLiveStroke()
      }
    }
  }

  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var key = event.key
    event.accepted = true

    if (key === Qt.Key_Escape) { ctl.stop(); return }
    if (key === Qt.Key_Shift) {
      shiftHeld = true
      if (points.length) updateLiveStroke()
      return
    }
    if (key === Qt.Key_Question || key === Qt.Key_F1) { ctl.helpVisible = !ctl.helpVisible; return }
    if (key === Qt.Key_Up || key === Qt.Key_Plus || key === Qt.Key_Equal) { stepZoom(1); return }
    if (key === Qt.Key_Down || key === Qt.Key_Minus) { stepZoom(-1); return }
    if (ctrl && key === Qt.Key_C) { exportImage(false); return }
    if (ctrl && key === Qt.Key_S) { exportImage(true); return }

    if (!drawing) {
      // Any drawing key while zoomed switches to drawing with that choice.
      var text = String(event.text || "").toLowerCase()
      if (Strokes.TOOL_KEYS[text] !== undefined || (text >= "1" && text <= "6")) {
        ctl.mode = "draw"
      } else {
        event.accepted = false
        return
      }
    }

    if (ctrl && key === Qt.Key_Z) { undo(); return }
    if (key === Qt.Key_BracketRight) { ctl.adjustPen(1); return }
    if (key === Qt.Key_BracketLeft) { ctl.adjustPen(-1); return }
    if (key === Qt.Key_Backspace || key === Qt.Key_Delete) { undo(); return }

    var ch = String(event.text || "").toLowerCase()
    if (ch >= "1" && ch <= "6") { ctl.setColor(Number(ch) - 1); return }
    if (ch === "c") { clearAll(); return }
    if (ch === "w") { toggleBoard("white"); return }
    if (ch === "k") { toggleBoard("black"); return }
    if (Strokes.TOOL_KEYS[ch] !== undefined) { ctl.setTool(Strokes.TOOL_KEYS[ch]); return }
    event.accepted = false
  }

  // ------------------------------------------------------------ chrome

  Rectangle {
    id: hint
    anchors.top: parent.top
    anchors.topMargin: Style.space(18)
    anchors.horizontalCenter: parent.horizontalCenter
    visible: win.isActive && win.sessionOn
    opacity: win.hintVisible ? 0.92 : 0
    width: hintRow.implicitWidth + Style.space(28)
    height: hintRow.implicitHeight + Style.space(14)
    radius: height / 2
    color: Qt.rgba(0.07, 0.07, 0.09, 0.82)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)

    Behavior on opacity { NumberAnimation { duration: 220 } }

    Row {
      id: hintRow
      anchors.centerIn: parent
      spacing: Style.space(10)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: win.drawing
        width: Style.space(12)
        height: width
        radius: width / 2
        color: win.ctl ? win.ctl.penColor : "white"
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        color: "white"
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
        text: !win.ctl ? ""
          : (win.drawing
            ? "Draw · " + Strokes.TOOL_LABELS[win.ctl.tool] + " · " + win.ctl.penWidth + " px"
            : "Zoom " + win.zoom.toFixed(1) + "×")
          + "    ? help  ·  Esc exit"
      }
    }
  }

  HelpCard {
    anchors.centerIn: parent
    visible: win.isActive && win.ctl && win.ctl.helpVisible && win.sessionOn
  }

  Behavior on zoom {
    enabled: win.animateZoom
    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
  }
}
