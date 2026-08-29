import Foundation
import SmartCastKit

let version = "1.1.0"

func printUsage() {
    let help = """
    smartcast v\(version) - Smart TV discovery, remote control, and media casting CLI

    USAGE:
        smartcast <subcommand> [arguments]

    SUBCOMMANDS:
        scan                          Discover all Smart TVs and media renderers on LAN
        key <ip> <key_name>           Send remote control key (power, volup, voldown, mute, home, etc.)
        text <ip> <string>            Inject text into active input field
        launch <ip> <app_id>          Launch app by ID (e.g. org.tizen.netflix-app, 12 for Roku, netflix for LG)
        apps <ip>                     List installed applications on device (Roku)
        volume <ip> <0-100>           Set playback/rendering volume level
        mute <ip> [on|off]            Mute or unmute TV audio
        cast <ip> <video_url>         Cast video stream URL via DLNA
        pause <ip>                    Pause active DLNA media playback
        resume <ip>                   Resume paused DLNA media playback
        stop <ip>                     Stop active DLNA media playback
        seek <ip> <seconds>           Seek DLNA media to position in seconds
        toast <ip> <message>          Display on-screen notification toast (LG webOS)
        wake <mac_address>            Send Wake-on-LAN magic packet to wake TV
        version                       Print version information

    EXAMPLES:
        smartcast scan
        smartcast key 192.168.1.50 volup
        smartcast text 192.168.1.50 "Avatar 4K"
        smartcast cast 192.168.1.50 http://192.168.1.100:8096/movie.mp4
        smartcast volume 192.168.1.50 25
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

func dlnaCaster(for ip: String) -> AnyMediaCaster? {
    let avURL = URL(string: "http://\(ip):52235/upnp/control/AVTransport1") ?? URL(string: "http://\(ip):52235/AVTransport/control")!
    let rcURL = URL(string: "http://\(ip):52235/upnp/control/RenderingControl1") ?? URL(string: "http://\(ip):52235/RenderingControl/control")
    let endpoints = DLNAEndpoints(avTransport: avURL, renderingControl: rcURL)
    let device = Device(ip: ip, name: "Target TV", supportedTransports: [.dlna], dlnaEndpoints: endpoints)
    return SmartCast.caster(for: device)
}

@main
struct SmartCastCLI {
    static func main() async {
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

            let device = Device(ip: ip, name: "Target TV", supportedTransports: [.samsungTizen, .lgWebOS, .samsungLegacy, .roku])
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

            let device = Device(ip: ip, name: "Target TV", supportedTransports: [.samsungTizen, .lgWebOS, .samsungLegacy, .roku])
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

        case "apps":
            guard args.count >= 2 else {
                print("Error: Missing IP address.")
                print("Usage: smartcast apps <ip>")
                exit(1)
            }
            let ip = args[1]
            let roku = RokuClient(ip: ip)
            do {
                let apps = try await roku.queryApps()
                print("Found \(apps.count) apps on Roku (\(ip)):")
                for a in apps {
                    print("  [\(a.id)] \(a.name)")
                }
            } catch {
                print("Error querying apps: \(error.localizedDescription)")
                exit(1)
            }

        case "volume", "vol":
            guard args.count >= 3, let level = Int(args[2]) else {
                print("Error: Missing IP or volume level (0-100).")
                print("Usage: smartcast volume <ip> <0-100>")
                exit(1)
            }
            let ip = args[1]
            guard let caster = dlnaCaster(for: ip) else {
                print("Error: Could not initialize media caster for \(ip)")
                exit(1)
            }
            do {
                try await caster.setVolume(level)
                print("Set volume on \(ip) to \(level)%")
            } catch {
                print("Error setting volume: \(error.localizedDescription)")
                exit(1)
            }

        case "mute":
            guard args.count >= 2 else {
                print("Error: Missing IP address.")
                print("Usage: smartcast mute <ip> [on|off]")
                exit(1)
            }
            let ip = args[1]
            let device = Device(ip: ip, name: "Target TV", supportedTransports: [.samsungTizen, .roku, .lgWebOS])
            if let remote = SmartCast.remote(for: device) {
                do {
                    try await remote.sendKey(.mute)
                    print("Toggled mute on \(ip)")
                } catch {
                    print("Error toggling mute: \(error.localizedDescription)")
                }
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

            guard let caster = dlnaCaster(for: ip) else {
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

        case "pause":
            guard args.count >= 2 else {
                print("Usage: smartcast pause <ip>")
                exit(1)
            }
            let ip = args[1]
            if let caster = dlnaCaster(for: ip) {
                try? await caster.pause()
                print("Paused playback on \(ip)")
            }

        case "resume":
            guard args.count >= 2 else {
                print("Usage: smartcast resume <ip>")
                exit(1)
            }
            let ip = args[1]
            if let caster = dlnaCaster(for: ip) {
                try? await caster.resume()
                print("Resumed playback on \(ip)")
            }

        case "stop":
            guard args.count >= 2 else {
                print("Usage: smartcast stop <ip>")
                exit(1)
            }
            let ip = args[1]
            if let caster = dlnaCaster(for: ip) {
                try? await caster.stop()
                print("Stopped playback on \(ip)")
            }

        case "toast":
            guard args.count >= 3 else {
                print("Usage: smartcast toast <ip> <message>")
                exit(1)
            }
            let ip = args[1]
            let msg = args.dropFirst(2).joined(separator: " ")
            let lg = LGWebOSClient(ip: ip)
            lg.connect()
            do {
                try await lg.showToast(message: msg)
                print("Showed toast '\(msg)' on \(ip)")
            } catch {
                print("Error showing toast: \(error.localizedDescription)")
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
}
