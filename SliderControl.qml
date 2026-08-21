import QtQuick
import qs.Commons
import qs.Ui

// A horizontal slider with animated fill and draggable knob.
// Reports value changes on release via sliderMoved(real value).
// The `value` property is the current position (0–1 by default, or 0–maxValue).
Item {
  id: root

  property real value: 0
  property real minValue: 0
  property real maxValue: 1
  property color fg: "#ffffff"
  property color accentColor: Color.accent

  signal sliderMoved(real value)

  height: Style.space(20)

  Rectangle {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: Style.space(4)
    radius: height / 2
    color: Qt.darker(root.fg, 2.5)

    Rectangle {
      width: root.ratio * parent.width
      height: parent.height
      radius: parent.radius
      color: root.enabled ? root.accentColor : Qt.darker(root.fg, 1.5)
      Behavior on width { NumberAnimation { duration: 80 } }
      Behavior on color { ColorAnimation { duration: 150 } }
    }
  }

  Rectangle {
    id: knob
    width: Style.space(14)
    height: Style.space(14)
    radius: width / 2
    color: root.enabled ? root.accentColor : Qt.darker(root.fg, 1.5)
    border.width: 2
    border.color: "#ffffff"
    anchors.verticalCenter: parent.verticalCenter
    x: root.ratio * (root.width - width)
    Behavior on x { enabled: !mouseArea.pressed; NumberAnimation { duration: 80 } }
    Behavior on color { ColorAnimation { duration: 150 } }
  }

  // Internal: current value as 0–1 ratio.
  readonly property real ratio: {
    var range = maxValue - minValue
    if (range <= 0) return 0
    return Math.max(0, Math.min(1, (value - minValue) / range))
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    enabled: root.enabled

    onPressed: function(mouse) { updateFromMouse(mouse.x) }
    onPositionChanged: function(mouse) { if (pressed) updateFromMouse(mouse.x) }
    onReleased: function(mouse) {
      var r = Math.max(0, Math.min(1, mouse.x / root.width))
      var val = Math.round(root.minValue + r * (root.maxValue - root.minValue))
      root.sliderMoved(val)
    }

    function updateFromMouse(mouseX) {
      var r = Math.max(0, Math.min(1, mouseX / root.width))
      knob.x = r * (root.width - knob.width)
    }
  }
}
