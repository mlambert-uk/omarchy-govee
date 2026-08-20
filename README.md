# Govee Lights — Omarchy Shell Plugin

Control your Govee smart lights directly from the Omarchy desktop bar.

## Features

- Discover all Govee light devices on your account
- Toggle power on/off per device
- Adjust brightness with a slider
- Auto-refreshes state every 30 seconds while the panel is open
- Middle-click the bar icon to force refresh

## Installation

```bash
omarchy plugin add https://github.com/mlambert-uk/omarchy-govee.git --enable
```

Or clone locally for development:

```bash
cp -r /path/to/omarchy-govee ~/.config/omarchy/plugins/mlambert-uk.govee
```

Then enable it:

```bash
omarchy plugin enable mlambert-uk.govee
```

## Setup

1. Open the Govee Home app on your phone
2. Go to your profile → **Settings**
3. Tap **About Us** → **Apply for API Key**
4. Copy the API key you receive via email
5. Click the lightbulb icon in the bar — the plugin will prompt you to paste your key

The key is stored locally at `~/.local/state/omarchy/settings/govee.json`.

## Usage

- **Click** the bar icon to open the panel
- **Middle-click** the bar icon to refresh device states
- **Toggle** the switch next to each device to turn it on/off
- **Drag** the brightness slider to adjust (only active when the device is on)
- **Reset** link at the bottom of the panel clears your stored API key

You can also toggle the panel via IPC:

```bash
omarchy-shell shell toggle mlambert-uk.govee
```

## File Structure

```
mlambert-uk.govee/
├── manifest.json      # Plugin metadata
├── BarWidget.qml      # Bar icon entry point
├── Panel.qml          # Main panel UI (setup flow + device list)
├── DeviceCard.qml     # Per-device card (power toggle + brightness)
├── GoveeApi.js        # API helpers (curl commands, response parsing)
└── README.md          # This file
```

## API Reference

This plugin uses the [Govee Developer API v2](https://developer.govee.com/docs/getting-started):

- `GET /router/api/v1/user/devices` — list devices and capabilities
- `GET /router/api/v1/device/state` — query device state
- `POST /router/api/v1/device/control` — send commands

Rate limits: 10 req/min for device list, 10 req/min/device for control, 30 req/min/device for state.

## Roadmap

- [ ] RGB color picker
- [ ] Color temperature slider
- [ ] Scene/effect selector
- [ ] Music mode activation
- [ ] Group controls (all on/off, set all to same color)
- [ ] Device naming/grouping

## License

MIT
