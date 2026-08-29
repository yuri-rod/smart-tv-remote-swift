import Foundation

/// High-level facade for discovering devices, controlling Smart TV remotes, and streaming media.
public enum SmartCast {
    /// Discovers all Smart TVs and media renderers on the local network.
    public static func scan(timeout: TimeInterval = 4.0) async -> [Device] {
        let scanner = DeviceScanner()
        return await scanner.scan(timeout: timeout)
    }

    /// Creates a remote controller client for the given device using its preferred remote transport.
    public static func remote(for device: Device, appName: String = "SmartCastKit", token: String? = nil) -> AnyRemoteController? {
        guard let transport = device.preferredRemoteTransport else { return nil }
        switch transport {
        case .samsungTizen:
            return SamsungTizenRemoteAdapter(client: SamsungTizenClient(ip: device.ip, appName: appName, token: token))
        case .samsungLegacy:
            return SamsungLegacyRemoteAdapter(client: SamsungLegacyClient(ip: device.ip, appName: appName))
        case .roku:
            return RokuRemoteAdapter(client: RokuClient(ip: device.ip))
        case .lgWebOS:
            return LGWebOSRemoteAdapter(client: LGWebOSClient(ip: device.ip, clientKey: token))
        default:
            return nil
        }
    }

    /// Creates a media caster client for the given device using its preferred playback transport.
    public static func caster(for device: Device) -> AnyMediaCaster? {
        guard let dlna = device.dlnaEndpoints else { return nil }
        let client = DLNAClient(avTransportURL: dlna.avTransport, renderingControlURL: dlna.renderingControl)
        return DLNAMediaCasterAdapter(client: client)
    }

    /// Wakes a sleeping TV using Wake-on-LAN if its MAC address is known.
    public static func wake(device: Device) async throws {
        guard let mac = device.macAddress else {
            throw WakeOnLANError.invalidMACAddress
        }
        try await WakeOnLAN.wake(macAddress: mac)
    }
}

/// Unified interface for sending remote control keys and text to any TV.
public protocol AnyRemoteController: Sendable {
    func sendKey(_ key: RemoteKey) async throws
    func sendText(_ text: String) async throws
}

/// Unified interface for casting media, controlling playback, and inspecting progress on any TV.
public protocol AnyMediaCaster: Sendable {
    func play(media: MediaItem) async throws
    func pause() async throws
    func resume() async throws
    func stop() async throws
    func seek(to seconds: Double) async throws
    func setVolume(_ volume: Int) async throws
    func playbackStatus() async throws -> PlaybackStatus
}

// MARK: - Remote Controller Adapters

final class SamsungTizenRemoteAdapter: AnyRemoteController {
    let client: SamsungTizenClient

    init(client: SamsungTizenClient) {
        self.client = client
        client.connect()
    }

    func sendKey(_ key: RemoteKey) async throws {
        try await client.sendKey(key)
    }

    func sendText(_ text: String) async throws {
        try await client.sendText(text)
    }
}

final class SamsungLegacyRemoteAdapter: AnyRemoteController {
    let client: SamsungLegacyClient

    init(client: SamsungLegacyClient) {
        self.client = client
    }

    func sendKey(_ key: RemoteKey) async throws {
        try await client.sendKey(key)
    }

    func sendText(_ text: String) async throws {
        try await client.sendText(text)
    }
}

final class RokuRemoteAdapter: AnyRemoteController {
    let client: RokuClient

    init(client: RokuClient) {
        self.client = client
    }

    func sendKey(_ key: RemoteKey) async throws {
        try await client.sendKey(key)
    }

    func sendText(_ text: String) async throws {
        // Roku does not have direct raw text input via standard ECP keypress without sequential char encoding
        for char in text {
            if let encoded = "Lit_\(char)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                try await client.sendKey(.custom(encoded))
            }
        }
    }
}

final class LGWebOSRemoteAdapter: AnyRemoteController {
    let client: LGWebOSClient

    init(client: LGWebOSClient) {
        self.client = client
        client.connect()
    }

    func sendKey(_ key: RemoteKey) async throws {
        try await client.sendKey(key)
    }

    func sendText(_ text: String) async throws {
        try await client.sendText(text)
    }
}

// MARK: - Media Caster Adapters

final class DLNAMediaCasterAdapter: AnyMediaCaster {
    let client: DLNAClient

    init(client: DLNAClient) {
        self.client = client
    }

    func play(media: MediaItem) async throws {
        try await client.setAVTransportURI(media: media)
        try await client.play()
    }

    func pause() async throws {
        try await client.pause()
    }

    func resume() async throws {
        try await client.play()
    }

    func stop() async throws {
        try await client.stop()
    }

    func seek(to seconds: Double) async throws {
        try await client.seek(to: seconds)
    }

    func setVolume(_ volume: Int) async throws {
        try await client.setVolume(volume)
    }

    func playbackStatus() async throws -> PlaybackStatus {
        try await client.playbackStatus()
    }
}
