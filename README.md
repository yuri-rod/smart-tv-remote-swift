# smartcast & SmartCastKit

A lightweight, zero-dependency Swift CLI and framework for Smart TV discovery, remote control, and media casting across iOS, macOS, tvOS, and watchOS.

```bash
# Discover TVs, control volume, and cast media from your terminal
$ smartcast scan
$ smartcast key 192.168.1.50 volup
$ smartcast text 192.168.1.50 "Avatar 4K"
$ smartcast cast 192.168.1.50 http://192.168.1.100:8096/stream.mp4
```

---

## Highlights

- Zero external dependencies. Built entirely with Swift standard library, `Network.framework`, and `Foundation`.
- Resilient network discovery. Combines SSDP multicast M-SEARCH with automatic local /24 subnet unicast probing.
- Samsung Smart TVs (2016+ Tizen OS). WebSocket protocol on port 8002 with token pairing, key simulation, text input injection, and app launch.
- Samsung Smart TVs (Pre-2015 Legacy). Binary wire protocol frame serialization over raw TCP port 55000.
- Roku TVs and Streaming Sticks. External Control Protocol (ECP) over HTTP for keypresses, app listing, and deep links.
- DLNA / UPnP Media Renderers. DIDL-Lite v1.0 XML metadata generation, SOAP AVTransport (Play, Pause, Stop, Seek, status polling), and RenderingControl volume.
- Wake-on-LAN. UDP magic packet generator (port 9) to power on sleeping devices.
- Swift 6 Concurrency. Fully Sendable, actor-isolated scanner, and built with modern async/await.

---

## CLI Installation

Install the `smartcast` command-line tool via Homebrew:

```bash
brew tap yuri-rod/tap https://github.com/yuri-rod/smart-tv-remote-swift
brew install smartcast
```

Or build directly from source:

```bash
git clone https://github.com/yuri-rod/smart-tv-remote-swift.git
cd smart-tv-remote-swift
swift build -c release
cp .build/release/smartcast /usr/local/bin/
```

---

## CLI Usage

### Discover Local Devices

```bash
smartcast scan
```

Output:
```text
Discovered 2 device(s):
--------------------------------------------------------------------------------
IP ADDRESS       | NAME                     | MANUFACTURER     | TRANSPORTS
--------------------------------------------------------------------------------
192.168.1.50     | Living Room TV           | Samsung          | samsung_tizen, dlna
192.168.1.65     | Bedroom Roku             | Roku             | roku
--------------------------------------------------------------------------------
```

### Remote Control & Text Injection

```bash
# Send keys
smartcast key 192.168.1.50 power
smartcast key 192.168.1.50 volup
smartcast key 192.168.1.50 voldown
smartcast key 192.168.1.50 home
smartcast key 192.168.1.50 enter

# Inject text into search fields
smartcast text 192.168.1.50 "Interstellar 4K"
```

### Stream / Cast Media (DLNA)

```bash
smartcast cast 192.168.1.50 http://192.168.1.100:8096/movie.mp4
```

### Wake-on-LAN

```bash
smartcast wake AA:BB:CC:DD:EE:FF
```

---

## Swift Package Installation

Add `SmartCastKit` as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yuri-rod/smart-tv-remote-swift.git", from: "1.0.0")
]
```

Or in Xcode: **File** > **Add Package Dependencies...** and enter the repository URL.

---

## Swift Library Usage

### 1. Discover Devices on LAN

```swift
import SmartCastKit

let devices = await SmartCast.scan(timeout: 4.0)

for device in devices {
    print("Found \(device.name) at \(device.ip)")
    print("Supported transports: \(device.supportedTransports)")
}
```

### 2. Send Remote Keys

```swift
guard let device = devices.first,
      let remote = SmartCast.remote(for: device) else { return }

try await remote.sendKey(.power)
try await remote.sendKey(.volumeUp)
try await remote.sendKey(.home)
try await remote.sendKey(.enter)

try await remote.sendText("Sci-Fi Movies")
```

### 3. Cast Video / Media (DLNA)

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

### 4. Samsung Tizen Token Pairing

```swift
let tizen = SamsungTizenClient(ip: "192.168.1.50", appName: "SmartCastKit", token: savedToken)

tizen.onTokenReceived = { newToken in
    UserDefaults.standard.set(newToken, forKey: "samsung_tv_token")
}

tizen.connect()
try await tizen.launchApp(appId: "org.tizen.netflix-app")
```

---

## Architecture

- `Core/Models.swift`: Unified device representations, transport flags, remote keys, media descriptors, and playback status.
- `Discovery/DeviceScanner.swift`: SSDP M-SEARCH sweep and subnet unicast probing.
- `Transports/SamsungTizenTransport.swift`: WebSocket port 8002 client with token authentication.
- `Transports/SamsungLegacyTransport.swift`: Port 55000 TCP binary frame serializer.
- `Transports/DLNATransport.swift`: SOAP AVTransport and RenderingControl client with DIDL-Lite builder.
- `Transports/RokuTransport.swift`: ECP HTTP client.
- `Utilities/WakeOnLAN.swift`: Magic packet generator.
- `Utilities/LocalTrustDelegate.swift`: Self-signed TLS evaluator for local appliances.
- `CLI/main.swift`: High-performance terminal interface.

---

## Requirements

- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+
- Swift 5.9+ / Swift 6.0
- Xcode 15.0+

---

## License

MIT License. See [LICENSE](LICENSE) for details.
