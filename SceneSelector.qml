import QtQuick
import qs.Commons
import qs.Ui

// A scrollable grid of scene buttons for a single device.
// Receives a ListModel of { name, value } scene options.
Item {
  id: root

  property var bar: null
  property var scenes: ListModel {}  // Populated by parent with { name, value }
  property int activeScene: -1       // Currently active scene value, or -1
  property bool enabled: true

  signal scenePicked(int sceneValue)

  readonly property color fg: bar ? bar.foreground : "#ffffff"
  readonly property string fontFam: bar ? bar.fontFamily : ""

  implicitHeight: sceneFlow.implicitHeight

  Flow {
    id: sceneFlow
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: root.scenes

      Rectangle {
        required property int index
        required property string name
        required property int value

        width: sceneText.implicitWidth + Style.space(14)
        height: Style.space(24)
        radius: height / 2
        color: {
          if (value === root.activeScene)
            return Color.accent
          if (sceneItemArea.containsMouse && root.enabled)
            return Style.hoverFillFor(root.fg, Color.accent)
          return Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
        }

        Behavior on color { ColorAnimation { duration: 100 } }

        Text {
          id: sceneText
          anchors.centerIn: parent
          text: name
          color: {
            if (value === root.activeScene)
              return "#ffffff"
            return root.fg
          }
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          font.bold: value === root.activeScene
        }

        MouseArea {
          id: sceneItemArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          enabled: root.enabled
          onClicked: root.scenePicked(value)
        }
      }
    }
  }
}
