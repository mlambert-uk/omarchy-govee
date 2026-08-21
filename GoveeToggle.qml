import QtQuick
import qs.Commons
import qs.Ui

// A small toggle switch with animated knob.
// Emits toggled() when clicked. Bind `checked` to your state.
Rectangle {
  id: root

  property bool checked: false
  property color fg: "#ffffff"

  signal toggled()

  width: Style.space(32)
  height: Style.space(18)
  radius: height / 2
  color: checked ? Color.accent : Qt.darker(fg, 2.5)

  Behavior on color { ColorAnimation { duration: 150 } }

  Rectangle {
    width: Style.space(14)
    height: Style.space(14)
    radius: width / 2
    color: "#ffffff"
    anchors.verticalCenter: parent.verticalCenter
    x: root.checked ? parent.width - width - Style.space(2) : Style.space(2)
    Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.InOutQuad } }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    enabled: root.enabled
    onClicked: root.toggled()
  }
}
