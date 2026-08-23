import Foundation

/// Represents the communication protocols supported by a Smart TV or media device.
public enum DeviceTransport: String, CaseIterable, Codable, Sendable {
    case samsungTizen = "samsung_tizen"
    case samsungLegacy = "samsung_legacy"
    case dlna = "dlna"
    case roku = "roku"
    case lgWebOS = "lg_webos"
    case googleCast = "google_cast"
}

/// Unified physical or network device discovered on the local network.
public struct Device: Identifiable, Hashable, Sendable, Codable {
    public let ip: String
    public var name: String
    public var manufacturer: String?
    public var model: String?
    public var macAddress: String?
    public var supportedTransports: [DeviceTransport]
    public var dlnaEndpoints: DLNAEndpoints?

    public var id: String { ip }

    public init(
        ip: String,
        name: String,
        manufacturer: String? = nil,
        model: String? = nil,
        macAddress: String? = nil,
        supportedTransports: [DeviceTransport] = [],
        dlnaEndpoints: DLNAEndpoints? = nil
    ) {
        self.ip = ip
        self.name = name
        self.manufacturer = manufacturer
        self.model = model
        self.macAddress = macAddress
        self.supportedTransports = supportedTransports
        self.dlnaEndpoints = dlnaEndpoints
    }

    /// The default preferred transport for media playback.
    public var preferredPlaybackTransport: DeviceTransport? {
        if supportedTransports.contains(.googleCast) { return .googleCast }
        if supportedTransports.contains(.dlna) { return .dlna }
        if supportedTransports.contains(.roku) { return .roku }
        return supportedTransports.first
    }

    /// The default preferred transport for remote key control.
    public var preferredRemoteTransport: DeviceTransport? {
        if supportedTransports.contains(.samsungTizen) { return .samsungTizen }
        if supportedTransports.contains(.samsungLegacy) { return .samsungLegacy }
        if supportedTransports.contains(.roku) { return .roku }
        if supportedTransports.contains(.lgWebOS) { return .lgWebOS }
        if supportedTransports.contains(.dlna) { return .dlna }
        return supportedTransports.first
    }
}

/// URLs for DLNA / UPnP AVTransport and RenderingControl services.
public struct DLNAEndpoints: Hashable, Sendable, Codable {
    public let avTransport: URL
    public let renderingControl: URL?

    public init(avTransport: URL, renderingControl: URL? = nil) {
        self.avTransport = avTransport
        self.renderingControl = renderingControl
    }
}

/// Universal remote control keys supported across TV manufacturers.
public enum RemoteKey: Hashable, Sendable {
    case power
    case powerOff
    case volumeUp
    case volumeDown
    case mute
    case up
    case down
    case left
    case right
    case enter
    case back
    case home
    case menu
    case info
    case play
    case pause
    case playPause
    case stop
    case rewind
    case fastForward
    case channelUp
    case channelDown
    case number(Int)
    case custom(String)
}

/// Media payload for casting to Smart TVs.
public struct MediaItem: Sendable {
    public let url: URL
    public let title: String
    public let mimeType: String
    public let posterURL: URL?
    public let subtitleURL: URL?
    public let durationSeconds: Double?

    public init(
        url: URL,
        title: String,
        mimeType: String = "video/mp4",
        posterURL: URL? = nil,
        subtitleURL: URL? = nil,
        durationSeconds: Double? = nil
    ) {
        self.url = url
        self.title = title
        self.mimeType = mimeType
        self.posterURL = posterURL
        self.subtitleURL = subtitleURL
        self.durationSeconds = durationSeconds
    }
}

/// Status of media playback on a device.
public struct PlaybackStatus: Equatable, Sendable {
    public enum State: String, Sendable {
        case playing = "PLAYING"
        case paused = "PAUSED_PLAYBACK"
        case stopped = "STOPPED"
        case buffering = "TRANSITIONING"
        case idle = "NO_MEDIA_PRESENT"
        case unknown = "UNKNOWN"
    }

    public let state: State
    public let positionSeconds: Double
    public let durationSeconds: Double

    public init(state: State, positionSeconds: Double = 0, durationSeconds: Double = 0) {
        self.state = state
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
    }

    public var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1.0, max(0.0, positionSeconds / durationSeconds))
    }
}
