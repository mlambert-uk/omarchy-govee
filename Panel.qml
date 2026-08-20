import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "GoveeApi.js" as Api

Panel {
  id: root
  moduleName: "mlambert-uk.govee"
  ipcTarget: "mlambert-uk.govee"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ─── State ──────────────────────────────────────────────────────────────

  property string apiKey: ""
  property bool hasKey: apiKey !== ""
  property bool setupMode: !hasKey
  property string setupError: ""

  property bool loading: false
  property string errorText: ""

  // The device list model holds device info + live state.
  ListModel { id: deviceModel }

  // Per-device scene models (indexed by device list position).
  property var sceneModels: []

  // ─── Panel lifecycle ────────────────────────────────────────────────────

  function open() {
    openedFromHotkey = false
    root.controller.show()
    keyFile.reload()
    if (hasKey) refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    keyFile.reload()
    if (hasKey) refresh()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // ─── API key persistence ────────────────────────────────────────────────

  property FileView keyFile: FileView {
    path: Api.keyFilePath(Quickshell.env("HOME"))
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.apiKey = Api.parseKeyFile(text())
      root.setupMode = !root.hasKey
    }
    onLoadFailed: {
      root.apiKey = ""
      root.setupMode = true
    }
  }

  function saveApiKey(key) {
    var trimmed = key.replace(/^\s+|\s+$/, "")
    if (trimmed === "") {
      setupError = "API key cannot be empty"
      return
    }
    setupError = ""
    keySaveProc.command = ["sh", "-c",
      "mkdir -p \"$(dirname '" + Api.keyFilePath(Quickshell.env("HOME")) + "')\" && " +
      "printf '%s' '" + Api.keyFileContents(trimmed).replace(/'/g, "'\\''") + "' > '" +
      Api.keyFilePath(Quickshell.env("HOME")) + "'"
    ]
    keySaveProc.running = true
  }

  function clearApiKey() {
    keySaveProc.command = ["rm", "-f", Api.keyFilePath(Quickshell.env("HOME"))]
    keySaveProc.running = true
  }

  Process {
    id: keySaveProc
    onExited: function(exitCode) {
      if (exitCode === 0) {
        keyFile.reload()
        if (root.hasKey) root.refresh()
      } else {
        root.setupError = "Failed to save API key"
      }
    }
  }

  // ─── Device discovery ───────────────────────────────────────────────────

  // Keep raw device data for capabilities lookup.
  property var rawDevices: []

  function refresh() {
    if (!hasKey) return
    loading = true
    errorText = ""
    listProc.command = Api.listDevicesCommand(apiKey)
    listProc.running = true
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.errorText = "No response from Govee API"
          root.loading = false
          return
        }
        var allDevices = Api.parseDevicesResponse(raw)
        var lights = Api.filterLights(allDevices)
        root.rawDevices = lights
        root.buildModel(lights)
        root.loading = false
        root.fetchAllStates()
      }
    }
  }

  function buildModel(lights) {
    deviceModel.clear()
    var models = []
    for (var i = 0; i < lights.length; i++) {
      var dev = lights[i]
      var hasColor = Api.hasCapability(dev, "devices.capabilities.color_setting", "colorRgb")
      var hasTemp = Api.hasCapability(dev, "devices.capabilities.color_setting", "colorTemperatureK")
      var tempRange = Api.getColorTempRange(dev)
      var hasSceneCap = Api.hasCapability(dev, "devices.capabilities.dynamic_scene", "lightScene")

      deviceModel.append({
        sku: dev.sku,
        deviceId: dev.device,
        deviceName: Api.deviceDisplayName(dev),
        hasBrightness: Api.hasCapability(dev, "devices.capabilities.range", "brightness"),
        hasColor: hasColor,
        hasColorTemp: hasTemp,
        hasScenes: hasSceneCap,
        devColorTempMin: tempRange ? tempRange.min : 2000,
        devColorTempMax: tempRange ? tempRange.max : 9000,
        powerOn: false,
        brightness: 100,
        devColorRgb: 16777215,
        devColorTempK: 4000,
        devActiveScene: -1
      })

      // Create an empty scene model; populated later by fetchScenes
      var sceneModel = Qt.createQmlObject('import QtQuick; ListModel {}', root)
      models.push(sceneModel)
    }
    sceneModels = models
  }

  // ─── Scene fetching ─────────────────────────────────────────────────────

  // Per-device scene values (objects like { paramId, id }) indexed by
  // position in sceneModels, then by ListModel row index.
  property var sceneValues: []

  property int sceneIndex: 0

  function fetchAllScenes() {
    sceneIndex = 0
    sceneValues = []
    for (var i = 0; i < deviceModel.count; i++) sceneValues.push([])
    fetchNextScenes()
  }

  function fetchNextScenes() {
    if (sceneIndex >= deviceModel.count) return
    var item = deviceModel.get(sceneIndex)
    if (!item.hasScenes) {
      sceneIndex++
      fetchNextScenes()
      return
    }
    scenesProc.command = Api.dynamicScenesCommand(apiKey, item.sku, item.deviceId)
    scenesProc.running = true
  }

  Process {
    id: scenesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw && root.sceneIndex < deviceModel.count) {
          var scenes = Api.parseDynamicScenes(raw)
          var model = root.sceneModels[root.sceneIndex]
          var values = root.sceneValues
          if (model) {
            model.clear()
            var deviceValues = []
            for (var i = 0; i < scenes.length; i++) {
              model.append({ name: scenes[i].name, value: i })
              deviceValues.push(scenes[i].value)
            }
            values[root.sceneIndex] = deviceValues
            root.sceneValues = values
          }
        }
        root.sceneIndex++
        sceneDelayTimer.restart()
      }
    }
  }

  Timer {
    id: sceneDelayTimer
    interval: 200
    onTriggered: root.fetchNextScenes()
  }

  // ─── Device state polling ───────────────────────────────────────────────

  property int stateIndex: 0

  function fetchAllStates() {
    stateIndex = 0
    fetchNextState()
  }

  function fetchNextState() {
    if (stateIndex >= deviceModel.count) {
      // After all states fetched, fetch scenes
      fetchAllScenes()
      return
    }
    var item = deviceModel.get(stateIndex)
    stateProc.command = Api.deviceStateCommand(apiKey, item.sku, item.deviceId)
    stateProc.running = true
  }

  Process {
    id: stateProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw && root.stateIndex < deviceModel.count && !root.controlInFlight) {
          var parsed = Api.parseDeviceState(raw)
          var isOn = parsed.powerSwitch === 1
          var bri = parsed.brightness !== undefined ? parsed.brightness : 100
          deviceModel.setProperty(root.stateIndex, "powerOn", isOn)
          deviceModel.setProperty(root.stateIndex, "brightness", bri)

          // Color state
          if (parsed.colorRgb !== undefined && parsed.colorRgb !== "")
            deviceModel.setProperty(root.stateIndex, "devColorRgb", parsed.colorRgb)
          if (parsed.colorTemperatureK !== undefined && parsed.colorTemperatureK !== "" && parsed.colorTemperatureK !== 0)
            deviceModel.setProperty(root.stateIndex, "devColorTempK", parsed.colorTemperatureK)
        }
        root.stateIndex++
        stateDelayTimer.restart()
      }
    }
  }

  Timer {
    id: stateDelayTimer
    interval: 200
    onTriggered: root.fetchNextState()
  }

  // ─── Device control ─────────────────────────────────────────────────────

  property bool controlInFlight: false

  function controlDevice(sku, device, capability) {
    controlInFlight = true
    controlProc.command = Api.controlCommand(apiKey, sku, device, capability)
    controlProc.running = true
  }

  function togglePower(index) {
    var item = deviceModel.get(index)
    var newState = !item.powerOn
    controlDevice(item.sku, item.deviceId, Api.powerCapability(newState))
    deviceModel.setProperty(index, "powerOn", newState)
  }

  function setBrightness(index, value) {
    var item = deviceModel.get(index)
    controlDevice(item.sku, item.deviceId, Api.brightnessCapability(value))
    deviceModel.setProperty(index, "brightness", value)
  }

  function setColor(index, rgbInt) {
    var item = deviceModel.get(index)
    controlDevice(item.sku, item.deviceId, Api.colorRgbCapability(rgbInt))
    deviceModel.setProperty(index, "devColorRgb", rgbInt)
    deviceModel.setProperty(index, "devActiveScene", -1)
  }

  function setColorTemp(index, kelvin) {
    var item = deviceModel.get(index)
    controlDevice(item.sku, item.deviceId, Api.colorTemperatureCapability(kelvin))
    deviceModel.setProperty(index, "devColorTempK", kelvin)
    deviceModel.setProperty(index, "devActiveScene", -1)
  }

  function setScene(index, sceneIndex) {
    var item = deviceModel.get(index)
    var values = sceneValues[index]
    if (!values || sceneIndex < 0 || sceneIndex >= values.length) return
    var sceneValue = values[sceneIndex]
    controlDevice(item.sku, item.deviceId, Api.lightSceneCapability(sceneValue))
    deviceModel.setProperty(index, "devActiveScene", sceneIndex)
  }

  Process {
    id: controlProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.controlInFlight = false
      }
    }
  }

  // ─── Auto-refresh while open ────────────────────────────────────────────

  Timer {
    id: refreshTimer
    interval: 30000
    running: root.opened && root.hasKey
    repeat: true
    onTriggered: root.refresh()
  }

  // ─── IPC ────────────────────────────────────────────────────────────────

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.setupMode && apiKeyField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: contentScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: contentScroll.width
          spacing: Style.space(12)
          topPadding: Style.space(16)
          bottomPadding: Style.space(16)

          // ── Header ──
          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            spacing: Style.space(10)

            Text {
              text: "\u{F0335}"
              color: root.bar ? root.bar.foreground : "#ffffff"
              font.family: root.bar ? root.bar.fontFamily : ""
              font.pixelSize: Style.font.display
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "Govee Lights"
              color: root.bar ? root.bar.foreground : "#ffffff"
              font.family: root.bar ? root.bar.fontFamily : ""
              font.pixelSize: Style.font.title
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // ── Divider ──
          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.bar ? root.bar.foreground : "#ffffff"
            opacity: 0.12
          }

          // ── Setup mode: API key entry ──
          Column {
            visible: root.setupMode
            width: parent.width
            spacing: Style.space(12)
            leftPadding: Style.space(16)
            rightPadding: Style.space(16)

            Text {
              width: parent.width - Style.space(32)
              text: "To get started, you need a Govee API key:"
              color: root.bar ? root.bar.foreground : "#ffffff"
              font.family: root.bar ? root.bar.fontFamily : ""
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Column {
              width: parent.width - Style.space(32)
              spacing: Style.space(6)

              Text {
                text: "1. Open the Govee Home app on your phone"
                color: Qt.darker(root.bar ? root.bar.foreground : "#ffffff", 1.3)
                font.family: root.bar ? root.bar.fontFamily : ""
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                text: "2. Go to Settings (profile icon)"
                color: Qt.darker(root.bar ? root.bar.foreground : "#ffffff", 1.3)
                font.family: root.bar ? root.bar.fontFamily : ""
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                text: "3. Tap \"About Us\" then \"Apply for API Key\""
                color: Qt.darker(root.bar ? root.bar.foreground : "#ffffff", 1.3)
                font.family: root.bar ? root.bar.fontFamily : ""
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                text: "4. Copy the key and paste it below"
                color: Qt.darker(root.bar ? root.bar.foreground : "#ffffff", 1.3)
                font.family: root.bar ? root.bar.fontFamily : ""
                font.pixelSize: Style.font.bodySmall
              }
            }

            Row {
              spacing: Style.space(8)

              TextField {
                id: apiKeyField
                width: Style.space(240)
                placeholderText: "Paste your API key"
                foreground: root.bar ? root.bar.foreground : "#ffffff"
                font.family: root.bar ? root.bar.fontFamily : ""

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.saveApiKey(apiKeyField.text)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Escape) {
                    root.close()
                    event.accepted = true
                  }
                }
              }

              Rectangle {
                width: saveLabel.implicitWidth + Style.space(16)
                height: apiKeyField.height
                radius: Style.cornerRadius
                color: saveArea.containsMouse ? Style.hoverFillFor(root.bar ? root.bar.foreground : "#ffffff", Color.accent) : Color.accent
                anchors.verticalCenter: apiKeyField.verticalCenter

                Text {
                  id: saveLabel
                  anchors.centerIn: parent
                  text: "Save"
                  color: "#ffffff"
                  font.family: root.bar ? root.bar.fontFamily : ""
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: saveArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.saveApiKey(apiKeyField.text)
                }
              }
            }

            Text {
              visible: root.setupError !== ""
              text: root.setupError
              color: "#ff6b6b"
              font.family: root.bar ? root.bar.fontFamily : ""
              font.pixelSize: Style.font.bodySmall
            }
          }

          // ── Loading indicator ──
          Text {
            visible: root.loading && !root.setupMode
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Loading devices..."
            color: Qt.darker(root.bar ? root.bar.foreground : "#ffffff", 1.4)
            font.family: root.bar ? root.bar.fontFamily : ""
            font.pixelSize: Style.font.body
            font.italic: true
          }

          // ── Error message ──
          Text {
            visible: root.errorText !== "" && !root.setupMode
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            text: root.errorText
            color: "#ff6b6b"
            font.family: root.bar ? root.bar.fontFamily : ""
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ── No devices found ──
          Text {
            visible: !root.loading && !root.setupMode && root.hasKey && deviceModel.count === 0 && root.errorText === ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No light devices found"
            color: Qt.darker(root.bar ? root.bar.foreground : "#ffffff", 1.4)
            font.family: root.bar ? root.bar.fontFamily : ""
            font.pixelSize: Style.font.body
          }

          // ── Device list ──
          Column {
            visible: !root.setupMode && deviceModel.count > 0
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: deviceModel

              DeviceCard {
                required property int index
                required property string sku
                required property string deviceId
                required property string deviceName
                required property bool hasBrightness
                required property bool hasColor
                required property bool hasColorTemp
                required property bool hasScenes
                required property int devColorTempMin
                required property int devColorTempMax
                required property bool powerOn
                required property int brightness
                required property int devColorRgb
                required property int devColorTempK
                required property int devActiveScene

                width: parent.width
                isOn: powerOn
                deviceBrightness: brightness
                showBrightness: hasBrightness
                showColor: hasColor
                showColorTemp: hasColorTemp
                showScenes: hasScenes
                colorRgb: devColorRgb
                colorTempK: devColorTempK
                colorTempMin: devColorTempMin
                colorTempMax: devColorTempMax
                name: deviceName
                skuLabel: sku
                bar: root.bar
                sceneModel: root.sceneModels.length > index ? root.sceneModels[index] : null
                sceneActive: devActiveScene

                onTogglePower: root.togglePower(index)
                onSetBrightness: function(value) { root.setBrightness(index, value) }
                onSetColor: function(rgbInt) { root.setColor(index, rgbInt) }
                onSetColorTemp: function(kelvin) { root.setColorTemp(index, kelvin) }
                onSetScene: function(sceneValue) { root.setScene(index, sceneValue) }
                onOpenScenes: {}
              }
            }
          }

          // ── Footer: settings link ──
          Row {
            visible: root.hasKey && !root.setupMode
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)

            Text {
              text: "API key configured"
              color: Qt.darker(root.bar ? root.bar.foreground : "#ffffff", 1.5)
              font.family: root.bar ? root.bar.fontFamily : ""
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "\u00b7 Reset"
              color: Qt.darker(root.bar ? root.bar.foreground : "#ffffff", 1.3)
              font.family: root.bar ? root.bar.fontFamily : ""
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clearApiKey()
              }
            }
          }
        }
      }
    }
  }
}
