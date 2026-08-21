// GoveeApi.js — Govee Developer API v2 helpers for the Omarchy shell plugin.
//
// All network calls are performed by QML Process components (curl). This
// module builds the commands and parses the responses.
//
// Security:
// - The API key is validated to contain only safe characters before storage.
// - Key files are always written with mode 0600 (owner-only) using install(1).
// - The API key is never passed as a curl command-line argument. It is read
//   from a private file and piped to curl via --config stdin (-K -), keeping
//   it out of /proc/*/cmdline for network operations.

var API_BASE = "https://openapi.api.govee.com"

// ─── API key storage ────────────────────────────────────────────────────────

// The key is persisted in a small JSON file so it survives shell restarts.
function keyFilePath(home) {
  return home + "/.local/state/omarchy/settings/govee.json"
}

// A separate private file holds just the raw API key for curl consumption.
// This avoids passing the key on any command line during API requests.
function headerFilePath(home) {
  return home + "/.local/state/omarchy/settings/govee-header"
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

// Validate that an API key contains only safe characters.
// Govee API keys are UUID-formatted hex strings with dashes.
// Rejecting anything else prevents curl config injection and shell escaping issues.
// Returns an error string if invalid, or "" if the key is acceptable.
function validateApiKey(apiKey) {
  if (!apiKey || apiKey.length === 0)
    return "API key cannot be empty"
  if (apiKey.length > 128)
    return "API key is too long"
  if (!/^[a-zA-Z0-9\-]+$/.test(apiKey))
    return "API key contains invalid characters (only letters, digits, and dashes are allowed)"
  return ""
}

// Shell command to persist both key files with restrictive permissions.
// The API key is supplied on stdin after the process starts; it is never part
// of this command array or visible in /proc/*/cmdline. Temporary files are
// created beside their destinations and atomically renamed into place, which
// also repairs permissive modes left by older plugin versions.
function saveKeyCommand(home) {
  var dir = home + "/.local/state/omarchy/settings"
  var kFile = keyFilePath(home)
  var hFile = headerFilePath(home)
  return [
    "bash", "-c",
    'set -e; umask 077; IFS= read -r key; [[ -n "$key" && ${#key} -le 128 && "$key" =~ ^[a-zA-Z0-9-]+$ ]]; mkdir -p -- "$1"; json_tmp=$(mktemp "$1/.govee.json.XXXXXX"); header_tmp=$(mktemp "$1/.govee-header.XXXXXX"); trap \'rm -f -- "$json_tmp" "$header_tmp"\' EXIT; printf \'{\\n  "apiKey": "%s"\\n}\\n\' "$key" > "$json_tmp"; printf \'%s\' "$key" > "$header_tmp"; chmod 600 -- "$json_tmp" "$header_tmp"; mv -f -- "$json_tmp" "$2"; mv -f -- "$header_tmp" "$3"; trap - EXIT',
    "govee-save", dir, kFile, hFile
  ]
}

// Shell command to remove both key files.
function clearKeyCommand(home) {
  return ["rm", "-f", keyFilePath(home), headerFilePath(home)]
}

// ─── Device list ────────────────────────────────────────────────────────────

// Curl command to fetch all devices.
// The API key header is read from the private header file and piped to curl
// via -K - (config from stdin) so it never appears in process arguments.
function listDevicesCommand(headerFile) {
  return [
    "bash", "-c",
    'printf \'header = "Govee-API-Key: %s"\\n\' "$(cat "$1")" | exec curl -fsS --max-time 10 -H "Content-Type: application/json" -K - "$2"',
    "govee", headerFile, API_BASE + "/router/api/v1/user/devices"
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
function deviceStateCommand(headerFile, sku, device) {
  var body = JSON.stringify({
    requestId: generateRequestId(),
    payload: {
      sku: sku,
      device: device
    }
  })
  return [
    "bash", "-c",
    'printf \'header = "Govee-API-Key: %s"\\n\' "$(cat "$1")" | exec curl -sS --max-time 10 -X POST -H "Content-Type: application/json" -d "$2" -K - "$3"',
    "govee", headerFile, body, API_BASE + "/router/api/v1/device/state"
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
function controlCommand(headerFile, sku, device, capability) {
  var body = JSON.stringify({
    requestId: generateRequestId(),
    payload: {
      sku: sku,
      device: device,
      capability: capability
    }
  })
  return [
    "bash", "-c",
    'printf \'header = "Govee-API-Key: %s"\\n\' "$(cat "$1")" | exec curl -fsS --max-time 10 -X POST -H "Content-Type: application/json" -d "$2" -K - "$3"',
    "govee", headerFile, body, API_BASE + "/router/api/v1/device/control"
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

// Convenience: music mode command payload.
// musicMode: integer (mode value from device capabilities)
// sensitivity: 0–100
// autoColor: 1 (auto) or 0 (use rgb)
// rgb: integer 0–16777215 (used when autoColor is 0)
function musicModeCapability(musicMode, sensitivity, autoColor, rgb) {
  return {
    type: "devices.capabilities.music_setting",
    instance: "musicMode",
    value: {
      musicMode: musicMode,
      sensitivity: Math.max(0, Math.min(100, Math.round(sensitivity))),
      autoColor: autoColor ? 1 : 0,
      rgb: autoColor ? 0 : Math.max(0, Math.min(16777215, Math.round(rgb)))
    }
  }
}

// Extract music mode options from a device's capability.
// Returns an array of { name, value } or empty array.
function getMusicModeOptions(device) {
  var cap = getCapability(device, "devices.capabilities.music_setting", "musicMode")
  if (!cap || !cap.parameters || !Array.isArray(cap.parameters.fields)) return []
  for (var i = 0; i < cap.parameters.fields.length; i++) {
    var field = cap.parameters.fields[i]
    if (field.fieldName === "musicMode" && Array.isArray(field.options))
      return field.options
  }
  return []
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
function dynamicScenesCommand(headerFile, sku, device) {
  var body = JSON.stringify({
    requestId: generateRequestId(),
    payload: {
      sku: sku,
      device: device
    }
  })
  return [
    "bash", "-c",
    'printf \'header = "Govee-API-Key: %s"\\n\' "$(cat "$1")" | exec curl -sS --max-time 10 -X POST -H "Content-Type: application/json" -d "$2" -K - "$3"',
    "govee", headerFile, body, API_BASE + "/router/api/v1/device/scenes"
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

// Check if a device is a fan.
function isFan(device) {
  return device && device.type === "devices.types.fan"
}

// Filter the full device list to controllable devices (lights + fans + anything with power).
// Excludes device groups (BaseGroup, SameModeGroup, DreamViewScenic, etc.)
function filterControllable(devices) {
  var result = []
  for (var i = 0; i < devices.length; i++) {
    var dev = devices[i]
    // Skip groups — they have no real device type or use group SKUs
    if (!dev.type || dev.type === "")
      continue
    if (dev.sku === "BaseGroup" || dev.sku === "SameModeGroup" || dev.sku === "DreamViewScenic")
      continue
    if (hasCapability(dev, "devices.capabilities.on_off", "powerSwitch"))
      result.push(dev)
  }
  return result
}

// ─── Fan capability helpers ─────────────────────────────────────────────────

// Convenience: oscillation toggle command payload.
function oscillationCapability(on) {
  return {
    type: "devices.capabilities.toggle",
    instance: "oscillationToggle",
    value: on ? 1 : 0
  }
}

// Convenience: work mode command payload.
// workMode: integer (1=FanSpeed, 2=Auto, 3=Sleep, 4=Nature, 5=Custom)
// modeValue: integer (speed 1-12 for FanSpeed/Sleep/Nature, 0 for Auto/Custom)
function workModeCapability(workMode, modeValue) {
  return {
    type: "devices.capabilities.work_mode",
    instance: "workMode",
    value: { workMode: workMode, modeValue: modeValue }
  }
}

// Extract work mode options from a device's capability.
// Returns { modes: [{name, value, speeds}], maxSpeed } or null.
function getWorkModeOptions(device) {
  var cap = getCapability(device, "devices.capabilities.work_mode", "workMode")
  if (!cap || !cap.parameters || !Array.isArray(cap.parameters.fields)) return null

  var modeField = null
  var valueField = null
  for (var i = 0; i < cap.parameters.fields.length; i++) {
    if (cap.parameters.fields[i].fieldName === "workMode") modeField = cap.parameters.fields[i]
    if (cap.parameters.fields[i].fieldName === "modeValue") valueField = cap.parameters.fields[i]
  }
  if (!modeField || !Array.isArray(modeField.options)) return null

  var modes = []
  var maxSpeed = 0
  for (var j = 0; j < modeField.options.length; j++) {
    var mode = modeField.options[j]
    var speeds = 0
    // Find matching modeValue options
    if (valueField && Array.isArray(valueField.options)) {
      for (var k = 0; k < valueField.options.length; k++) {
        var vo = valueField.options[k]
        if (vo.name === mode.name && Array.isArray(vo.options)) {
          speeds = vo.options.length
          if (speeds > maxSpeed) maxSpeed = speeds
        }
      }
    }
    modes.push({ name: mode.name, value: mode.value, speeds: speeds })
  }
  return { modes: modes, maxSpeed: maxSpeed }
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
