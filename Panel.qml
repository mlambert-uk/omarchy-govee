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

  property var devices: []        // Full device list from API (lights only)
  property var deviceStates: ({}) // Map of device id -> { powerSwitch, brightness, ... }
  property bool loading: false
  property string errorText: ""

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
        root.devices = Api.filterLights(allDevices)
        root.loading = false
        // Fetch state for each device
        root.fetchAllStates()
      }
    }
  }

  // ─── Device state polling ───────────────────────────────────────────────

  property int stateIndex: 0

  function fetchAllStates() {
    stateIndex = 0
    deviceStates = {}
    fetchNextState()
  }

  function fetchNextState() {
    if (stateIndex >= devices.length) return
    var dev = devices[stateIndex]
    stateProc.command = Api.deviceStateCommand(apiKey, dev.sku, dev.device)
    stateProc.running = true
  }

  Process {
    id: stateProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw && root.stateIndex < root.devices.length) {
          var dev = root.devices[root.stateIndex]
          var states = root.deviceStates
          states[dev.device] = Api.parseDeviceState(raw)
          root.deviceStates = states
          root.deviceStatesChanged()
        }
        root.stateIndex++
        // Small delay between state requests to respect rate limits
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

  function controlDevice(sku, device, capability) {
    controlProc.command = Api.controlCommand(apiKey, sku, device, capability)
    controlProc.running = true
  }

  function togglePower(sku, device, currentlyOn) {
    controlDevice(sku, device, Api.powerCapability(!currentlyOn))
    // Optimistic update
    var states = deviceStates
    if (!states[device]) states[device] = {}
    states[device].powerSwitch = currentlyOn ? 0 : 1
    deviceStates = states
    deviceStatesChanged()
  }

  function setBrightness(sku, device, value) {
    controlDevice(sku, device, Api.brightnessCapability(value))
    // Optimistic update
    var states = deviceStates
    if (!states[device]) states[device] = {}
    states[device].brightness = value
    deviceStates = states
    deviceStatesChanged()
  }

  Process {
    id: controlProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Control fire-and-forget; errors are silent for now
      }
    }
  }

  // ─── Auto-refresh while open ────────────────────────────────────────────

  Timer {
    id: refreshTimer
    interval: 30000  // 30 seconds
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
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
            visible: !root.loading && !root.setupMode && root.hasKey && root.devices.length === 0 && root.errorText === ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No light devices found"
            color: Qt.darker(root.bar ? root.bar.foreground : "#ffffff", 1.4)
            font.family: root.bar ? root.bar.fontFamily : ""
            font.pixelSize: Style.font.body
          }

          // ── Device list ──
          Column {
            visible: !root.setupMode && root.devices.length > 0
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.devices

              DeviceCard {
                required property var modelData
                required property int index
                width: parent.width
                device: modelData
                deviceState: root.deviceStates[modelData.device] || {}
                bar: root.bar
                onTogglePower: function(sku, deviceId, currentlyOn) {
                  root.togglePower(sku, deviceId, currentlyOn)
                }
                onSetBrightness: function(sku, deviceId, value) {
                  root.setBrightness(sku, deviceId, value)
                }
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
