import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "GoveeApi.js" as Api

Item {
  id: root

  // Properties fed directly from the ListModel.
  property bool isOn: false
  property int deviceBrightness: 100
  property bool showBrightness: false
  property bool showColor: false
  property bool showColorTemp: false
  property bool showScenes: false
  property int colorRgb: 16711680
  property int colorTempK: 4000
  property int colorTempMin: 2000
  property int colorTempMax: 9000
  property string name: ""
  property string skuLabel: ""
  property var bar: null
  property var sceneModel: null
  property int sceneActive: -1

  // Expanded state for inline controls
  property bool colorExpanded: false
  property bool scenesExpanded: false

  signal togglePower()
  signal setBrightness(int value)
  signal setColor(int rgbInt)
  signal setColorTemp(int kelvin)
  signal setScene(int sceneValue)
  signal openScenes()

  readonly property color fg: bar ? bar.foreground : "#ffffff"
  readonly property string fontFam: bar ? bar.fontFamily : ""
  readonly property color currentColorDisplay: {
    var c = Api.intToRgb(colorRgb)
    return Qt.rgba(c.r / 255, c.g / 255, c.b / 255, 1)
  }

  implicitHeight: cardColumn.implicitHeight + Style.space(16)

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(12)
    radius: Style.cornerRadius
    color: root.fg
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
        text: root.name
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
          onClicked: root.togglePower()
        }
      }
    }

    // ── SKU + control buttons row ──
    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        text: root.skuLabel
        color: Qt.darker(root.fg, 1.6)
        font.family: root.fontFam
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }

      Item { width: Style.space(4); height: 1 }

      // Color swatch button
      Rectangle {
        visible: root.showColor
        width: Style.space(16)
        height: Style.space(16)
        radius: Style.space(3)
        color: root.currentColorDisplay
        border.width: 1
        border.color: Qt.darker(root.fg, 2.0)
        anchors.verticalCenter: parent.verticalCenter

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: root.isOn ? Qt.PointingHandCursor : Qt.ArrowCursor
          enabled: root.isOn
          onClicked: {
            root.colorExpanded = !root.colorExpanded
            if (root.colorExpanded) root.scenesExpanded = false
          }
        }
      }

      // Color temp icon button
      Rectangle {
        visible: root.showColorTemp && !root.showColor
        width: tempLabel.implicitWidth + Style.space(12)
        height: Style.space(20)
        radius: Style.space(3)
        color: root.colorExpanded ? Color.accent : (colorTempArea.containsMouse && root.isOn ? Style.hoverFillFor(root.fg, Color.accent) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08))
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: tempLabel
          anchors.centerIn: parent
          text: "Temp"
          color: root.colorExpanded ? "#ffffff" : Qt.darker(root.fg, 1.2)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: colorTempArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: root.isOn ? Qt.PointingHandCursor : Qt.ArrowCursor
          enabled: root.isOn
          onClicked: {
            root.colorExpanded = !root.colorExpanded
            if (root.colorExpanded) root.scenesExpanded = false
          }
        }
      }

      // Scenes button
      Rectangle {
        visible: root.showScenes
        width: scenesLabel.implicitWidth + Style.space(12)
        height: Style.space(20)
        radius: Style.space(3)
        color: root.scenesExpanded ? Color.accent : (scenesArea.containsMouse && root.isOn ? Style.hoverFillFor(root.fg, Color.accent) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08))
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: scenesLabel
          anchors.centerIn: parent
          text: "Scenes"
          color: root.scenesExpanded ? "#ffffff" : Qt.darker(root.fg, 1.2)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: scenesArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: root.isOn ? Qt.PointingHandCursor : Qt.ArrowCursor
          enabled: root.isOn
          onClicked: {
            root.scenesExpanded = !root.scenesExpanded
            if (root.scenesExpanded) root.colorExpanded = false
          }
        }
      }
    }

    // ── Brightness slider ──
    Row {
      visible: root.showBrightness
      width: parent.width
      spacing: Style.space(10)

      Text {
        text: "\u{F0E4E}"
        color: Qt.darker(root.fg, 1.5)
        font.family: root.fontFam
        font.pixelSize: Style.font.bodySmall
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        id: sliderContainer
        width: parent.width - Style.space(80)
        height: Style.space(20)
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(4)
          radius: height / 2
          color: Qt.darker(root.fg, 2.5)

          Rectangle {
            width: parent.width * (root.deviceBrightness / 100)
            height: parent.height
            radius: parent.radius
            color: root.isOn ? Color.accent : Qt.darker(root.fg, 1.5)
            Behavior on width { NumberAnimation { duration: 80 } }
            Behavior on color { ColorAnimation { duration: 150 } }
          }
        }

        Rectangle {
          id: sliderKnob
          width: Style.space(14)
          height: Style.space(14)
          radius: width / 2
          color: root.isOn ? Color.accent : Qt.darker(root.fg, 1.5)
          border.width: 2
          border.color: "#ffffff"
          anchors.verticalCenter: parent.verticalCenter
          x: (sliderContainer.width - width) * (root.deviceBrightness / 100)
          Behavior on x { enabled: !sliderMouse.pressed; NumberAnimation { duration: 80 } }
          Behavior on color { ColorAnimation { duration: 150 } }
        }

        MouseArea {
          id: sliderMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          enabled: root.isOn

          onPressed: function(mouse) { updateBrightness(mouse.x) }
          onPositionChanged: function(mouse) { if (pressed) updateBrightness(mouse.x) }
          onReleased: function(mouse) {
            var value = Math.max(1, Math.min(100, Math.round((mouse.x / sliderContainer.width) * 100)))
            root.setBrightness(value)
          }

          function updateBrightness(mouseX) {
            var value = Math.max(1, Math.min(100, Math.round((mouseX / sliderContainer.width) * 100)))
            sliderKnob.x = (sliderContainer.width - sliderKnob.width) * (value / 100)
          }
        }
      }

      Text {
        text: root.deviceBrightness + "%"
        color: Qt.darker(root.fg, 1.3)
        font.family: root.fontFam
        font.pixelSize: Style.font.bodySmall
        width: Style.space(32)
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // ── Color picker (expandable) ──
    Column {
      visible: root.colorExpanded && root.isOn
      width: parent.width
      spacing: Style.space(8)

      ColorPicker {
        width: parent.width
        bar: root.bar
        currentColor: root.colorRgb
        enabled: root.isOn
        onColorPicked: function(rgbInt) { root.setColor(rgbInt) }
      }

      // Color temperature slider
      Column {
        visible: root.showColorTemp
        width: parent.width
        spacing: Style.space(4)

        Text {
          text: "Color Temperature: " + root.colorTempK + "K"
          color: Qt.darker(root.fg, 1.3)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
        }

        Item {
          id: tempSliderContainer
          width: parent.width
          height: Style.space(20)

          // Gradient track warm to cool
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(8)
            radius: height / 2

            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: "#FF8A2B" }  // warm 2000K
              GradientStop { position: 0.3; color: "#FFC58F" }  // 4000K
              GradientStop { position: 0.5; color: "#FFFFFF" }  // 5500K
              GradientStop { position: 0.7; color: "#CCDCFF" }  // 7000K
              GradientStop { position: 1.0; color: "#9BB8FF" }  // cool 9000K
            }
          }

          // Knob
          Rectangle {
            width: Style.space(14)
            height: Style.space(14)
            radius: width / 2
            color: "#ffffff"
            border.width: 2
            border.color: "#00000044"
            anchors.verticalCenter: parent.verticalCenter
            x: ((root.colorTempK - root.colorTempMin) / (root.colorTempMax - root.colorTempMin)) * (tempSliderContainer.width - width)
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: root.isOn

            onPressed: function(mouse) { updateTemp(mouse.x) }
            onPositionChanged: function(mouse) { if (pressed) updateTemp(mouse.x) }
            onReleased: function(mouse) {
              var ratio = Math.max(0, Math.min(1, mouse.x / tempSliderContainer.width))
              var kelvin = Math.round(root.colorTempMin + ratio * (root.colorTempMax - root.colorTempMin))
              root.setColorTemp(kelvin)
            }

            function updateTemp(mouseX) {
              var ratio = Math.max(0, Math.min(1, mouseX / tempSliderContainer.width))
              root.colorTempK = Math.round(root.colorTempMin + ratio * (root.colorTempMax - root.colorTempMin))
            }
          }
        }
      }
    }

    // ── Scenes list (expandable) ──
    Column {
      visible: root.scenesExpanded && root.isOn && root.sceneModel !== null
      width: parent.width
      spacing: Style.space(6)

      Text {
        text: "Scenes"
        color: Qt.darker(root.fg, 1.3)
        font.family: root.fontFam
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      SceneSelector {
        width: parent.width
        bar: root.bar
        scenes: root.sceneModel
        activeScene: root.sceneActive
        enabled: root.isOn
        onScenePicked: function(sceneValue) { root.setScene(sceneValue) }
      }
    }
  }
}
