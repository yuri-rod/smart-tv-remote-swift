# Launch Distribution Plan

## 1. Hacker News (Show HN)

**Title:**
`Show HN: SmartCast – Control Smart TVs and cast local media from your terminal in pure Swift`

**URL:**
`https://github.com/yuri-rod/smart-tv-remote-swift`

**Body:**
```text
Hey HN,

I got tired of vendor apps and bloated multi-gigabyte bridges just to send a volume command or cast a video stream to my TV on the local network.

Most open-source Smart TV libraries for Apple platforms are either old Objective-C abandonware, Node.js daemons, or single-brand Python scripts.

I built SmartCastKit (and a standalone `smartcast` CLI) in pure Swift with zero third-party dependencies. It runs on macOS, iOS, tvOS, and watchOS.

What it does:
- LAN Discovery: Combines SSDP M-SEARCH multicast with an active /24 subnet unicast fallback (works around iOS multicast sandbox throttles).
- Samsung TVs (2016+ Tizen): WebSocket port 8002 protocol with persistent token pairing, key simulation, text input injection, and app launch.
- Samsung TVs (Pre-2015): Wire protocol frames over raw TCP port 55000.
- Roku: ECP HTTP integration for keys, app listing, and deep links.
- DLNA / UPnP: Full DIDL-Lite v1.0 XML builder with SOAP AVTransport (Play, Pause, Seek, status polling) and RenderingControl volume.
- Wake-on-LAN: UDP magic packet generator (port 9) to power on sleeping sets.

Quick install via Homebrew:
$ brew install yuri-rod/tap/smartcast
$ smartcast scan
$ smartcast key 192.168.1.50 volup
$ smartcast cast 192.168.1.50 http://.../video.mp4

Code: https://github.com/yuri-rod/smart-tv-remote-swift

Feedback and PRs welcome!
```

---

## 2. Reddit (r/selfhosted, r/commandline, r/swift)

**Title:**
`I built smartcast: A zero-dependency Swift CLI & framework to discover, remote control, and cast media to Samsung, Roku, and DLNA TVs`

**Body:**
```text
Hi everyone,

I wanted a clean, single-binary way to discover Smart TVs on my local network, send remote commands, and stream media files directly from the command line without opening vendor apps or running heavy bridge servers.

I created `smartcast` (and the underlying `SmartCastKit` Swift package).

Features:
- Fast LAN scanning (SSDP multicast + /24 subnet sweep fallback)
- Samsung Tizen 2016+ (WebSocket 8002 with token pairing & text injection)
- Samsung Legacy pre-2015 (port 55000 TCP frames)
- Roku (ECP protocol)
- DLNA / UPnP (SOAP AVTransport & RenderingControl)
- Wake-on-LAN magic packet support
- Pure Swift, zero external dependencies

Installation:
brew install yuri-rod/tap/smartcast
# or build from source:
git clone https://github.com/yuri-rod/smart-tv-remote-swift.git
cd smart-tv-remote-swift && swift build -c release

Repo: https://github.com/yuri-rod/smart-tv-remote-swift
```

---

## 3. Twitter / X Post

```text
Announcing smartcast: A zero-dependency Swift CLI to discover, remote control, and cast media to Samsung, Roku, and DLNA TVs on your LAN.

- SSDP + Subnet scan
- Samsung Tizen WSS 8002 & Legacy TCP 55000
- Roku ECP
- DLNA AVTransport
- Wake-on-LAN

Available on GitHub:
https://github.com/yuri-rod/smart-tv-remote-swift
```
