import Foundation

public enum DLNAProtocol {
    public static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    public static func formatTimestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    public static func parseTimestamp(_ string: String) -> Double {
        let parts = string.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else {
            return 0
        }
        return (h * 3600) + (m * 60) + s
    }

    public static func didlMetadata(for media: MediaItem) -> String {
        let title = xmlEscape(media.title)
        let url = xmlEscape(media.url.absoluteString)
        let mime = xmlEscape(media.mimeType)

        var didl = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
          <item id="0" parentID="-1" restricted="1">
            <dc:title>\(title)</dc:title>
            <upnp:class>object.item.videoItem</upnp:class>
            <res protocolInfo="http-get:*:\(mime):*">\(url)</res>
        """

        if let poster = media.posterURL {
            let posterEsc = xmlEscape(poster.absoluteString)
            didl += """
            <upnp:albumArtURI>\(posterEsc)</upnp:albumArtURI>
            """
        }

        didl += """
          </item>
        </DIDL-Lite>
        """
        return didl
    }

    public static func soapEnvelope(serviceType: String, action: String, arguments: [String: String]) -> String {
        var argsXML = ""
        for (k, v) in arguments {
            argsXML += "<\(k)>\(xmlEscape(v))</\(k)>\n"
        }

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:\(action) xmlns:u="\(serviceType)">
              \(argsXML)
            </u:\(action)>
          </s:Body>
        </s:Envelope>
        """
    }
}

public final class DLNAClient: Sendable {
    public let avTransportURL: URL
    public let renderingControlURL: URL?
    private let urlSession: URLSession

    public init(avTransportURL: URL, renderingControlURL: URL? = nil, urlSession: URLSession = .shared) {
        self.avTransportURL = avTransportURL
        self.renderingControlURL = renderingControlURL
        self.urlSession = urlSession
    }

    public func setAVTransportURI(media: MediaItem) async throws {
        let meta = DLNAProtocol.didlMetadata(for: media)
        try await sendAVTransportAction(
            action: "SetAVTransportURI",
            arguments: [
                "InstanceID": "0",
                "CurrentURI": media.url.absoluteString,
                "CurrentURIMetaData": meta
            ]
        )
    }

    public func play() async throws {
        try await sendAVTransportAction(
            action: "Play",
            arguments: [
                "InstanceID": "0",
                "Speed": "1"
            ]
        )
    }

    public func pause() async throws {
        try await sendAVTransportAction(
            action: "Pause",
            arguments: ["InstanceID": "0"]
        )
    }

    public func stop() async throws {
        try await sendAVTransportAction(
            action: "Stop",
            arguments: ["InstanceID": "0"]
        )
    }

    public func seek(to seconds: Double) async throws {
        let target = DLNAProtocol.formatTimestamp(seconds)
        try await sendAVTransportAction(
            action: "Seek",
            arguments: [
                "InstanceID": "0",
                "Unit": "REL_TIME",
                "Target": target
            ]
        )
    }

    public func setVolume(_ volume: Int) async throws {
        guard let renderingControlURL else {
            throw DLNAError.renderingControlNotAvailable
        }
        let clamped = min(100, max(0, volume))
        let body = DLNAProtocol.soapEnvelope(
            serviceType: "urn:schemas-upnp-org:service:RenderingControl:1",
            action: "SetVolume",
            arguments: [
                "InstanceID": "0",
                "Channel": "Master",
                "DesiredVolume": "\(clamped)"
            ]
        )

        var request = URLRequest(url: renderingControlURL)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:RenderingControl:1#SetVolume\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(body.utf8)

        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw DLNAError.actionFailed("SetVolume failed")
        }
    }

    public func playbackStatus() async throws -> PlaybackStatus {
        let posXML = try await sendAVTransportActionWithResponse(
            action: "GetPositionInfo",
            arguments: ["InstanceID": "0"]
        )

        let transportXML = try await sendAVTransportActionWithResponse(
            action: "GetTransportInfo",
            arguments: ["InstanceID": "0"]
        )

        let position = extractTag(name: "RelTime", from: posXML).map { DLNAProtocol.parseTimestamp($0) } ?? 0
        let duration = extractTag(name: "TrackDuration", from: posXML).map { DLNAProtocol.parseTimestamp($0) } ?? 0
        let stateStr = extractTag(name: "CurrentTransportState", from: transportXML) ?? ""
        let state = PlaybackStatus.State(rawValue: stateStr) ?? .unknown

        return PlaybackStatus(state: state, positionSeconds: position, durationSeconds: duration)
    }

    @discardableResult
    private func sendAVTransportAction(action: String, arguments: [String: String]) async throws -> String {
        return try await sendAVTransportActionWithResponse(action: action, arguments: arguments)
    }

    private func sendAVTransportActionWithResponse(action: String, arguments: [String: String]) async throws -> String {
        let serviceType = "urn:schemas-upnp-org:service:AVTransport:1"
        let body = DLNAProtocol.soapEnvelope(serviceType: serviceType, action: action, arguments: arguments)

        var request = URLRequest(url: avTransportURL)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP status \( (response as? HTTPURLResponse)?.statusCode ?? -1)"
            throw DLNAError.actionFailed("\(action) failed: \(errorText)")
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func extractTag(name: String, from xml: String) -> String? {
        guard let startRange = xml.range(of: "<\(name)>"),
              let endRange = xml.range(of: "</\(name)>", range: startRange.upperBound..<xml.endIndex) else {
            return nil
        }
        return String(xml[startRange.upperBound..<endRange.lowerBound])
    }
}

public enum DLNAError: LocalizedError {
    case actionFailed(String)
    case renderingControlNotAvailable

    public var errorDescription: String? {
        switch self {
        case .actionFailed(let msg): return msg
        case .renderingControlNotAvailable: return "DLNA RenderingControl service is not available on this device."
        }
    }
}
