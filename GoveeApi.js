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
