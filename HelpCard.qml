import QtQuick
import qs.Commons

// Key reference shown over the frozen frame with "?" or F1.
Rectangle {
  id: card

  readonly property var sections: [
    { title: "Zoom", rows: [
      ["Scroll  ·  ↑ ↓", "Zoom in / out"],
      ["Move pointer", "Pan"],
      ["Left click", "Freeze view and draw"],
      ["Right click  ·  Esc", "Exit"]
    ] },
    { title: "Draw", rows: [
      ["P  H  L  A  R  O  T", "Pen, highlighter, line, arrow, rect, ellipse, text"],
      ["1 – 6", "Red, green, blue, yellow, orange, pink"],
      ["Shift + drag", "Straight / 45°, square, circle"],
      ["Ctrl + scroll  ·  [ ]", "Pen width"],
      ["Ctrl + Z  ·  Backspace", "Undo"],
      ["C", "Clear"],
      ["W  ·  K", "Whiteboard / blackboard"],
      ["Right click", "Back to zoom"]
    ] },
    { title: "Share", rows: [
      ["Ctrl + C", "Copy this monitor to the clipboard"],
      ["Ctrl + S", "Save to Pictures (and copy)"]
    ] }
  ]

  width: column.implicitWidth + Style.space(48)
  height: column.implicitHeight + Style.space(40)
  radius: Style.cornerRadius > 0 ? Style.space(14) : 0
  color: Qt.rgba(0.07, 0.07, 0.09, 0.92)
  border.width: 1
  border.color: Qt.rgba(1, 1, 1, 0.14)

  Column {
    id: column
    anchors.centerIn: parent
    spacing: Style.space(14)

    Text {
      text: "Zoomarchy"
      color: "white"
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Repeater {
      model: card.sections

      Column {
        required property var modelData
        spacing: Style.space(5)

        Text {
          text: modelData.title.toUpperCase()
          color: Qt.rgba(1, 1, 1, 0.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.5
        }

        Repeater {
          model: modelData.rows

          Row {
            required property var modelData
            spacing: Style.space(16)

            Text {
              width: Style.space(190)
              text: modelData[0]
              color: "white"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              text: modelData[1]
              color: Qt.rgba(1, 1, 1, 0.78)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }
        }
      }
    }
  }
}
