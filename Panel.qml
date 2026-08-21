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
  property bool credentialMigrationAttempted: false

  readonly property color fg: bar ? bar.foreground : "#ffffff"
  readonly property string fontFam: bar ? bar.fontFamily : ""

  // Path to the private header file used by curl commands (never contains the
  // key in process argv — it is read from this file at runtime).
  readonly property string headerFile: Api.headerFilePath(Quickshell.env("HOME"))

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
      var loadedKey = Api.parseKeyFile(text())
      root.apiKey = loadedKey
      root.setupMode = !root.hasKey
      // Older versions created only govee.json and could leave it mode 0644.
      // Rewrite once per plugin lifetime to repair its mode and create the
      // private curl header file. The guard prevents the write/reload cycle
      // from continually rewriting an already migrated credential.
      if (root.hasKey && !root.credentialMigrationAttempted) {
        root.credentialMigrationAttempted = true
        var migrationError = Api.validateApiKey(loadedKey)
        if (migrationError === "") root.persistApiKey(loadedKey)
        else root.setupError = migrationError
      }
    }
    onLoadFailed: {
      root.apiKey = ""
      root.setupMode = true
    }
  }

  function saveApiKey(key) {
    var trimmed = key.replace(/^\s+|\s+$/g, "")
    var error = Api.validateApiKey(trimmed)
    if (error !== "") {
      setupError = error
      return
    }
    setupError = ""
    credentialMigrationAttempted = true
    persistApiKey(trimmed)
  }

  function persistApiKey(key) {
    // The command contains paths only. The key is delivered over stdin once
    // the child has started, then removed from QML process state.
    keySaveProc.pendingKey = key
    keySaveProc.command = Api.saveKeyCommand(Quickshell.env("HOME"))
    keySaveProc.running = true
  }

  function clearApiKey() {
    keySaveProc.command = Api.clearKeyCommand(Quickshell.env("HOME"))
    keySaveProc.running = true
  }

  Process {
    id: keySaveProc
    property string pendingKey: ""
    stdinEnabled: true
    onStarted: {
      write(pendingKey + "\n")
      pendingKey = ""
    }
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
    if (listProc.running || stateProc.running || scenesProc.running) return
    // Don't show loading spinner on subsequent refreshes — only first load
    if (deviceModel.count === 0) loading = true
    errorText = ""
    listProc.stderrText = ""
    listProc.command = Api.listDevicesCommand(headerFile)
    listProc.running = true
  }

  Process {
    id: listProc
    property string stderrText: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").substring(0, 1048576).trim()
        if (!raw) {
          root.errorText = listProc.stderrText || "No response from Govee API"
          root.loading = false
          return
        }
        var apiError = Api.responseError(raw)
        if (apiError !== "") {
          root.errorText = apiError
          root.loading = false
          return
        }
        var allDevices = Api.parseDevicesResponse(raw)
        var lights = Api.filterControllable(allDevices)
        root.rawDevices = lights

        // Only rebuild the model on first load or if the device list changed
        if (root.needsModelRebuild(lights)) {
          root.buildModel(lights)
        }
        root.loading = false
        root.fetchAllStates()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: { listProc.stderrText = String(text || "").substring(0, 1024).trim() }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !stderrText)
        stderrText = "Network error (exit " + exitCode + ")"
    }
  }

  // Check if the device list has changed (different devices or order).
  function needsModelRebuild(lights) {
    if (deviceModel.count !== lights.length) return true
    for (var i = 0; i < lights.length; i++) {
      var item = deviceModel.get(i)
      if (item.sku !== lights[i].sku || item.deviceId !== lights[i].device) return true
    }
    return false
  }

  function buildModel(lights) {
    deviceModel.clear()
    scenesLoaded = false
    // Destroy previously created dynamic scene models
    for (var d = 0; d < sceneModels.length; d++) {
      if (sceneModels[d]) sceneModels[d].destroy()
    }
    var models = []
    for (var i = 0; i < lights.length; i++) {
      var dev = lights[i]
      var hasColor = Api.hasCapability(dev, "devices.capabilities.color_setting", "colorRgb")
      var hasTemp = Api.hasCapability(dev, "devices.capabilities.color_setting", "colorTemperatureK")
      var tempRange = Api.getColorTempRange(dev)
      var hasSceneCap = Api.hasCapability(dev, "devices.capabilities.dynamic_scene", "lightScene")
      var hasOscillation = Api.hasCapability(dev, "devices.capabilities.toggle", "oscillationToggle")
      var hasWorkMode = Api.hasCapability(dev, "devices.capabilities.work_mode", "workMode")
      var workModeOpts = Api.getWorkModeOptions(dev)
      var hasMusicMode = Api.hasCapability(dev, "devices.capabilities.music_setting", "musicMode")

      deviceModel.append({
        sku: dev.sku,
        deviceId: dev.device,
        deviceName: Api.deviceDisplayName(dev),
        isFan: Api.isFan(dev),
        hasBrightness: Api.hasCapability(dev, "devices.capabilities.range", "brightness"),
        hasColor: hasColor,
        hasColorTemp: hasTemp,
        hasScenes: hasSceneCap,
        hasOscillation: hasOscillation,
        hasWorkMode: hasWorkMode,
        hasMusic: hasMusicMode,
        maxSpeed: workModeOpts ? workModeOpts.maxSpeed : 0,
        devColorTempMin: tempRange ? tempRange.min : 2000,
        devColorTempMax: tempRange ? tempRange.max : 9000,
        powerOn: false,
        brightness: 100,
        devColorRgb: 16777215,
        devColorTempK: 4000,
        devActiveScene: -1,
        oscillation: false,
        workMode: 0,
        modeValue: 0,
        deviceOnline: true
      })

      // Create an empty scene model; populated later by fetchScenes
      var sceneModel = Qt.createQmlObject('import QtQuick; ListModel {}', root)
      models.push(sceneModel)
    }
    sceneModels = models

    // Store work mode options per device for the UI
    var wmOpts = []
    var mmOpts = []
    for (var j = 0; j < lights.length; j++) {
      wmOpts.push(Api.getWorkModeOptions(lights[j]))
      mmOpts.push(Api.getMusicModeOptions(lights[j]))
    }
    workModeOptions = wmOpts
    musicModeOptions = mmOpts
  }

  // Per-device work mode options (array indexed by device position).
  property var workModeOptions: []
  // Per-device music mode options (array of [{name, value}] arrays).
  property var musicModeOptions: []

  // ─── Scene fetching ─────────────────────────────────────────────────────

  // Per-device scene values (objects like { paramId, id }) indexed by
  // position in sceneModels, then by ListModel row index.
  property var sceneValues: []
  property bool scenesLoaded: false

  property int sceneIndex: 0

  function fetchAllScenes() {
    sceneIndex = 0
    sceneValues = []
    for (var i = 0; i < deviceModel.count; i++) sceneValues.push([])
    fetchNextScenes()
  }

  function fetchNextScenes() {
    if (sceneIndex >= deviceModel.count) {
      scenesLoaded = true
      return
    }
    var item = deviceModel.get(sceneIndex)
    if (!item.hasScenes) {
      sceneIndex++
      fetchNextScenes()
      return
    }
    scenesProc.command = Api.dynamicScenesCommand(headerFile, item.sku, item.deviceId)
    scenesProc.running = true
  }

  Process {
    id: scenesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").substring(0, 1048576).trim()
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
      // After all states fetched, fetch scenes only on first load
      if (!scenesLoaded && deviceModel.count > 0)
        fetchAllScenes()
      return
    }
    var item = deviceModel.get(stateIndex)
    stateProc.command = Api.deviceStateCommand(headerFile, item.sku, item.deviceId)
    stateProc.running = true
  }

  Process {
    id: stateProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").substring(0, 1048576).trim()
        if (raw && root.stateIndex < deviceModel.count && !root.isControlInFlight(root.stateIndex)) {
          var parsed = Api.parseDeviceState(raw)
          if (!parsed) {
            root.stateIndex++
            stateDelayTimer.restart()
            return
          }
          var item = deviceModel.get(root.stateIndex)

          // If device is offline, treat as off regardless of last-known state
          var isOnline = parsed.online !== false
          var isOn = isOnline && parsed.powerSwitch === 1
          var bri = parsed.brightness !== undefined ? parsed.brightness : 100

          // Only update properties that actually changed
          if (item.deviceOnline !== isOnline)
            deviceModel.setProperty(root.stateIndex, "deviceOnline", isOnline)
          if (item.powerOn !== isOn)
            deviceModel.setProperty(root.stateIndex, "powerOn", isOn)
          if (item.brightness !== bri)
            deviceModel.setProperty(root.stateIndex, "brightness", bri)

          // Color state
          if (parsed.colorRgb !== undefined && parsed.colorRgb !== "" && item.devColorRgb !== parsed.colorRgb)
            deviceModel.setProperty(root.stateIndex, "devColorRgb", parsed.colorRgb)
          if (parsed.colorTemperatureK !== undefined && parsed.colorTemperatureK !== "" && parsed.colorTemperatureK !== 0 && item.devColorTempK !== parsed.colorTemperatureK)
            deviceModel.setProperty(root.stateIndex, "devColorTempK", parsed.colorTemperatureK)

          // Fan state
          if (parsed.oscillationToggle !== undefined) {
            var osc = parsed.oscillationToggle === 1
            if (item.oscillation !== osc)
              deviceModel.setProperty(root.stateIndex, "oscillation", osc)
          }
          if (parsed.workMode !== undefined && typeof parsed.workMode === "object") {
            var wm = parsed.workMode.workMode !== undefined ? parsed.workMode.workMode : 0
            var mv = parsed.workMode.modeValue !== undefined ? parsed.workMode.modeValue : 0
            if (item.workMode !== wm)
              deviceModel.setProperty(root.stateIndex, "workMode", wm)
            if (item.modeValue !== mv)
              deviceModel.setProperty(root.stateIndex, "modeValue", mv)
          }
        }
        root.stateIndex++
        stateDelayTimer.restart()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var err = String(text || "").substring(0, 1024).trim()
        if (err) console.warn("Govee state poll error:", err)
      }
    }
  }

  Timer {
    id: stateDelayTimer
    interval: 200
    onTriggered: root.fetchNextState()
  }

  // ─── Device control ─────────────────────────────────────────────────────

  // Track the number of queued/running control commands per device. A count is
  // necessary because sliders can enqueue several updates for the same device.
  property var controlInFlightDevices: ({})

  // Command queue: each entry is { command: [...], index: int }
  property var controlQueue: []

  // Rate-limit backoff: when true, new commands are dropped until the timer fires.
  property bool rateLimited: false

  function isControlInFlight(index) {
    return (controlInFlightDevices[index] || 0) > 0
  }

  function incrementControlInFlight(index) {
    var inflight = controlInFlightDevices
    inflight[index] = (inflight[index] || 0) + 1
    controlInFlightDevices = inflight
  }

  function decrementControlInFlight(index) {
    var inflight = controlInFlightDevices
    var remaining = (inflight[index] || 0) - 1
    if (remaining > 0) inflight[index] = remaining
    else delete inflight[index]
    controlInFlightDevices = inflight
  }

  function discardQueuedControls() {
    for (var i = 0; i < controlQueue.length; i++)
      decrementControlInFlight(controlQueue[i].index)
    controlQueue = []
  }

  // Reset the auto-refresh timer whenever the user interacts.
  function resetRefreshTimer() {
    refreshTimer.restart()
  }

  function controlDevice(sku, device, capability, index) {
    if (rateLimited) return false  // Drop commands during backoff

    incrementControlInFlight(index)
    resetRefreshTimer()

    var cmd = Api.controlCommand(headerFile, sku, device, capability)
    controlQueue.push({ command: cmd, index: index })
    controlQueue = controlQueue  // trigger change
    processControlQueue()
    return true
  }

  function processControlQueue() {
    if (controlProc.running) return
    if (rateLimited || controlQueue.length === 0) return
    var next = controlQueue.shift()
    controlQueue = controlQueue  // trigger change
    controlProc.controlIndex = next.index
    controlProc.command = next.command
    controlProc.running = true
  }

  function togglePower(index) {
    var item = deviceModel.get(index)
    var newState = !item.powerOn
    if (controlDevice(item.sku, item.deviceId, Api.powerCapability(newState), index))
      deviceModel.setProperty(index, "powerOn", newState)
  }

  function setBrightness(index, value) {
    var item = deviceModel.get(index)
    if (controlDevice(item.sku, item.deviceId, Api.brightnessCapability(value), index))
      deviceModel.setProperty(index, "brightness", value)
  }

  function setColor(index, rgbInt) {
    var item = deviceModel.get(index)
    if (controlDevice(item.sku, item.deviceId, Api.colorRgbCapability(rgbInt), index)) {
      deviceModel.setProperty(index, "devColorRgb", rgbInt)
      deviceModel.setProperty(index, "devActiveScene", -1)
    }
  }

  function setColorTemp(index, kelvin) {
    var item = deviceModel.get(index)
    if (controlDevice(item.sku, item.deviceId, Api.colorTemperatureCapability(kelvin), index)) {
      deviceModel.setProperty(index, "devColorTempK", kelvin)
      deviceModel.setProperty(index, "devActiveScene", -1)
    }
  }

  function setScene(index, sceneIndex) {
    var item = deviceModel.get(index)
    var values = sceneValues[index]
    if (!values || sceneIndex < 0 || sceneIndex >= values.length) return
    var sceneValue = values[sceneIndex]
    if (controlDevice(item.sku, item.deviceId, Api.lightSceneCapability(sceneValue), index))
      deviceModel.setProperty(index, "devActiveScene", sceneIndex)
  }

  function setOscillation(index, on) {
    var item = deviceModel.get(index)
    if (controlDevice(item.sku, item.deviceId, Api.oscillationCapability(on), index))
      deviceModel.setProperty(index, "oscillation", on)
  }

  function setWorkMode(index, workMode, modeValue) {
    var item = deviceModel.get(index)
    if (controlDevice(item.sku, item.deviceId, Api.workModeCapability(workMode, modeValue), index)) {
      deviceModel.setProperty(index, "workMode", workMode)
      deviceModel.setProperty(index, "modeValue", modeValue)
    }
  }

  function setMusicMode(index, musicMode, sensitivity, autoColor, rgb) {
    var item = deviceModel.get(index)
    controlDevice(item.sku, item.deviceId, Api.musicModeCapability(musicMode, sensitivity, autoColor, rgb), index)
  }

  Process {
    id: controlProc
    property int controlIndex: -1
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var err = String(text || "").substring(0, 1024).trim()
        if (err) {
          console.warn("Govee control error:", err)
          if (err.indexOf("429") >= 0) {
            root.showNotification("Rate limited — too many requests. Wait a moment before trying again.")
            // Clear pending commands and pause for 5 seconds
            root.discardQueuedControls()
            root.rateLimited = true
            rateLimitTimer.restart()
          } else if (err.indexOf("401") >= 0 || err.indexOf("403") >= 0)
            root.showNotification("Authentication error — check your API key.")
          else
            root.showNotification("Command failed — check your network connection.")
        }
      }
    }
    onExited: function(exitCode) {
      if (controlProc.controlIndex >= 0) {
        root.decrementControlInFlight(controlProc.controlIndex)
      }
      controlProc.controlIndex = -1
      root.processControlQueue()
    }
  }

  function showNotification(message) {
    notifyProc.command = ["notify-send", "-u", "low", "-a", "Govee", "Govee", message]
    notifyProc.running = true
  }

  Process {
    id: notifyProc
    running: false
  }

  Timer {
    id: rateLimitTimer
    interval: 5000
    onTriggered: {
      root.rateLimited = false
      root.processControlQueue()
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
              color: root.fg
              font.family: root.fontFam
              font.pixelSize: Style.font.display
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "Govee Lights"
              color: root.fg
              font.family: root.fontFam
              font.pixelSize: Style.font.title
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // ── Divider ──
          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.fg
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
              color: root.fg
              font.family: root.fontFam
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Column {
              width: parent.width - Style.space(32)
              spacing: Style.space(6)

              Text {
                text: "1. Open the Govee Home app on your phone"
                color: Qt.darker(root.fg, 1.3)
                font.family: root.fontFam
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                text: "2. Go to Settings (profile icon)"
                color: Qt.darker(root.fg, 1.3)
                font.family: root.fontFam
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                text: "3. Tap \"About Us\" then \"Apply for API Key\""
                color: Qt.darker(root.fg, 1.3)
                font.family: root.fontFam
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                text: "4. Copy the key and paste it below"
                color: Qt.darker(root.fg, 1.3)
                font.family: root.fontFam
                font.pixelSize: Style.font.bodySmall
              }
            }

            Row {
              spacing: Style.space(8)

              TextField {
                id: apiKeyField
                width: Style.space(240)
                placeholderText: "Paste your API key"
                foreground: root.fg
                font.family: root.fontFam

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
                color: saveArea.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : Color.accent
                anchors.verticalCenter: apiKeyField.verticalCenter

                Text {
                  id: saveLabel
                  anchors.centerIn: parent
                  text: "Save"
                  color: "#ffffff"
                  font.family: root.fontFam
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
              textFormat: Text.PlainText
              color: "#ff6b6b"
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
            }
          }

          // ── Loading indicator ──
          Text {
            visible: root.loading && !root.setupMode
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Loading devices..."
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFam
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
            textFormat: Text.PlainText
            color: "#ff6b6b"
            font.family: root.fontFam
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ── No devices found ──
          Text {
            visible: !root.loading && !root.setupMode && root.hasKey && deviceModel.count === 0 && root.errorText === ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No light devices found"
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFam
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
                required property bool isFan
                required property bool hasBrightness
                required property bool hasColor
                required property bool hasColorTemp
                required property bool hasScenes
                required property bool hasMusic
                required property bool hasOscillation
                required property bool hasWorkMode
                required property int maxSpeed
                required property int devColorTempMin
                required property int devColorTempMax
                required property bool powerOn
                required property int brightness
                required property int devColorRgb
                required property int devColorTempK
                required property int devActiveScene
                required property bool oscillation
                required property int workMode
                required property int modeValue
                required property bool deviceOnline

                width: parent.width
                isOn: powerOn
                deviceBrightness: brightness
                showBrightness: hasBrightness
                showColor: hasColor
                showColorTemp: hasColorTemp
                showScenes: hasScenes
                showOscillation: hasOscillation
                showWorkMode: hasWorkMode
                fanMaxSpeed: maxSpeed
                colorRgb: devColorRgb
                colorTempK: devColorTempK
                colorTempMin: devColorTempMin
                colorTempMax: devColorTempMax
                fanOscillation: oscillation
                fanWorkMode: workMode
                fanModeValue: modeValue
                name: deviceName
                skuLabel: sku
                deviceIsFan: isFan
                bar: root.bar
                sceneModel: root.sceneModels.length > index ? root.sceneModels[index] : null
                activeScene: devActiveScene
                workModeOptions: root.workModeOptions.length > index ? root.workModeOptions[index] : null
                musicModeOptions: root.musicModeOptions.length > index ? root.musicModeOptions[index] : null
                showMusic: hasMusic
                online: deviceOnline

                onTogglePower: root.togglePower(index)
                onSetBrightness: function(value) { root.setBrightness(index, value) }
                onSetColor: function(rgbInt) { root.setColor(index, rgbInt) }
                onSetColorTemp: function(kelvin) { root.setColorTemp(index, kelvin) }
                onSetScene: function(sceneValue) { root.setScene(index, sceneValue) }
                onSetOscillation: function(on) { root.setOscillation(index, on) }
                onSetWorkMode: function(wm, mv) { root.setWorkMode(index, wm, mv) }
                onSetMusicMode: function(mode, sens, auto, rgb) { root.setMusicMode(index, mode, sens, auto, rgb) }
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
              color: Qt.darker(root.fg, 1.5)
              font.family: root.fontFam
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "\u00b7 Reset"
              color: Qt.darker(root.fg, 1.3)
              font.family: root.fontFam
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
