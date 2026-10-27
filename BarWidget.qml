import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Config.js" as Config
import "Keys.js" as HotKeys

// Bar icon plus popup. The main view starts zoom, draw and live zoom; the
// settings view edits ~/.config/zoomarchy/settings.json, including the
// global hotkeys, which are checked against every bind Hyprland has before
// they are written to ~/.config/hypr/zoomarchy.lua.
Panel {
  id: root
  moduleName: "regin.zoomarchy"
  ipcTarget: "zoomarchy-panel"

  // "main" | "settings"
  property string view: "main"
  property var draft: Config.defaults()
  property var hyprBinds: []
  property bool bindsLoaded: false
  // Action id whose hotkey is being recorded, or "".
  property string capturing: ""
  property string partialCombo: ""
  property string status: ""
  property bool statusError: false

  property string sessionMode: "off"
  property real liveFactor: 1

  readonly property bool liveOn: liveFactor > 1.001
  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.5)
  readonly property color bad: Commons.Color.urgent

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  SettingsStore {
    id: store
    onSaved: function(ok, message) {
      root.statusError = !ok
      root.status = ok ? "Saved" : message
      if (ok) {
        root.loadBinds()
        statusTimer.restart()
      }
    }
  }

  Timer {
    id: statusTimer
    interval: 2500
    onTriggered: if (!root.statusError) root.status = ""
  }

  // Session and live-zoom state published by the overlay.
  FileView {
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/zoomarchy-state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var state = JSON.parse(text())
        root.sessionMode = String(state.mode || "off")
        root.liveFactor = Number(state.live) || 1
      } catch (e) {}
    }
  }

  // ------------------------------------------------------------ actions

  property string pendingAction: ""

  // The popup closes before the overlay captures, or it would be frozen
  // into the picture.
  function run(action) {
    root.pendingAction = action
    root.close()
    actionTimer.restart()
  }

  Timer {
    id: actionTimer
    interval: 260
    onTriggered: Quickshell.execDetached(["omarchy-shell", "-q", "zoomarchy", root.pendingAction])
  }

  function comboFor(id) {
    return store.values.bindings[id] || ""
  }

  // ------------------------------------------------------------ settings

  function openSettings() {
    root.draft = Config.copy(store.values)
    root.capturing = ""
    root.status = ""
    root.statusError = false
    root.view = "settings"
    store.refreshHookStatus()
    loadBinds()
  }

  function loadBinds() {
    if (!bindsProc.running) bindsProc.running = true
  }

  Process {
    id: bindsProc
    // Plain text on purpose: see HotKeys.parseBindsText.
    command: ["hyprctl", "binds"]
    stdout: StdioCollector {
      id: bindsOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.hyprBinds = HotKeys.parseBindsText(bindsOut.text)
      root.bindsLoaded = true
    }
  }

  function setDraft(key, value) {
    var next = Config.copy(root.draft)
    next[key] = value
    root.draft = next
  }

  function setBinding(id, combo) {
    var next = Config.copy(root.draft)
    next.bindings[id] = combo
    // A new combo has new conflicts; an override never carries over.
    delete next.overrides[id]
    root.draft = next
  }

  function setOverride(id, on) {
    var next = Config.copy(root.draft)
    if (on) next.overrides[id] = true
    else delete next.overrides[id]
    root.draft = next
  }

  function conflictsFor(id) {
    return HotKeys.conflicts(root.draft.bindings[id], root.hyprBinds, Config.BIND_PREFIX)
  }

  readonly property var duplicateIds: HotKeys.duplicates(draft.bindings)

  readonly property bool blocked: {
    if (duplicateIds.length > 0) return true
    for (var i = 0; i < Config.ACTIONS.length; i++) {
      var id = Config.ACTIONS[i].id
      if (!HotKeys.parse(draft.bindings[id]).valid && draft.bindings[id] !== "") return true
      if (conflictsFor(id).length > 0 && !draft.overrides[id]) return true
    }
    return false
  }

  readonly property bool bindingsChanged: JSON.stringify(draft.bindings) !== JSON.stringify(store.values.bindings)
    || JSON.stringify(draft.overrides) !== JSON.stringify(store.values.overrides)

  function save() {
    if (root.blocked) return
    root.status = "Saving…"
    root.statusError = false
    store.save(root.draft, root.bindingsChanged)
  }

  function startCapture(id) {
    root.capturing = id
    root.partialCombo = ""
    Qt.callLater(function() { captureCatcher.forceActiveFocus() })
  }

  function finishCapture(combo) {
    if (root.capturing !== "" && combo !== "") setBinding(root.capturing, combo)
    root.capturing = ""
    root.partialCombo = ""
    keyCatcher.forceActiveFocus()
  }

  // `omarchy-shell zoomarchy-settings open` jumps straight to settings.
  IpcHandler {
    target: "zoomarchy-settings"

    function open(): void {
      if (root.opened) {
        root.openSettings()
      } else {
        // Switching view while the popup maps leaves it blank; switch once
        // it is up.
        root.open()
        settingsTimer.restart()
      }
    }
  }

  Timer {
    id: settingsTimer
    interval: 200
    onTriggered: if (root.opened) root.openSettings()
  }

  onOpenedChanged: {
    if (!opened) {
      root.capturing = ""
      root.view = "main"
    }
  }

  // ------------------------------------------------------------ bar icon

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    fontSize: Style.font.iconLarge
    active: root.liveOn || root.sessionMode !== "off"
    tooltipText: root.liveOn ? "Zoomarchy: live zoom " + root.liveFactor.toFixed(2) + "× (middle-click to stop)" : "Zoomarchy"
    fixedWidth: root.bar && root.bar.vertical ? -1 : Style.space(27)
    fixedHeight: root.bar && root.bar.vertical ? Style.space(26) : -1
    onPressed: function(b) {
      if (b === Qt.MiddleButton || (b === Qt.LeftButton && root.liveOn && !root.opened)) {
        if (root.liveOn) Quickshell.execDetached(["omarchy-shell", "-q", "zoomarchy", "liveOff"])
        else root.toggle()
        return
      }
      root.toggle()
    }
    onWheelMoved: function(delta) {
      Quickshell.execDetached(["omarchy-shell", "-q", "zoomarchy", delta > 0 ? "liveIn" : "liveOut"])
    }
  }

  // ------------------------------------------------------------ popup

  // Keys bound in Hyprland would never reach the recorder; the inhibitor
  // passes them through while a hotkey is being recorded.
  ShortcutInhibitor {
    window: panel
    enabled: root.capturing !== ""
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.view === "settings" ? 440 : 320))
    contentHeight: root.view === "settings"
      ? panel.fittedContentHeight(Style.space(680), Style.space(760))
      : panel.fittedContentHeight(mainView.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.capturing !== ""
      onCloseRequested: {
        if (root.view === "settings") root.view = "main"
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // ---------------------------------------------------------- main view
      Column {
        id: mainView
        visible: root.view === "main"
        width: parent.width
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          title: "Zoomarchy"
          meta: root.liveOn ? "Live zoom " + root.liveFactor.toFixed(2) + "×" : "Zoom and draw on any screen"
          foreground: root.fg
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: ""
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: ""
              tooltipText: "Settings"
              foreground: root.fg
              onClicked: root.openSettings()
            }
          }
        }

        ActionButton { label: "Still zoom"; combo: root.comboFor("zoom"); onClicked: root.run("zoom") }
        ActionButton { label: "Draw on screen"; combo: root.comboFor("draw"); onClicked: root.run("draw") }
        ActionButton {
          label: root.liveOn ? "Stop live zoom" : "Live zoom"
          combo: root.comboFor("liveToggle")
          selected: root.liveOn
          onClicked: Quickshell.execDetached(["omarchy-shell", "-q", "zoomarchy", "liveToggle"])
        }

        Text {
          visible: !store.hookInstalled
          width: parent.width
          wrapMode: Text.WordWrap
          color: root.bad
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          text: "Hotkeys are not active yet. Open settings to enable them."
        }
      }

      // ---------------------------------------------------------- settings
      Item {
        id: settingsView
        visible: root.view === "settings"
        anchors.fill: parent

        Flickable {
          id: flick
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: footer.top
          anchors.bottomMargin: Style.space(8)
          clip: true
          contentWidth: width
          contentHeight: settingsColumn.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          interactive: root.capturing === ""

          Column {
            id: settingsColumn
            width: flick.width
            spacing: Style.space(10)

            Row {
              spacing: Style.space(8)
              PanelActionButton {
                iconText: ""
                tooltipText: "Back"
                foreground: root.fg
                onClicked: root.view = "main"
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Zoomarchy settings"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
            }

            PanelSectionHeader { text: "HOTKEYS"; foreground: root.fg; fontFamily: root.fontFamily }

            Rectangle {
              visible: !store.hookInstalled
              width: parent.width
              height: hookRow.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: "transparent"
              border.width: 1
              border.color: root.bad

              Column {
                id: hookRow
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(6)

                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  text: "Hyprland does not load Zoomarchy's hotkeys yet. Enabling adds a small marked block to ~/.config/hypr/bindings.lua (a backup is made first)."
                }
                Button {
                  text: "Enable hotkeys"
                  foreground: root.fg
                  bordered: true
                  enabled: !store.busy
                  onClicked: store.installHook()
                }
              }
            }

            Repeater {
              model: Config.ACTIONS

              HotkeyRow {
                required property var modelData
                width: settingsColumn.width
                action: modelData
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              text: root.bindsLoaded
                ? "Checked against " + root.hyprBinds.length + " active Hyprland binds. For scroll binds, hold the modifiers and scroll while recording."
                : "Reading Hyprland binds…"
            }

            PanelSectionHeader { text: "STILL ZOOM"; foreground: root.fg; fontFamily: root.fontFamily }

            ChoiceRow {
              label: "Initial zoom"
              options: Config.ZOOM_CHOICES
              value: String(root.draft.zoomDefault)
              onPicked: function(v) { root.setDraft("zoomDefault", Number(v)) }
            }
            ChoiceRow {
              label: "Scroll step"
              options: Config.STEP_CHOICES
              value: String(root.draft.zoomStep)
              onPicked: function(v) { root.setDraft("zoomStep", Number(v)) }
            }
            SwitchRow {
              label: "Animate zoom"
              checked: root.draft.animateZoom
              onToggled: root.setDraft("animateZoom", !root.draft.animateZoom)
            }
            SwitchRow {
              label: "Smooth scaling"
              detail: "Off shows exact, blocky pixels"
              checked: root.draft.smoothScaling
              onToggled: root.setDraft("smoothScaling", !root.draft.smoothScaling)
            }

            PanelSectionHeader { text: "DRAWING"; foreground: root.fg; fontFamily: root.fontFamily }

            NumberField {
              width: parent.width
              label: "Pen width"
              value: root.draft.penWidth
              from: 1
              to: 40
              foreground: root.fg
              fontFamily: root.fontFamily
              onModified: function(v) { root.setDraft("penWidth", v) }
            }

            Item {
              width: parent.width
              height: swatches.implicitHeight

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Pen color"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Row {
                id: swatches
                anchors.right: parent.right
                spacing: Style.space(6)

                Repeater {
                  model: Config.COLORS

                  Rectangle {
                    required property var modelData
                    required property int index
                    width: Style.space(22)
                    height: width
                    radius: width / 2
                    color: modelData.value
                    border.width: root.draft.penColor === index ? 3 : 0
                    border.color: root.fg

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setDraft("penColor", parent.index)
                    }
                  }
                }
              }
            }

            PanelSectionHeader { text: "LIVE ZOOM"; foreground: root.fg; fontFamily: root.fontFamily }

            ChoiceRow {
              label: "Zoom when turned on"
              options: Config.LIVE_ZOOM_CHOICES
              value: String(root.draft.liveZoom)
              onPicked: function(v) { root.setDraft("liveZoom", Number(v)) }
            }
            ChoiceRow {
              label: "Step"
              options: Config.LIVE_STEP_CHOICES
              value: String(root.draft.liveStep)
              onPicked: function(v) { root.setDraft("liveStep", Number(v)) }
            }
            SwitchRow {
              label: "Rigid view"
              detail: "Pan only when the pointer reaches an edge"
              checked: root.draft.liveRigid
              onToggled: root.setDraft("liveRigid", !root.draft.liveRigid)
            }
          }
        }

        Item {
          id: footer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Math.max(saveButton.implicitHeight, statusText.implicitHeight)

          Text {
            id: statusText
            anchors.left: parent.left
            anchors.right: buttons.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            color: root.statusError || root.blocked ? root.bad : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            text: root.status !== "" ? root.status
              : (root.blocked ? "Resolve the hotkey conflicts to save" : "")
          }

          Row {
            id: buttons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Button {
              text: "Defaults"
              foreground: root.fg
              onClicked: {
                var next = Config.defaults()
                root.draft = next
              }
            }
            Button {
              id: saveButton
              text: "Save"
              foreground: root.fg
              bordered: true
              enabled: !root.blocked && !store.busy
              onClicked: root.save()
            }
          }
        }
      }

      // Records the next combo while `capturing` is set. Lives outside the
      // views so it can hold focus whichever view is shown.
      Item {
        id: captureCatcher
        width: 1
        height: 1
        focus: root.capturing !== ""

        Keys.onPressed: function(event) {
          event.accepted = true
          if (HotKeys.isEscape(event.key) && event.modifiers === Qt.NoModifier) {
            root.finishCapture("")
            return
          }
          if (HotKeys.isModifierKey(event.key)) {
            var mods = HotKeys.modsFromQt(event.modifiers)
            root.partialCombo = mods ? HotKeys.format(mods, "…") : ""
            return
          }
          var combo = HotKeys.comboFromQt(event.key, event.modifiers, event.nativeScanCode)
          if (combo !== "") root.finishCapture(combo)
        }
      }

      WheelHandler {
        enabled: root.capturing !== ""
        onWheel: function(event) {
          var combo = HotKeys.comboFromWheel(event.angleDelta.y, event.modifiers)
          if (combo !== "") root.finishCapture(combo)
        }
      }
    }
  }

  // ------------------------------------------------------------ pieces

  component ActionButton: Button {
    property string label: ""
    property string combo: ""
    width: mainView.width
    leftAlign: true
    text: label
    foreground: root.fg
    fontFamily: root.fontFamily

    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      anchors.verticalCenter: parent.verticalCenter
      text: parent.combo
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component HotkeyRow: Column {
    id: row
    property var action: ({})
    readonly property string combo: root.draft.bindings[action.id] || ""
    readonly property bool recording: root.capturing === action.id
    readonly property var clashes: root.conflictsFor(action.id)
    readonly property bool duplicate: root.duplicateIds.indexOf(action.id) !== -1
    readonly property string warning: combo !== "" ? HotKeys.warning(combo) : ""
    readonly property bool overridden: root.draft.overrides[action.id] === true

    spacing: Style.space(4)

    Item {
      width: row.width
      height: comboButton.implicitHeight

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: row.action.label
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Button {
          id: comboButton
          width: Style.space(210)
          bordered: true
          selected: row.recording
          foreground: (row.clashes.length && !row.overridden) || row.duplicate ? root.bad : root.fg
          fontFamily: root.fontFamily
          text: row.recording ? (root.partialCombo || "Press a combo… (Esc cancels)")
            : (row.combo || "Not bound")
          tooltipText: "Click, then press the new combo"
          onClicked: row.recording ? root.finishCapture("") : root.startCapture(row.action.id)
        }
        PanelActionButton {
          iconText: ""
          tooltipText: "Unbind"
          foreground: root.fg
          enabled: row.combo !== ""
          onClicked: root.setBinding(row.action.id, "")
        }
        PanelActionButton {
          iconText: ""
          tooltipText: "Default (" + row.action.defaultCombo + ")"
          foreground: root.fg
          enabled: row.combo !== row.action.defaultCombo
          onClicked: root.setBinding(row.action.id, row.action.defaultCombo)
        }
      }
    }

    Text {
      visible: row.duplicate
      width: row.width
      wrapMode: Text.WordWrap
      color: root.bad
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      text: "Used by another Zoomarchy action"
    }

    Item {
      visible: row.clashes.length > 0
      width: row.width
      height: Math.max(clashText.implicitHeight, overrideSwitch.implicitHeight)

      Text {
        id: clashText
        anchors.left: parent.left
        anchors.right: overrideSwitch.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.WordWrap
        color: row.overridden ? root.dim : root.bad
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        text: (row.overridden ? "Will replace: " : "Already bound to: ") + row.clashes.join(", ")
          + (row.overridden ? "" : ". Switch on to replace it.")
      }

      ToggleSwitch {
        id: overrideSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: row.overridden
        foreground: root.fg
        onToggled: root.setOverride(row.action.id, !row.overridden)
      }
    }

    Text {
      visible: row.warning !== "" && row.clashes.length === 0
      width: row.width
      wrapMode: Text.WordWrap
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      text: row.warning
    }
  }

  component ChoiceRow: Item {
    id: choice
    property string label: ""
    property var options: []
    property string value: ""
    signal picked(string value)

    width: settingsColumn.width
    height: group.implicitHeight

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: choice.label
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    ButtonGroup {
      id: group
      anchors.right: parent.right
      options: choice.options.map(function(o) { return { value: o, label: o + "×" } })
      value: choice.value
      foreground: root.fg
      fontFamily: root.fontFamily
      focusable: false
      onChanged: function(v) { choice.picked(v) }
    }
  }

  component SwitchRow: Item {
    id: switchRow
    property string label: ""
    property string detail: ""
    property bool checked: false
    signal toggled()

    width: settingsColumn.width
    height: Math.max(labels.implicitHeight, toggle.implicitHeight)

    Column {
      id: labels
      anchors.left: parent.left
      anchors.right: toggle.left
      anchors.verticalCenter: parent.verticalCenter

      Text {
        text: switchRow.label
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        visible: switchRow.detail !== ""
        text: switchRow.detail
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    ToggleSwitch {
      id: toggle
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: switchRow.checked
      foreground: root.fg
      onToggled: switchRow.toggled()
    }
  }
}
