import QtQuick
import qs.Commons
import qs.Ui
import "GoveeApi.js" as Api

// A compact HSV color picker: hue bar on top, saturation-value grid below.
// Emits colorPicked(int rgbInt) on mouse release.
Item {
  id: root

  property var bar: null
  property int currentColor: 16711680  // Initial color as RGB int (red)

  signal colorPicked(int rgbInt)

  readonly property color fg: bar ? bar.foreground : "#ffffff"
  readonly property string fontFam: bar ? bar.fontFamily : ""

  // Internal HSV state
  property real hue: 0          // 0–360
  property real saturation: 1   // 0–1
  property real value: 1        // 0–1

  implicitWidth: parent ? parent.width : Style.space(280)
  implicitHeight: hueBar.height + svGrid.height + Style.space(10)

  // Initialize from currentColor
  onCurrentColorChanged: {
    if (!hueMouseArea.pressed && !svMouseArea.pressed) {
      var rgb = Api.intToRgb(currentColor)
      var hsv = Api.rgbToHsv(rgb.r, rgb.g, rgb.b)
      hue = hsv.h
      saturation = hsv.s
      value = hsv.v
    }
  }

  Component.onCompleted: {
    var rgb = Api.intToRgb(currentColor)
    var hsv = Api.rgbToHsv(rgb.r, rgb.g, rgb.b)
    hue = hsv.h
    saturation = hsv.s
    value = hsv.v
  }

  // ── Hue bar ──
  Item {
    id: hueBar
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(20)

    // Hue gradient rendered as a horizontal spectrum
    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      clip: true

      // Multi-stop hue gradient using a canvas
      Canvas {
        anchors.fill: parent
        onPaint: {
          var ctx = getContext("2d")
          var gradient = ctx.createLinearGradient(0, 0, width, 0)
          gradient.addColorStop(0.0, "#FF0000")
          gradient.addColorStop(0.167, "#FFFF00")
          gradient.addColorStop(0.333, "#00FF00")
          gradient.addColorStop(0.5, "#00FFFF")
          gradient.addColorStop(0.667, "#0000FF")
          gradient.addColorStop(0.833, "#FF00FF")
          gradient.addColorStop(1.0, "#FF0000")
          ctx.fillStyle = gradient
          ctx.fillRect(0, 0, width, height)
        }
      }
    }

    // Hue indicator
    Rectangle {
      width: Style.space(4)
      height: parent.height + Style.space(4)
      radius: Style.space(2)
      color: "#ffffff"
      border.width: 1
      border.color: "#00000044"
      anchors.verticalCenter: parent.verticalCenter
      x: (root.hue / 360) * (hueBar.width - width)
    }

    MouseArea {
      id: hueMouseArea
      anchors.fill: parent
      enabled: root.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      onPressed: function(mouse) { updateHue(mouse.x) }
      onPositionChanged: function(mouse) { if (pressed) updateHue(mouse.x) }
      onReleased: emitColor()

      function updateHue(mouseX) {
        root.hue = Math.max(0, Math.min(360, (mouseX / hueBar.width) * 360))
      }
    }
  }

  // ── Saturation/Value grid ──
  Item {
    id: svGrid
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: hueBar.bottom
    anchors.topMargin: Style.space(6)
    height: Style.space(120)

    // Base hue color fill
    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      color: {
        var rgb = Api.hsvToRgb(root.hue, 1, 1)
        return Qt.rgba(rgb.r / 255, rgb.g / 255, rgb.b / 255, 1)
      }
    }

    // White-to-transparent horizontal gradient (saturation)
    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "#FFFFFFFF" }
        GradientStop { position: 1.0; color: "#00FFFFFF" }
      }
    }

    // Black-to-transparent vertical gradient (value)
    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      gradient: Gradient {
        GradientStop { position: 0.0; color: "#00000000" }
        GradientStop { position: 1.0; color: "#FF000000" }
      }
    }

    // Crosshair indicator
    Rectangle {
      width: Style.space(12)
      height: Style.space(12)
      radius: width / 2
      color: "transparent"
      border.width: 2
      border.color: root.value > 0.5 ? "#000000" : "#ffffff"
      x: root.saturation * (svGrid.width - width)
      y: (1 - root.value) * (svGrid.height - height)
    }

    MouseArea {
      id: svMouseArea
      anchors.fill: parent
      enabled: root.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      onPressed: function(mouse) { updateSV(mouse.x, mouse.y) }
      onPositionChanged: function(mouse) { if (pressed) updateSV(mouse.x, mouse.y) }
      onReleased: emitColor()

      function updateSV(mouseX, mouseY) {
        root.saturation = Math.max(0, Math.min(1, mouseX / svGrid.width))
        root.value = Math.max(0, Math.min(1, 1 - (mouseY / svGrid.height)))
      }
    }
  }

  function emitColor() {
    var rgb = Api.hsvToRgb(root.hue, root.saturation, root.value)
    var rgbInt = Api.rgbToInt(rgb.r, rgb.g, rgb.b)
    root.colorPicked(rgbInt)
  }
}
