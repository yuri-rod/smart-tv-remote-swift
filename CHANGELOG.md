# Changelog

## 1.2.0 (2026-10-03)

Toolchain upgrade to Swift 6.1 / full Swift 6 language mode, plus the four most impactful fixes: transport selection, pairing reliability, LG navigation, and SSDP cleanup.

Added:
- `smartcast probe <ip>` reports which remote-control transports answer on one host (Samsung 8002, Roku 8060, Legacy 55000, LG 3001/3000).
- Global `--transport` flag (`tizen`, `legacy`, `roku`, `lg`) for `key`, `text`, and `mute`. Previously `key` always spoke Samsung Tizen even when pointed at an LG or Roku.
- `SmartCast.probe(ip:)` and `DeviceTransport(cliName:)` public API.
- `connectAndWait()` / `ensureConnected()` (Samsung) and `ensurePaired()` (LG): every send path now waits for the pairing handshake instead of firing into a half-open socket.
- LG D-pad and digit keys (`UP DOWN LEFT RIGHT ENTER BACK HOME MENU INFO 0-9`) work over the pointer input socket with request/response correlation. Media keys keep their direct `ssap://` URIs.

Fixed:
- LG handshake read only the first frame and marked the TV paired before the `registered` message arrived; it now waits for the client key (with a fast path for already-paired clients).
- SSDP scan leaked its UDP connections; they are now retained and cancelled when the scan ends.
- `String(cString:)` deprecation warning in the subnet sweep.

Changed:
- Swift tools 5.9 to 6.1, full Swift 6 language mode. Requirements are now Swift 6.1+ and Xcode 16.3+.
- CI runner `macos-14` to `macos-15` with default Xcode (14 is retired in November 2026).
- Removed the unused `import Combine` from DeviceScanner.
- Test suite grows from 9 to 12 tests.

## 1.1.1

- Universal release build fix, covered by a CI step so a tag can no longer ship a broken binary.
- Homebrew formula points at the v1.1.1 tarball with its sha256.

## 1.1.0

- LG webOS SSAP transport, async `@main` CLI, volume and toast controls.

## 1.0.0

- Initial SmartCastKit framework release: Samsung Tizen and Legacy, Roku ECP, DLNA casting, SSDP discovery, Wake-on-LAN.
