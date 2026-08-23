import Foundation

public struct RokuApp: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let type: String?
    public let version: String?

    public init(id: String, name: String, type: String? = nil, version: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.version = version
    }
}

public final class RokuClient: Sendable {
    public let ip: String
    public let port: UInt16
    private let urlSession: URLSession

    public init(ip: String, port: UInt16 = 8060, urlSession: URLSession = .shared) {
        self.ip = ip
        self.port = port
        self.urlSession = urlSession
    }

    private var baseURL: URL {
        URL(string: "http://\(ip):\(port)")!
    }

    public func sendKey(_ key: RemoteKey) async throws {
        guard let code = rokuKeyCode(for: key) else {
            throw RokuError.unsupportedKey
        }
        let url = baseURL.appendingPathComponent("keypress").appendingPathComponent(code)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RokuError.commandFailed("Keypress \(code) failed")
        }
    }

    public func launchApp(appId: String, params: [String: String] = [:]) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent("launch").appendingPathComponent(appId), resolvingAgainstBaseURL: false)!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RokuError.commandFailed("App launch \(appId) failed")
        }
    }

    public func queryApps() async throws -> [RokuApp] {
        let url = baseURL.appendingPathComponent("query").appendingPathComponent("apps")
        let (data, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RokuError.commandFailed("Failed to query apps")
        }
        guard let xml = String(data: data, encoding: .utf8) else { return [] }

        var apps: [RokuApp] = []
        let pattern = "<app id=\"([^\"]+)\"[^>]*>([^<]+)</app>"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsString = xml as NSString
            let matches = regex.matches(in: xml, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                let id = nsString.substring(with: match.range(at: 1))
                let name = nsString.substring(with: match.range(at: 2))
                apps.append(RokuApp(id: id, name: name))
            }
        }
        return apps
    }

    private func rokuKeyCode(for key: RemoteKey) -> String? {
        switch key {
        case .power: return "Power"
        case .powerOff: return "PowerOff"
        case .home: return "Home"
        case .back: return "Back"
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .enter: return "Select"
        case .play, .pause, .playPause: return "Play"
        case .rewind: return "Rev"
        case .fastForward: return "Fwd"
        case .volumeUp: return "VolumeUp"
        case .volumeDown: return "VolumeDown"
        case .mute: return "VolumeMute"
        case .info: return "Info"
        case .channelUp: return "ChannelUp"
        case .channelDown: return "ChannelDown"
        case .custom(let code): return code
        default: return nil
        }
    }
}

public enum RokuError: LocalizedError {
    case unsupportedKey
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedKey: return "The specified key is not supported on Roku."
        case .commandFailed(let msg): return msg
        }
    }
}
