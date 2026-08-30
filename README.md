# SmartCastKit & smartcast 📺⚡

```
  ███████╗███╗   ███╗ █████╗ ██████╗ ████████╗ ██████╗ █████╗ ███████╗████████╗
  ██╔════╝████╗ ████║██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔══██╗██╔════╝╚══██╔══╝
  ███████╗██╔████╔██║███████║██████╔╝   ██║   ██║     ███████║███████╗   ██║   
  ╚════██║██║╚██╔╝██║██╔══██║██╔══██╗   ██║   ██║     ██╔══██║╚════██║   ██║   
  ███████║██║ ╚═╝ ██║██║  ██║██║  ██║   ██║   ╚██████╗██║  ██║███████║   ██║   
  ╚══════╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝╚══════╝   ╚═╝   
```

**Lightweight, zero-dependency Swift CLI and framework for Smart TV discovery, remote control, and media casting across iOS, macOS, tvOS, and watchOS.**

[![Version](https://img.shields.io/badge/version-1.1.1-blue.svg)](Package.swift)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Swift: 5.9 | 6.0](https://img.shields.io/badge/swift-5.9%20%7C%206.0-orange.svg)](https://swift.org)
[![Platform: iOS | macOS | tvOS | watchOS](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS-lightgrey.svg)]()
[![Tests: 9 passed](https://img.shields.io/badge/tests-9%20passed-brightgreen.svg)]()
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Donate-yellow.svg?style=flat&logo=buy-me-a-coffee)](https://buymeacoffee.com/yurirod)

```bash
# Discover TVs, control volume, and cast media from your terminal
$ smartcast scan
$ smartcast key 192.168.1.50 volup
$ smartcast text 192.168.1.50 "Avatar 4K"
$ smartcast cast 192.168.1.50 http://192.168.1.100:8096/stream.mp4
$ smartcast volume 192.168.1.50 25
```

---

## Highlights

- **Zero external dependencies:** Built entirely with Swift standard library, `Network.framework`, and `Foundation`.
- **Resilient network discovery:** Combines SSDP multicast M-SEARCH with automatic local /24 subnet unicast probing.
- **Samsung Smart TVs (2016+ Tizen OS):** WebSocket protocol on port 8002 with token pairing, key simulation, text input injection, and app launch.
- **Samsung Smart TVs (Pre-2015 Legacy):** Binary wire protocol frame serialization over raw TCP port 55000.
- **LG Smart TVs (webOS 3.0+):** SSAP WebSocket protocol on port 3000/3001 with pairing keys, volume controls, toast messages, and app launching.
- **Roku TVs and Streaming Sticks:** External Control Protocol (ECP) over HTTP for keypresses, app listing, and deep links.
- **DLNA / UPnP Media Renderers:** DIDL-Lite v1.0 XML metadata generation, SOAP AVTransport (Play, Pause, Stop, Seek, status polling), and RenderingControl volume.
- **Wake-on-LAN:** UDP magic packet generator (port 9) to power on sleeping devices.
- **Swift 6 Concurrency:** Fully Sendable, actor-isolated scanner, and built with modern async/await and `@main` CLI entrypoint.

---

## CLI Installation

### Homebrew (macOS)

```bash
brew tap yuri-rod/tap https://github.com/yuri-rod/smart-tv-remote-swift
brew install smartcast
```

### Build from Source

```bash
git clone https://github.com/yuri-rod/smart-tv-remote-swift.git
cd smart-tv-remote-swift
swift build -c release
cp .build/release/smartcast /usr/local/bin/
```

---

## CLI Command Reference

| Command | Arguments | Description | Example |
| :--- | :--- | :--- | :--- |
| `scan` | none | Scans local network for TVs and media renderers | `smartcast scan` |
| `key` | `<ip> <key_name>` | Sends remote keypress to TV | `smartcast key 192.168.1.50 volup` |
| `text` | `<ip> <string>` | Injects text into active TV search/input field | `smartcast text 192.168.1.50 "Sci-Fi"` |
| `launch` | `<ip> <app_id>` | Launches app by ID | `smartcast launch 192.168.1.50 org.tizen.netflix-app` |
| `apps` | `<ip>` | Lists installed apps on device (Roku) | `smartcast apps 192.168.1.50` |
| `volume` | `<ip> <0-100>` | Sets playback/rendering volume level | `smartcast volume 192.168.1.50 25` |
| `mute` | `<ip>` | Toggles TV mute state | `smartcast mute 192.168.1.50` |
| `cast` | `<ip> <video_url>` | Casts media URL via DLNA AVTransport | `smartcast cast 192.168.1.50 http://.../video.mp4` |
| `pause` | `<ip>` | Pauses active DLNA media playback | `smartcast pause 192.168.1.50` |
| `resume` | `<ip>` | Resumes paused DLNA media playback | `smartcast resume 192.168.1.50` |
| `stop` | `<ip>` | Stops active DLNA media playback | `smartcast stop 192.168.1.50` |
| `toast` | `<ip> <msg>` | Shows on-screen notification toast (LG webOS) | `smartcast toast 192.168.1.50 "Dinner is ready"` |
| `wake` | `<mac_address>` | Broadcasts Wake-on-LAN magic packet | `smartcast wake AA:BB:CC:DD:EE:FF` |
| `version` | none | Prints version information | `smartcast version` |

### Supported Remote Keys

| Key Name | Aliases | Description |
| :--- | :--- | :--- |
| `power` | `poweroff` | Power toggle / Off |
| `volup` | `volumeup`, `volume_up` | Volume Up |
| `voldown` | `volumedown`, `volume_down` | Volume Down |
| `mute` | | Toggle Mute |
| `up`, `down`, `left`, `right` | | Directional D-Pad navigation |
| `enter` | `select`, `ok` | Select / OK |
| `back` | `return` | Back / Return |
| `home` | | Return to Smart TV Home menu |
| `menu` | `info` | Settings menu or info overlay |
| `play`, `pause`, `playpause` | | Media playback controls |
| `stop` | | Stop playback |
| `rewind`, `rev` | | Rewind media |
| `ff`, `fastforward`, `fwd` | | Fast forward media |
| `chup`, `chdown` | | Channel Up / Down |
| `0` to `9` | | Number keys |

---

## Swift Package Installation

Add `SmartCastKit` as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yuri-rod/smart-tv-remote-swift.git", from: "1.0.0")
]
```

Or in Xcode: **File** > **Add Package Dependencies...** and enter the repository URL.

### iOS Configuration (`Info.plist`)

When integrating `SmartCastKit` into an iOS or iPadOS application, Apple requires the Local Network Privacy permission. Add the following keys to your app's `Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app requires local network access to discover and control Smart TVs.</string>
<key>NSBonjourServices</key>
<array>
    <string>_googlecast._tcp</string>
    <string>_airplay._tcp</string>
</array>
```

---

## Swift Library Usage

### 1. Discover Devices on Local Network

```swift
import SmartCastKit

// Scan for all Smart TVs, DLNA renderers, and Roku devices
let devices = await SmartCast.scan(timeout: 4.0)

for device in devices {
    print("Found \(device.name) at \(device.ip)")
    print("Manufacturer: \(device.manufacturer ?? "Unknown")")
    print("Supported transports: \(device.supportedTransports)")
}
```

### 2. Send Remote Keystrokes & Text

```swift
guard let device = devices.first,
      let remote = SmartCast.remote(for: device) else { return }

// Send physical key events
try await remote.sendKey(.power)
try await remote.sendKey(.volumeUp)
try await remote.sendKey(.home)
try await remote.sendKey(.enter)

// Send text to active on-screen search inputs (YouTube, browser, etc.)
try await remote.sendText("Avatar 4K HDR")
```

### 3. Cast Video / Media (DLNA AVTransport)

```swift
guard let device = devices.first(where: { $0.supportedTransports.contains(.dlna) }),
      let caster = SmartCast.caster(for: device) else { return }

let media = MediaItem(
    url: URL(string: "http://192.168.1.100:8096/videos/movie.mp4")!,
    title: "Interstellar",
    mimeType: "video/mp4",
    posterURL: URL(string: "http://192.168.1.100:8096/posters/movie.jpg")!,
    durationSeconds: 10140.0
)

// Start playback
try await caster.play(media: media)

// Control playback
try await caster.setVolume(25)
try await caster.seek(to: 3600.0) // 1 hour mark
try await caster.pause()

// Poll live status
let status = try await caster.playbackStatus()
print("Playback state: \(status.state), Position: \(status.positionSeconds)s")
```

### 4. Samsung Tizen Pairing with Token Store

When connecting to a Samsung Tizen TV for the first time, an authorization prompt appears on the TV screen. Once accepted, the TV issues an authorization token. Save this token to bypass future pairing prompts:

```swift
let savedToken = UserDefaults.standard.string(forKey: "samsung_tv_token")
let tizen = SamsungTizenClient(ip: "192.168.1.50", appName: "MyRemoteApp", token: savedToken)

tizen.onTokenReceived = { newToken in
    UserDefaults.standard.set(newToken, forKey: "samsung_tv_token")
}

tizen.connect()

// Launch installed apps directly
try await tizen.launchApp(appId: "org.tizen.netflix-app")
```

### 5. Wake TV via Wake-on-LAN

```swift
// Send UDP port 9 magic packet
try await WakeOnLAN.wake(macAddress: "AA:BB:CC:DD:EE:FF")
```

---

## Architecture

```text
SmartCastKit
├── Core
│   └── Models.swift                 Unified device model, transport enum, remote keys, media descriptors
├── Discovery
│   └── DeviceScanner.swift          SSDP multicast M-SEARCH combined with /24 subnet probing
├── Transports
│   ├── SamsungTizenTransport.swift  WebSocket port 8002 protocol with token pairing & app launching
│   ├── SamsungLegacyTransport.swift Raw TCP port 55000 binary wire frame serializer
│   ├── DLNATransport.swift          SOAP AVTransport & RenderingControl client with DIDL-Lite metadata
│   └── RokuTransport.swift          HTTP ECP client for keypresses and app launching
├── Utilities
│   ├── LocalTrustDelegate.swift     Self-signed TLS evaluator for local appliances
│   └── WakeOnLAN.swift              102-byte magic packet generator
├── CLI
│   └── main.swift                   High-performance command-line interface
└── SmartCast.swift                  High-level developer facade
```

---

## Troubleshooting

### Device Not Discovered
1. Ensure your Mac or iOS device is on the same local Wi-Fi network and subnet as the TV.
2. If your router uses separate 2.4 GHz and 5 GHz bands with AP isolation enabled, devices on different bands cannot communicate directly.
3. On iOS, verify that Local Network permission has been granted in iOS Settings.

### Samsung TV Pairing & Wake-on-LAN
1. On modern Samsung TVs, navigate to **Settings** > **General** > **Network** > **Expert Settings** and enable:
   - **Power On with Mobile** (required for Wake-on-LAN to work while TV is in standby).
   - **IP Remote** (required for WebSocket port 8002 remote control).
2. If the TV previously rejected connection from your app name, go to **Settings** > **General** > **External Device Manager** > **Device Connection Manager** > **Device List** and remove the rejected client.

---

## Requirements

- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+
- Swift 5.9+ / Swift 6.0
- Xcode 15.0+

---

## Support & Sponsorship

If SmartCastKit or smartcast saved you time or powered your home automation setup, consider buying me a coffee:

<a href="https://buymeacoffee.com/yurirod"><img src="https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=☕&slug=yurirod&button_colour=FFDD00&font_colour=000000&font_family=Inter&outline_colour=000000&coffee_colour=ffffff" /></a>

---

## License

MIT License (c) 2026 Yuri Barreira
