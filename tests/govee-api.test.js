"use strict"

const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const vm = require("node:vm")
const { spawnSync } = require("node:child_process")

const source = fs.readFileSync(path.join(__dirname, "..", "GoveeApi.js"), "utf8")
const api = {}
vm.createContext(api)
vm.runInContext(source, api, { filename: "GoveeApi.js" })

function plain(value) {
  return JSON.parse(JSON.stringify(value))
}

assert.equal(api.validateApiKey("abc-123-DEF"), "")
assert.notEqual(api.validateApiKey(""), "")
assert.notEqual(api.validateApiKey("key\nnext"), "")
assert.notEqual(api.validateApiKey('key"'), "")
assert.notEqual(api.validateApiKey("a".repeat(129)), "")
assert.equal(api.parseKeyFile('{"apiKey":"  abc-123  "}'), "abc-123")
assert.equal(api.parseKeyFile("not json"), "")
assert.equal(api.responseError('{"code":200,"data":[]}'), "")
assert.match(api.responseError('{"code":401}'), /Authentication/)
assert.match(api.responseError('{"code":429}'), /Rate limited/)
assert.match(api.responseError("not json"), /Invalid response/)

assert.deepEqual(plain(api.brightnessCapability(-4)), {
  type: "devices.capabilities.range",
  instance: "brightness",
  value: 1
})
assert.equal(api.brightnessCapability(101).value, 100)
assert.equal(api.colorRgbCapability(-1).value, 0)
assert.equal(api.colorRgbCapability(0x1000000).value, 0xffffff)
assert.equal(api.colorTemperatureCapability(1000).value, 2000)
assert.equal(api.colorTemperatureCapability(10000).value, 9000)

const state = api.parseDeviceState(JSON.stringify({
  code: 200,
  payload: {
    capabilities: [
      { instance: "powerSwitch", state: { value: 1 } },
      { instance: "online", state: { value: false } }
    ]
  }
}))
assert.deepEqual(plain(state), { powerSwitch: 1, online: false })
assert.equal(api.parseDeviceState('{"code":500}'), null)
assert.equal(api.parseDeviceState("not json"), null)

const secret = "secret-key-123"
for (const command of [
  api.listDevicesCommand("/private/header"),
  api.deviceStateCommand("/private/header", "sku", "device"),
  api.controlCommand("/private/header", "sku", "device", api.powerCapability(true)),
  api.dynamicScenesCommand("/private/header", "sku", "device")
]) {
  assert.equal(command.includes(secret), false)
  assert.match(command[2], /exec curl -q --proto =https/)
  assert.doesNotMatch(command[2], /Govee-API-Key: [a-zA-Z0-9-]+/)
}

const tempHome = fs.mkdtempSync(path.join(os.tmpdir(), "omarchy-govee-test-"))
try {
  const saveCommand = api.saveKeyCommand(tempHome)
  assert.equal(saveCommand.includes(secret), false)
  const saved = spawnSync(saveCommand[0], saveCommand.slice(1), {
    input: `${secret}\n`,
    encoding: "utf8"
  })
  assert.equal(saved.status, 0, saved.stderr)

  const keyFile = api.keyFilePath(tempHome)
  const headerFile = api.headerFilePath(tempHome)
  assert.equal(fs.statSync(keyFile).mode & 0o777, 0o600)
  assert.equal(fs.statSync(headerFile).mode & 0o777, 0o600)
  assert.equal(JSON.parse(fs.readFileSync(keyFile, "utf8")).apiKey, secret)
  assert.equal(fs.readFileSync(headerFile, "utf8"), secret)

  const rejected = spawnSync(saveCommand[0], saveCommand.slice(1), {
    input: "unsafe/key\n",
    encoding: "utf8"
  })
  assert.notEqual(rejected.status, 0)
} finally {
  fs.rmSync(tempHome, { recursive: true, force: true })
}

console.log("Govee API helper tests passed")
