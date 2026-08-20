// GoveeApi.js — Govee Developer API v2 helpers for the Omarchy shell plugin.
//
// All network calls are performed by QML Process components (curl). This
// module builds the commands and parses the responses.

var API_BASE = "https://openapi.api.govee.com"

// ─── API key storage ────────────────────────────────────────────────────────

// The key is persisted in a small JSON file so it survives shell restarts.
function keyFilePath(home) {
  return home + "/.local/state/omarchy/settings/govee.json"
}

function parseKeyFile(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (data && typeof data.apiKey === "string")
      return data.apiKey.replace(/^\s+|\s+$/g, "")
  } catch (e) {}
  return ""
}

function keyFileContents(apiKey) {
  return JSON.stringify({ apiKey: apiKey }, null, 2)
}

// ─── Device list ────────────────────────────────────────────────────────────

// Curl command to fetch all devices.
function listDevicesCommand(apiKey) {
  return [
    "curl", "-fsS", "--max-time", "10",
    "-H", "Govee-API-Key: " + apiKey,
    "-H", "Content-Type: application/json",
    API_BASE + "/router/api/v1/user/devices"
  ]
}

// Parse the /user/devices response into a flat array of device objects.
// Each device carries: sku, device (id), deviceName, capabilities[].
function parseDevicesResponse(raw) {
  try {
    var resp = JSON.parse(String(raw || ""))
    if (resp && resp.code === 200 && Array.isArray(resp.data))
      return resp.data
  } catch (e) {}
  return []
}

// ─── Device state ───────────────────────────────────────────────────────────

// Curl command to query a single device's current state.
// The state endpoint is POST with sku+device in the JSON body.
function deviceStateCommand(apiKey, sku, device) {
  var body = JSON.stringify({
    requestId: generateRequestId(),
    payload: {
      sku: sku,
      device: device
    }
  })
  return [
    "curl", "-sS", "--max-time", "10",
    "-X", "POST",
    "-H", "Govee-API-Key: " + apiKey,
    "-H", "Content-Type: application/json",
    "-d", body,
    API_BASE + "/router/api/v1/device/state"
  ]
}

// Parse device state response. Returns an object mapping instance names to
// their current values, e.g. { powerSwitch: 1, brightness: 80 }.
function parseDeviceState(raw) {
  var state = {}
  try {
    var resp = JSON.parse(String(raw || ""))
    if (resp && resp.code === 200 && resp.payload && Array.isArray(resp.payload.capabilities)) {
      var caps = resp.payload.capabilities
      for (var i = 0; i < caps.length; i++) {
        var cap = caps[i]
        if (cap && cap.instance && cap.state !== undefined)
          state[cap.instance] = cap.state.value !== undefined ? cap.state.value : cap.state
      }
    }
  } catch (e) {}
  return state
}

// ─── Device control ─────────────────────────────────────────────────────────

// Build a curl command to send a control request.
// capability: { type, instance, value }
function controlCommand(apiKey, sku, device, capability) {
  var body = JSON.stringify({
    requestId: generateRequestId(),
    payload: {
      sku: sku,
      device: device,
      capability: capability
    }
  })
  return [
    "curl", "-fsS", "--max-time", "10",
    "-X", "POST",
    "-H", "Govee-API-Key: " + apiKey,
    "-H", "Content-Type: application/json",
    "-d", body,
    API_BASE + "/router/api/v1/device/control"
  ]
}

// Convenience: power on/off command payload.
function powerCapability(on) {
  return {
    type: "devices.capabilities.on_off",
    instance: "powerSwitch",
    value: on ? 1 : 0
  }
}

// Convenience: brightness command payload (1–100).
function brightnessCapability(value) {
  return {
    type: "devices.capabilities.range",
    instance: "brightness",
    value: Math.max(1, Math.min(100, Math.round(value)))
  }
}

// Convenience: RGB color command payload.
// rgbInt is a single integer 0–16777215 (0xRRGGBB).
function colorRgbCapability(rgbInt) {
  return {
    type: "devices.capabilities.color_setting",
    instance: "colorRgb",
    value: Math.max(0, Math.min(16777215, Math.round(rgbInt)))
  }
}

// Convenience: color temperature command payload (Kelvin).
function colorTemperatureCapability(kelvin) {
  return {
    type: "devices.capabilities.color_setting",
    instance: "colorTemperatureK",
    value: Math.max(2000, Math.min(9000, Math.round(kelvin)))
  }
}

// Convenience: light scene command payload.
// sceneValue can be either an integer (static scene) or an object { paramId, id } (dynamic scene).
function lightSceneCapability(sceneValue) {
  return {
    type: "devices.capabilities.dynamic_scene",
    instance: "lightScene",
    value: sceneValue
  }
}

// ─── Color conversion helpers ───────────────────────────────────────────────

// Convert RGB integer (0xRRGGBB) to {r, g, b} components (0–255 each).
function intToRgb(rgbInt) {
  return {
    r: (rgbInt >> 16) & 0xFF,
    g: (rgbInt >> 8) & 0xFF,
    b: rgbInt & 0xFF
  }
}

// Convert {r, g, b} (0–255) to a single integer.
function rgbToInt(r, g, b) {
  return ((Math.round(r) & 0xFF) << 16) | ((Math.round(g) & 0xFF) << 8) | (Math.round(b) & 0xFF)
}

