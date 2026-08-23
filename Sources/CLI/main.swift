import Foundation
import SmartCastKit

let version = "1.0.0"

func printUsage() {
    let help = """
    smartcast v\(version) - Smart TV discovery, remote control, and media casting CLI

    USAGE:
        smartcast <subcommand> [arguments]

    SUBCOMMANDS:
        scan                          Discover all Smart TVs and media renderers on LAN
        key <ip> <key_name>           Send remote control key (power, volup, voldown, mute, home, etc.)
        text <ip> <string>            Inject text into active input field
        launch <ip> <app_id>          Launch app by ID (e.g. org.tizen.netflix-app or 12 for Roku)
        cast <ip> <video_url>         Cast video stream URL via DLNA
        wake <mac_address>            Send Wake-on-LAN magic packet to wake TV
        version                       Print version information

    EXAMPLES:
        smartcast scan
        smartcast key 192.168.1.50 volup
        smartcast text 192.168.1.50 "Avatar 4K"
        smartcast cast 192.168.1.50 http://192.168.1.100:8096/movie.mp4
        smartcast wake AA:BB:CC:DD:EE:FF
    """
    print(help)
}

func parseKey(_ name: String) -> RemoteKey? {
    switch name.lowercased() {
    case "power": return .power
    case "poweroff": return .powerOff
    case "volup", "volumeup", "volume_up": return .volumeUp
    case "voldown", "volumedown", "volume_down": return .volumeDown
    case "mute": return .mute
    case "up": return .up
    case "down": return .down
    case "left": return .left
    case "right": return .right
    case "enter", "select", "ok": return .enter
    case "back", "return": return .back
    case "home": return .home
    case "menu": return .menu
    case "info": return .info
    case "play": return .play
    case "pause": return .pause
    case "playpause": return .playPause
    case "stop": return .stop
    case "rewind", "rev": return .rewind
    case "ff", "fastforward", "fwd": return .fastForward
    case "chup", "channelup": return .channelUp
    case "chdown", "channeldown": return .channelDown
    default:
        if let num = Int(name), (0...9).contains(num) {
            return .number(num)
        }
        return .custom(name)
    }
}

func runCLI() async {
    let args = Array(CommandLine.arguments.dropFirst())

    guard let command = args.first else {
        printUsage()
        exit(0)
    }

    switch command.lowercased() {
    case "scan", "discover", "list":
        print("Scanning local network for Smart TVs and media renderers (timeout 4s)...")
        let devices = await SmartCast.scan(timeout: 4.0)

        if devices.isEmpty {
            print("No devices discovered on local network.")
            return
        }

        print("\nDiscovered \(devices.count) device(s):")
        print("--------------------------------------------------------------------------------")
        print(String(format: "%-16s | %-24s | %-16s | %s", "IP ADDRESS", "NAME", "MANUFACTURER", "TRANSPORTS"))
        print("--------------------------------------------------------------------------------")
        for d in devices {
            let transports = d.supportedTransports.map { $0.rawValue }.joined(separator: ", ")
            let mfg = d.manufacturer ?? "-"
            print(String(format: "%-16s | %-24s | %-16s | %s", d.ip, String(d.name.prefix(24)), String(mfg.prefix(16)), transports))
        }
        print("--------------------------------------------------------------------------------\n")

    case "key", "press":
        guard args.count >= 3 else {
            print("Error: Missing IP address or key name.")
            print("Usage: smartcast key <ip> <key_name>")
            exit(1)
        }
        let ip = args[1]
        let keyName = args[2]
        guard let key = parseKey(keyName) else {
            print("Error: Unknown key '\(keyName)'.")
            exit(1)
        }

        let device = Device(ip: ip, name: "Target TV", supportedTransports: [.samsungTizen, .samsungLegacy, .roku])
        guard let remote = SmartCast.remote(for: device) else {
            print("Error: Failed to initialize remote controller for \(ip).")
            exit(1)
        }

        do {
            try await remote.sendKey(key)
            print("Sent key '\(keyName)' to \(ip)")
        } catch {
            print("Error sending key: \(error.localizedDescription)")
            exit(1)
        }

    case "text", "type":
        guard args.count >= 3 else {
            print("Error: Missing IP address or text string.")
            print("Usage: smartcast text <ip> <string>")
            exit(1)
        }
        let ip = args[1]
        let text = args[2]

        let device = Device(ip: ip, name: "Target TV", supportedTransports: [.samsungTizen, .samsungLegacy, .roku])
        guard let remote = SmartCast.remote(for: device) else {
            print("Error: Failed to initialize remote controller for \(ip).")
            exit(1)
        }

        do {
            try await remote.sendText(text)
            print("Injected text '\(text)' to \(ip)")
        } catch {
            print("Error sending text: \(error.localizedDescription)")
            exit(1)
        }

    case "launch", "app":
        guard args.count >= 3 else {
            print("Error: Missing IP address or app ID.")
            print("Usage: smartcast launch <ip> <app_id>")
            exit(1)
        }
        let ip = args[1]
        let appId = args[2]

        let tizen = SamsungTizenClient(ip: ip)
        tizen.connect()

        do {
            try await tizen.launchApp(appId: appId)
            print("Launched app '\(appId)' on \(ip)")
        } catch {
            print("Error launching app: \(error.localizedDescription)")
            exit(1)
        }

    case "cast", "play":
        guard args.count >= 3 else {
            print("Error: Missing IP address or video URL.")
            print("Usage: smartcast cast <ip> <video_url>")
            exit(1)
        }
        let ip = args[1]
        let urlStr = args[2]
        guard let url = URL(string: urlStr) else {
            print("Error: Invalid URL '\(urlStr)'.")
            exit(1)
        }

        let avURL = URL(string: "http://\(ip):\(DLNAEndpoints.defaultAVPort(for: ip))/AVTransport/control") ?? URL(string: "http://\(ip):52235/upnp/control/AVTransport1")!
        let endpoints = DLNAEndpoints(avTransport: avURL)
        let device = Device(ip: ip, name: "Target TV", supportedTransports: [.dlna], dlnaEndpoints: endpoints)

        guard let caster = SmartCast.caster(for: device) else {
            print("Error: Failed to initialize media caster for \(ip).")
            exit(1)
        }

        let media = MediaItem(url: url, title: "SmartCast Video Stream")
        do {
            try await caster.play(media: media)
            print("Streaming '\(urlStr)' to \(ip)")
        } catch {
            print("Error casting media: \(error.localizedDescription)")
            exit(1)
        }

    case "wake", "wol":
        guard args.count >= 2 else {
            print("Error: Missing MAC address.")
            print("Usage: smartcast wake <mac_address>")
            exit(1)
        }
        let mac = args[1]
        do {
            try await WakeOnLAN.wake(macAddress: mac)
            print("Broadcasted Wake-on-LAN magic packet for \(mac)")
        } catch {
            print("Error waking device: \(error.localizedDescription)")
            exit(1)
        }

    case "version", "--version", "-v":
        print("smartcast v\(version)")

    case "help", "--help", "-h":
        printUsage()

    default:
        print("Error: Unknown subcommand '\(command)'.")
        printUsage()
        exit(1)
    }
}

extension DLNAEndpoints {
    static func defaultAVPort(for ip: String) -> UInt16 {
        return 52235
    }
}

let sema = DispatchSemaphore(value: 0)
Task {
    await runCLI()
    sema.signal()
}
sema.wait()
