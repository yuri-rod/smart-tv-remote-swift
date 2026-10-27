# SmartCastKit and smartcast

A Swift library and macOS CLI for discovering TVs, sending remote commands and controlling DLNA playback on a local network.

Use it to build a remote-control app or script a TV you own. The package has no external dependencies: it uses Foundation, Network and Security frameworks. Protocol clients are separate from the device model and CLI, so applications can use a specific transport directly.

## Build and try it

Use a Swift 6.1 or later toolchain. The package declares macOS 12, iOS 15, tvOS 15 and watchOS 8 minimum versions; CI builds and tests on macOS.

```sh
git clone https://github.com/yuri-rod/smart-tv-remote-swift.git
cd smart-tv-remote-swift
swift build -c release
"$(swift build -c release --show-bin-path)/smartcast" version
```

Output:

```text
smartcast v1.2.1
```

Run the CLI from that build directory, or copy the binary to a directory on your `PATH`. On macOS, tests need Xcode's XCTest framework. If Command Line Tools is selected, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for the build and test commands.

Before contacting a TV, run the offline tests:

```sh
swift test
python3 Tests/cli_smoke.py
```

The Swift tests exercise protocol frames, metadata, pairing response parsing and transport selection. The CLI tests use HTTP fixtures on `127.0.0.1:52235` and `127.0.0.1:8060`; those ports must be free. They verify both successful responses and rejected commands without scanning the network or requiring a TV.

## Control a TV

Replace the example address with your device's address. Run discovery only on a network you are authorized to scan.

```sh
smartcast probe 192.168.1.50
smartcast --transport roku key 192.168.1.50 home
smartcast --transport lg key 192.168.1.51 up
smartcast --transport tizen key 192.168.1.52 volup
```

`probe` checks known ports on one host. `scan` sends SSDP multicast queries and probes the local IPv4 /24 subnet. An open port is a transport hint, not confirmation of a device's make or capabilities.

`key`, `text` and `mute` default to Samsung Tizen. Use `--transport tizen|legacy|roku|lg` to select another protocol. Samsung and LG may show a pairing prompt. The CLI does not persist pairing tokens between invocations.

| Command | Behavior |
| --- | --- |
| `scan` / `probe <ip>` | Discover devices / probe one host |
| `key <ip> <key>` | Send a remote key, such as `home`, `up`, `volup` or `enter` |
| `text <ip> "text"` | Send text through the selected transport; LG currently displays a toast |
| `mute <ip>` | Toggle mute |
| `launch <ip> <app_id>` | Launch a Samsung Tizen app |
| `apps <ip>` | List Roku apps |
| `cast <ip> <video_url>` | Give a DLNA renderer a media URL |
| `volume <ip> <0-100>` | Set DLNA RenderingControl volume |
| `pause <ip>` / `resume <ip>` / `stop <ip>` | Control DLNA playback |
| `toast <ip> "message"` | Show an LG notification |
| `wake <mac_address>` | Send a Wake-on-LAN packet |

The CLI's DLNA commands use fixed Samsung-style control endpoints on port 52235. For other renderers, use the library with discovered or explicitly supplied `DLNAEndpoints`. The TV must be able to fetch a cast media URL itself; this package does not host or transcode local files.

## Use the library

Add the repository URL in Xcode's package dependencies and select the `SmartCastKit` product, or add it to a Swift package:

```swift
.package(url: "https://github.com/yuri-rod/smart-tv-remote-swift.git", from: "1.2.1")
```

Add `.product(name: "SmartCastKit", package: "smart-tv-remote-swift")` to your target dependencies. A direct client avoids discovery when you already know the device and protocol:

```swift
import SmartCastKit

let roku = RokuClient(ip: "192.168.1.50")
try await roku.sendKey(.home)
let apps = try await roku.queryApps()
for app in apps {
    print("\(app.id): \(app.name)")
}
```

For DLNA, `SmartCast.caster(for:)` uses the device's `dlnaEndpoints`. It supports play, pause, resume, stop, seek, volume and playback status. Samsung and LG clients expose pairing callbacks so an application can persist tokens in its own credential store.

## Implementation and verification

- [Device models and transport preferences](Sources/SmartCastKit/Core/Models.swift) keep discovery results separate from protocol clients.
- [Discovery](Sources/SmartCastKit/Discovery/DeviceScanner.swift) combines SSDP descriptors with TCP port probes.
- [Transport clients](Sources/SmartCastKit/Transports) implement Samsung Tizen, legacy Samsung, Roku, LG webOS and DLNA.
- [Protocol tests](Tests/SmartCastKitTests/SmartCastKitTests.swift) use synthetic frames and messages. [CLI response tests](Tests/cli_smoke.py) verify command exit status against loopback fixtures.
- [CI](.github/workflows/ci.yml) builds, runs both test suites and builds a universal macOS binary. To reproduce the universal build: `swift build -c release --arch arm64 --arch x86_64`.

Contributions should include a fixture or regression test for the protocol behavior being changed. Hardware results should identify the TV model, firmware and command tested. Unit tests do not establish compatibility with every device or Apple platform.

## Operational limits

Use trusted local networks and endpoints. Samsung and LG sessions use a delegate that accepts self-signed certificates without certificate or host pinning; it does not authenticate the TV's identity. Roku, legacy Samsung, DLNA and the current LG default connection use unencrypted protocols.

Discovery assumes a /24 IPv4 network and can take longer than its response-wait timeout. The library declares a Google Cast transport enum but does not implement a Cast client. LG text input currently maps to notifications, and the LG connection builder uses `ws` even when a TLS port is supplied. These are implementation limits, not hardware compatibility guarantees.

Embedding apps must configure their platform's local-network access and transport permissions. Device firmware, pairing settings and network isolation can prevent commands from reaching a TV. Wake-on-LAN also depends on the device's standby network settings.

[MIT license](LICENSE). [Support the project](https://buymeacoffee.com/yurirod).