// Convert HSV (h: 0–360, s: 0–1, v: 0–1) to {r, g, b} (0–255).
function hsvToRgb(h, s, v) {
  var c = v * s
  var x = c * (1 - Math.abs(((h / 60) % 2) - 1))
  var m = v - c
  var r, g, b
  if (h < 60)       { r = c; g = x; b = 0 }
  else if (h < 120) { r = x; g = c; b = 0 }
  else if (h < 180) { r = 0; g = c; b = x }
  else if (h < 240) { r = 0; g = x; b = c }
  else if (h < 300) { r = x; g = 0; b = c }
  else              { r = c; g = 0; b = x }
  return {
    r: Math.round((r + m) * 255),
    g: Math.round((g + m) * 255),
    b: Math.round((b + m) * 255)
  }
}

// Convert {r, g, b} (0–255) to {h, s, v} (h: 0–360, s/v: 0–1).
function rgbToHsv(r, g, b) {
  r /= 255; g /= 255; b /= 255
  var max = Math.max(r, g, b)
  var min = Math.min(r, g, b)
  var d = max - min
  var h = 0, s = max === 0 ? 0 : d / max, v = max
  if (d !== 0) {
    if (max === r) h = 60 * (((g - b) / d) % 6)
    else if (max === g) h = 60 * (((b - r) / d) + 2)
    else h = 60 * (((r - g) / d) + 4)
  }
  if (h < 0) h += 360
  return { h: h, s: s, v: v }
}

// Convert a color temperature in Kelvin to an approximate RGB for preview.
function kelvinToRgb(kelvin) {
  var temp = kelvin / 100
  var r, g, b
  if (temp <= 66) {
    r = 255
    g = Math.min(255, Math.max(0, 99.4708025861 * Math.log(temp) - 161.1195681661))
  } else {
    r = Math.min(255, Math.max(0, 329.698727446 * Math.pow(temp - 60, -0.1332047592)))
    g = Math.min(255, Math.max(0, 288.1221695283 * Math.pow(temp - 60, -0.0755148492)))
  }
  if (temp >= 66) b = 255
  else if (temp <= 19) b = 0
  else b = Math.min(255, Math.max(0, 138.5177312231 * Math.log(temp - 10) - 305.0447927307))
  return { r: Math.round(r), g: Math.round(g), b: Math.round(b) }
}

// ─── Capability extraction helpers ──────────────────────────────────────────

// Get the capability object for a given type+instance from a device.
function getCapability(device, type, instance) {
  if (!device || !Array.isArray(device.capabilities)) return null
  for (var i = 0; i < device.capabilities.length; i++) {
    var cap = device.capabilities[i]
    if (cap.type === type && cap.instance === instance) return cap
  }
  return null
}

// Extract the scene options list from a device's lightScene capability.
// Returns an array of { name, value } objects.
function getSceneOptions(device) {
  var cap = getCapability(device, "devices.capabilities.dynamic_scene", "lightScene")
  if (!cap || !cap.parameters || !Array.isArray(cap.parameters.options)) return []
  return cap.parameters.options
}

// ─── Dynamic scenes endpoint ────────────────────────────────────────────────

// Curl command to fetch dynamic scenes for a device.
function dynamicScenesCommand(apiKey, sku, device) {
  var body = JSON.stringify({
    requestId: generateRequestId(),
    payload: {
      sku: sku,
      device: device
    }
  })
  return [
    "curl", "-sS", "--max-time", "10",
    "-X", "POST",
    "-H", "Govee-API-Key: " + apiKey,
    "-H", "Content-Type: application/json",
    "-d", body,
    API_BASE + "/router/api/v1/device/scenes"
  ]
}

// Parse dynamic scenes response. Returns an array of { name, value } where
// value is the object { paramId, id } needed for the control command.
function parseDynamicScenes(raw) {
  var scenes = []
  try {
    var resp = JSON.parse(String(raw || ""))
    if (resp && resp.code === 200 && resp.payload && Array.isArray(resp.payload.capabilities)) {
      var caps = resp.payload.capabilities
      for (var i = 0; i < caps.length; i++) {
        var cap = caps[i]
        if (cap.instance === "lightScene" && cap.parameters && Array.isArray(cap.parameters.options)) {
          for (var j = 0; j < cap.parameters.options.length; j++) {
            var opt = cap.parameters.options[j]
            if (opt && opt.name && opt.value)
              scenes.push({ name: opt.name, value: opt.value })
          }
        }
      }
    }
  } catch (e) {}
  return scenes
}

// Get color temperature range {min, max} from a device. Returns null if unsupported.
function getColorTempRange(device) {
  var cap = getCapability(device, "devices.capabilities.color_setting", "colorTemperatureK")
  if (!cap || !cap.parameters || !cap.parameters.range) return null
  return { min: cap.parameters.range.min, max: cap.parameters.range.max }
}

// ─── Capability helpers ─────────────────────────────────────────────────────

// Check if a device has a given capability type + instance.
function hasCapability(device, type, instance) {
  if (!device || !Array.isArray(device.capabilities)) return false
  for (var i = 0; i < device.capabilities.length; i++) {
    var cap = device.capabilities[i]
    if (cap.type === type && cap.instance === instance) return true
  }
  return false
}

// Check if a device is a controllable light (has power switch).
function isLight(device) {
  return hasCapability(device, "devices.capabilities.on_off", "powerSwitch")
}

// Filter the full device list down to lights only.
function filterLights(devices) {
  var lights = []
  for (var i = 0; i < devices.length; i++) {
    if (isLight(devices[i])) lights.push(devices[i])
  }
  return lights
}

// Get a friendly display name for a device.
function deviceDisplayName(device) {
  if (device.deviceName) return device.deviceName
  return device.sku + " (" + device.device.substr(0, 8) + "...)"
}

// ─── Utilities ──────────────────────────────────────────────────────────────

function generateRequestId() {
  // Simple unique-ish ID: timestamp + random suffix.
  return Date.now().toString(36) + "-" + Math.random().toString(36).substr(2, 6)
}
