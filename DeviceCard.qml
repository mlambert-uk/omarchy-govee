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
  property bool deviceIsFan: false
  property bool showOscillation: false
  property bool showWorkMode: false
  property bool showMusic: false
  property int fanMaxSpeed: 12
  property bool fanOscillation: false
  property int fanWorkMode: 0
  property int fanModeValue: 0
  property var workModeOptions: null  // { modes: [{name, value, speeds}], maxSpeed }
  property var musicModeOptions: null // [{name, value}] array

  // Expanded state for inline controls
  property bool colorExpanded: false
  property bool scenesExpanded: false
  property bool musicExpanded: false

  // Music mode local state
  property int musicSelectedMode: -1
  property int musicSensitivity: 80
  property bool musicAutoColor: true
  property int musicRgb: 16711680

  // Collapse expanded sections when device turns off
  onIsOnChanged: {
    if (!isOn) {
      colorExpanded = false
      scenesExpanded = false
      musicExpanded = false
    }
  }

  signal togglePower()
  signal setBrightness(int value)
  signal setColor(int rgbInt)
  signal setColorTemp(int kelvin)
  signal setScene(int sceneValue)
  signal setOscillation(bool on)
  signal setWorkMode(int wm, int mv)
  signal setMusicMode(int mode, int sens, bool autoColor, int rgb)
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
      visible: root.isOn
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

      // Music mode button
      Rectangle {
        visible: root.showMusic
        width: musicLabel.implicitWidth + Style.space(12)
        height: Style.space(20)
        radius: Style.space(3)
        color: root.musicExpanded ? Color.accent : (musicArea.containsMouse && root.isOn ? Style.hoverFillFor(root.fg, Color.accent) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08))
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: musicLabel
          anchors.centerIn: parent
          text: "Music"
          color: root.musicExpanded ? "#ffffff" : Qt.darker(root.fg, 1.2)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: musicArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: root.isOn ? Qt.PointingHandCursor : Qt.ArrowCursor
          enabled: root.isOn
          onClicked: {
            root.musicExpanded = !root.musicExpanded
            if (root.musicExpanded) { root.colorExpanded = false; root.scenesExpanded = false }
          }
        }
      }
    }

    // ── Brightness slider ──
    Row {
      visible: root.showBrightness && root.isOn
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

    // ── Fan: Oscillation toggle ──
    Row {
      visible: root.showOscillation && root.isOn
      width: parent.width
      spacing: Style.space(10)

      Text {
        text: "Oscillation"
        color: Qt.darker(root.fg, 1.3)
        font.family: root.fontFam
        font.pixelSize: Style.font.bodySmall
        anchors.verticalCenter: parent.verticalCenter
      }

      Item { width: parent.width - oscLabel.implicitWidth - oscToggle.width - Style.space(20); height: 1 }

      Text {
        id: oscLabel
        text: root.fanOscillation ? "On" : "Off"
        color: Qt.darker(root.fg, 1.4)
        font.family: root.fontFam
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }

      Rectangle {
        id: oscToggle
        width: Style.space(32)
        height: Style.space(18)
        radius: height / 2
        color: root.fanOscillation ? Color.accent : Qt.darker(root.fg, 2.5)
        anchors.verticalCenter: parent.verticalCenter

        Behavior on color { ColorAnimation { duration: 150 } }

        Rectangle {
          width: Style.space(14)
          height: Style.space(14)
          radius: width / 2
          color: "#ffffff"
          anchors.verticalCenter: parent.verticalCenter
          x: root.fanOscillation ? parent.width - width - Style.space(2) : Style.space(2)
          Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.InOutQuad } }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: root.isOn ? Qt.PointingHandCursor : Qt.ArrowCursor
          enabled: root.isOn
          onClicked: root.setOscillation(!root.fanOscillation)
        }
      }
    }

    // ── Fan: Work mode selector ──
    Column {
      visible: root.showWorkMode && root.workModeOptions !== null && root.isOn
      width: parent.width
      spacing: Style.space(6)

      // Mode pills
      Flow {
        width: parent.width
        spacing: Style.space(5)

        Repeater {
          model: root.workModeOptions ? root.workModeOptions.modes.length : 0

          Rectangle {
            required property int index
            readonly property var mode: root.workModeOptions.modes[index]
            readonly property bool isActive: root.fanWorkMode === mode.value

            width: modeText.implicitWidth + Style.space(14)
            height: Style.space(26)
            radius: height / 2
            color: {
              if (isActive) return Color.accent
              if (modeArea.containsMouse && root.isOn)
                return Style.hoverFillFor(root.fg, Color.accent)
              return Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
            }

            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
              id: modeText
              anchors.centerIn: parent
              text: mode.name
              color: isActive ? "#ffffff" : root.fg
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
              font.bold: isActive
            }

            MouseArea {
              id: modeArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.isOn ? Qt.PointingHandCursor : Qt.ArrowCursor
              enabled: root.isOn
              onClicked: {
                // Use default modeValue: 0 for modes without speed, current speed for modes with speed
                var mv = mode.speeds > 0 ? Math.max(1, root.fanModeValue) : 0
                root.setWorkMode(mode.value, mv)
              }
            }
          }
        }
      }

      // Speed slider (only for modes that have speed options)
      Row {
        visible: {
          if (!root.workModeOptions) return false
          for (var i = 0; i < root.workModeOptions.modes.length; i++) {
            if (root.workModeOptions.modes[i].value === root.fanWorkMode)
              return root.workModeOptions.modes[i].speeds > 0
          }
          return false
        }
        width: parent.width
        spacing: Style.space(10)

        Text {
          text: "Speed"
          color: Qt.darker(root.fg, 1.4)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }

        Item {
          id: speedSliderContainer
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
              width: root.fanMaxSpeed > 0 ? parent.width * (root.fanModeValue / root.fanMaxSpeed) : 0
              height: parent.height
              radius: parent.radius
              color: root.isOn ? Color.accent : Qt.darker(root.fg, 1.5)
              Behavior on width { NumberAnimation { duration: 80 } }
            }
          }

          Rectangle {
            id: speedKnob
            width: Style.space(14)
            height: Style.space(14)
            radius: width / 2
            color: root.isOn ? Color.accent : Qt.darker(root.fg, 1.5)
            border.width: 2
            border.color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
            x: root.fanMaxSpeed > 0 ? (speedSliderContainer.width - width) * (root.fanModeValue / root.fanMaxSpeed) : 0
            Behavior on x { enabled: !speedMouse.pressed; NumberAnimation { duration: 80 } }
          }

          MouseArea {
            id: speedMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.isOn ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: root.isOn

            onPressed: function(mouse) { updateSpeed(mouse.x) }
            onPositionChanged: function(mouse) { if (pressed) updateSpeed(mouse.x) }
            onReleased: function(mouse) {
              var value = Math.max(1, Math.min(root.fanMaxSpeed, Math.round((mouse.x / speedSliderContainer.width) * root.fanMaxSpeed)))
              root.setWorkMode(root.fanWorkMode, value)
            }

            function updateSpeed(mouseX) {
              var value = Math.max(1, Math.min(root.fanMaxSpeed, Math.round((mouseX / speedSliderContainer.width) * root.fanMaxSpeed)))
              speedKnob.x = (speedSliderContainer.width - speedKnob.width) * (value / root.fanMaxSpeed)
            }
          }
        }

        Text {
          text: root.fanModeValue + "/" + root.fanMaxSpeed
          color: Qt.darker(root.fg, 1.3)
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          width: Style.space(32)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
        }
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

    // ── Music mode (expandable) ──
    Column {
      visible: root.musicExpanded && root.isOn && root.musicModeOptions !== null && root.musicModeOptions.length > 0
      width: parent.width
      spacing: Style.space(8)

      Text {
        text: "Music Mode"
        color: Qt.darker(root.fg, 1.3)
        font.family: root.fontFam
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      // Mode pills
      Flow {
        width: parent.width
        spacing: Style.space(5)

        Repeater {
          model: root.musicModeOptions ? root.musicModeOptions.length : 0

          Rectangle {
            required property int index
            readonly property var mode: root.musicModeOptions[index]
            readonly property bool isActive: root.musicSelectedMode === mode.value

            width: mmText.implicitWidth + Style.space(14)
            height: Style.space(26)
            radius: height / 2
            color: {
              if (isActive) return Color.accent
              if (mmArea.containsMouse)
                return Style.hoverFillFor(root.fg, Color.accent)
              return Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
            }

            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
              id: mmText
              anchors.centerIn: parent
              text: mode.name
              color: isActive ? "#ffffff" : root.fg
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
              font.bold: isActive
            }

            MouseArea {
              id: mmArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.musicSelectedMode = mode.value
                root.setMusicMode(root.musicSelectedMode, root.musicSensitivity, root.musicAutoColor, root.musicRgb)
              }
            }
          }
        }
      }

      // Sensitivity slider
      Row {
        width: parent.width
        spacing: Style.space(10)

        Text {
          text: "Sensitivity"
          color: Qt.darker(root.fg, 1.4)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }

        Item {
          id: sensSliderContainer
          width: parent.width - Style.space(110)
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
              width: parent.width * (root.musicSensitivity / 100)
              height: parent.height
              radius: parent.radius
              color: Color.accent
              Behavior on width { NumberAnimation { duration: 80 } }
            }
          }

          Rectangle {
            id: sensKnob
            width: Style.space(14)
            height: Style.space(14)
            radius: width / 2
            color: Color.accent
            border.width: 2
            border.color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
            x: (sensSliderContainer.width - width) * (root.musicSensitivity / 100)
            Behavior on x { enabled: !sensMouse.pressed; NumberAnimation { duration: 80 } }
          }

          MouseArea {
            id: sensMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onPressed: function(mouse) { updateSens(mouse.x) }
            onPositionChanged: function(mouse) { if (pressed) updateSens(mouse.x) }
            onReleased: function(mouse) {
              var value = Math.max(0, Math.min(100, Math.round((mouse.x / sensSliderContainer.width) * 100)))
              root.musicSensitivity = value
              if (root.musicSelectedMode >= 0)
                root.setMusicMode(root.musicSelectedMode, root.musicSensitivity, root.musicAutoColor, root.musicRgb)
            }

            function updateSens(mouseX) {
              var value = Math.max(0, Math.min(100, Math.round((mouseX / sensSliderContainer.width) * 100)))
              sensKnob.x = (sensSliderContainer.width - sensKnob.width) * (value / 100)
            }
          }
        }

        Text {
          text: root.musicSensitivity + "%"
          color: Qt.darker(root.fg, 1.3)
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          width: Style.space(32)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // Auto-color toggle
      Row {
        width: parent.width
        spacing: Style.space(10)

        Text {
          text: "Auto Color"
          color: Qt.darker(root.fg, 1.3)
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          anchors.verticalCenter: parent.verticalCenter
        }

        Item { width: parent.width - autoColorLabel.implicitWidth - autoColorToggle.width - Style.space(20); height: 1 }

        Text {
          id: autoColorLabel
          text: root.musicAutoColor ? "On" : "Off"
          color: Qt.darker(root.fg, 1.4)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
          id: autoColorToggle
          width: Style.space(32)
          height: Style.space(18)
          radius: height / 2
          color: root.musicAutoColor ? Color.accent : Qt.darker(root.fg, 2.5)
          anchors.verticalCenter: parent.verticalCenter

          Behavior on color { ColorAnimation { duration: 150 } }

          Rectangle {
            width: Style.space(14)
            height: Style.space(14)
            radius: width / 2
            color: "#ffffff"
            anchors.verticalCenter: parent.verticalCenter
            x: root.musicAutoColor ? parent.width - width - Style.space(2) : Style.space(2)
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.InOutQuad } }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.musicAutoColor = !root.musicAutoColor
              if (root.musicSelectedMode >= 0)
                root.setMusicMode(root.musicSelectedMode, root.musicSensitivity, root.musicAutoColor, root.musicRgb)
            }
          }
        }
      }

      // Fixed color picker (only when autoColor is off)
      Column {
        visible: !root.musicAutoColor
        width: parent.width
        spacing: Style.space(6)

        Text {
          text: "Fixed Color"
          color: Qt.darker(root.fg, 1.4)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
        }

        ColorPicker {
          width: parent.width
          bar: root.bar
          currentColor: root.musicRgb
          enabled: true
          onColorPicked: function(rgbInt) {
            root.musicRgb = rgbInt
            if (root.musicSelectedMode >= 0)
              root.setMusicMode(root.musicSelectedMode, root.musicSensitivity, root.musicAutoColor, root.musicRgb)
          }
        }
      }
    }
  }
}
