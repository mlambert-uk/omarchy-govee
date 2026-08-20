import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "GoveeApi.js" as Api

Item {
  id: root

  property var device: ({})
  property var deviceState: ({})
  property var bar: null

  signal togglePower(string sku, string deviceId, bool currentlyOn)
  signal setBrightness(string sku, string deviceId, int value)

  readonly property bool isOn: deviceState.powerSwitch === 1
  readonly property int brightness: deviceState.brightness !== undefined ? deviceState.brightness : 100
  readonly property bool hasBrightness: Api.hasCapability(device, "devices.capabilities.range", "brightness")
  readonly property string displayName: Api.deviceDisplayName(device)
  readonly property color fg: bar ? bar.foreground : "#ffffff"
  readonly property string fontFam: bar ? bar.fontFamily : ""

  implicitHeight: cardColumn.implicitHeight + Style.space(16)

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(12)
    radius: Style.cornerRadius
    color: root.bar ? root.bar.foreground : "#ffffff"
    opacity: 0.04
  }

  Column {
    id: cardColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(20)
    anchors.rightMargin: Style.space(20)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(10)

    // ── Device name + power toggle row ──
    Row {
      width: parent.width
      spacing: Style.space(10)

      // Power indicator dot
      Rectangle {
        width: Style.space(8)
        height: Style.space(8)
        radius: width / 2
        color: root.isOn ? "#4cdf6b" : Qt.darker(root.fg, 2.0)
        anchors.verticalCenter: parent.verticalCenter
      }

      // Device name
      Text {
        text: root.displayName
        color: root.fg
        font.family: root.fontFam
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: parent.width - powerButton.width - Style.space(26)
        anchors.verticalCenter: parent.verticalCenter
      }

      // Power toggle button
      Rectangle {
        id: powerButton
        width: Style.space(36)
        height: Style.space(22)
        radius: height / 2
        color: root.isOn ? Color.accent : Qt.darker(root.fg, 2.5)
        anchors.verticalCenter: parent.verticalCenter

        Behavior on color { ColorAnimation { duration: 150 } }

        // Toggle knob
        Rectangle {
          width: Style.space(16)
          height: Style.space(16)
          radius: width / 2
          color: "#ffffff"
          anchors.verticalCenter: parent.verticalCenter
          x: root.isOn ? parent.width - width - Style.space(3) : Style.space(3)

          Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.InOutQuad } }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.togglePower(root.device.sku, root.device.device, root.isOn)
        }
      }
    }

    // ── SKU label ──
    Text {
      text: device.sku || ""
      color: Qt.darker(root.fg, 1.6)
      font.family: root.fontFam
      font.pixelSize: Style.font.caption
    }

    // ── Brightness slider ──
    Row {
      visible: root.hasBrightness
      width: parent.width
      spacing: Style.space(10)

      // Sun icon (dim)
      Text {
        text: "\u{F0E4E}"  // nf-md-brightness_5
        color: Qt.darker(root.fg, 1.5)
        font.family: root.fontFam
        font.pixelSize: Style.font.bodySmall
        anchors.verticalCenter: parent.verticalCenter
      }

      // Slider track
      Item {
        id: sliderContainer
        width: parent.width - Style.space(80)
        height: Style.space(20)
        anchors.verticalCenter: parent.verticalCenter

        // Track background
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(4)
          radius: height / 2
          color: Qt.darker(root.fg, 2.5)

          // Filled portion
          Rectangle {
            width: parent.width * (root.brightness / 100)
            height: parent.height
            radius: parent.radius
            color: root.isOn ? Color.accent : Qt.darker(root.fg, 1.5)

            Behavior on width { NumberAnimation { duration: 80 } }
            Behavior on color { ColorAnimation { duration: 150 } }
          }
        }

        // Slider knob
        Rectangle {
          id: sliderKnob
          width: Style.space(14)
          height: Style.space(14)
          radius: width / 2
          color: root.isOn ? Color.accent : Qt.darker(root.fg, 1.5)
          border.width: 2
          border.color: "#ffffff"
          anchors.verticalCenter: parent.verticalCenter
          x: (sliderContainer.width - width) * (root.brightness / 100)

          Behavior on x { enabled: !sliderMouse.pressed; NumberAnimation { duration: 80 } }
          Behavior on color { ColorAnimation { duration: 150 } }
        }

        MouseArea {
          id: sliderMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          enabled: root.isOn

          onPressed: function(mouse) {
            updateBrightness(mouse.x)
          }
          onPositionChanged: function(mouse) {
            if (pressed) updateBrightness(mouse.x)
          }
          onReleased: function(mouse) {
            var value = Math.max(1, Math.min(100, Math.round((mouse.x / sliderContainer.width) * 100)))
            root.setBrightness(root.device.sku, root.device.device, value)
          }

          function updateBrightness(mouseX) {
            // Local visual feedback only; actual API call on release
            var value = Math.max(1, Math.min(100, Math.round((mouseX / sliderContainer.width) * 100)))
            sliderKnob.x = (sliderContainer.width - sliderKnob.width) * (value / 100)
          }
        }
      }

      // Brightness percentage label
      Text {
        text: root.brightness + "%"
        color: Qt.darker(root.fg, 1.3)
        font.family: root.fontFam
        font.pixelSize: Style.font.bodySmall
        width: Style.space(32)
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
