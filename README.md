# SmartCastKit

A lightweight, zero-dependency Swift framework for Smart TV discovery, remote control, and media casting across iOS, macOS, tvOS, and watchOS.

## Overview

SmartCastKit provides a unified API to discover local network TVs and media renderers, send remote control keystrokes, inject text, launch apps, and stream media via DLNA.

Supported protocols and devices:
- Samsung Smart TVs (2016+ Tizen OS): WebSocket protocol on port 8002 with token pairing, key simulation, text input, and app launch.
- Samsung Smart TVs (Pre-2015 Legacy): Binary wire protocol over TCP port 55000.
- Roku TVs and Streaming Sticks: External Control Protocol (ECP) over HTTP for keypresses, app listing, and deep links.
- DLNA / UPnP Media Renderers: DIDL-Lite v1.0 XML metadata generation, SOAP AVTransport (Play, Pause, Stop, Seek, status polling), and RenderingControl volume.
- Wake-on-LAN: UDP magic packet generator (port 9) to power on sleeping devices.
- Network Discovery: SSDP multicast discovery (M-SEARCH) combined with active subnet unicast probing.

## Requirements

- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+
- Swift 5.9+ / Swift 6.0
- Xcode 15.0+

## Installation

Add SmartCastKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yuri-rod/smart-tv-remote-swift.git", from: "1.0.0")
]
```

Or in Xcode: **File** > **Add Package Dependencies...** and enter the repository URL.

## Usage

### Discover Devices

```swift
import SmartCastKit

let devices = await SmartCast.scan(timeout: 4.0)

for device in devices {
    print("Found \(device.name) at \(device.ip)")
    print("Supported transports: \(device.supportedTransports)")
}
```

### Remote Control

```swift
guard let device = devices.first,
      let remote = SmartCast.remote(for: device) else { return }

try await remote.sendKey(.power)
try await remote.sendKey(.volumeUp)
try await remote.sendKey(.home)
try await remote.sendKey(.enter)

// Inject text into active search field
try await remote.sendText("Sci-Fi Movies")
```

### Media Casting (DLNA)

```swift
guard let device = devices.first(where: { $0.supportedTransports.contains(.dlna) }),
      let caster = SmartCast.caster(for: device) else { return }

let media = MediaItem(
    url: URL(string: "http://192.168.1.100:8096/stream.mp4")!,
    title: "Sample Video",
    mimeType: "video/mp4",
    posterURL: URL(string: "http://192.168.1.100:8096/poster.jpg")!
)

try await caster.play(media: media)
try await caster.setVolume(30)
try await caster.seek(to: 120.0)

let status = try await caster.playbackStatus()
print("Playback state: \(status.state), Position: \(status.positionSeconds)s")
```

### Samsung Tizen with Persistent Token

```swift
let tizen = SamsungTizenClient(ip: "192.168.1.50", appName: "SmartCastKit", token: savedToken)

tizen.onTokenReceived = { newToken in
    UserDefaults.standard.set(newToken, forKey: "samsung_tv_token")
}

tizen.connect()
try await tizen.launchApp(appId: "org.tizen.netflix-app")
```

### Wake-on-LAN

```swift
try await WakeOnLAN.wake(macAddress: "AA:BB:CC:DD:EE:FF")
```

## Architecture

- `Core/Models.swift`: Unified device representations, transport flags, remote keys, media descriptors, and playback status.
- `Discovery/DeviceScanner.swift`: SSDP M-SEARCH sweep and subnet unicast probing.
- `Transports/SamsungTizenTransport.swift`: WebSocket port 8002 client with token authentication.
- `Transports/SamsungLegacyTransport.swift`: Port 55000 TCP binary frame serializer.
- `Transports/DLNATransport.swift`: SOAP AVTransport and RenderingControl client with DIDL-Lite builder.
- `Transports/RokuTransport.swift`: ECP HTTP client.
- `Utilities/WakeOnLAN.swift`: Magic packet generator.
- `Utilities/LocalTrustDelegate.swift`: Self-signed TLS evaluator for local appliances.

## License

MIT License. See [LICENSE](LICENSE) for details.
