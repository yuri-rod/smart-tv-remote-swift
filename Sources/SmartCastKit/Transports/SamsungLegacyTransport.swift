import Foundation
import Network

/// Transport client for older pre-2015 Samsung Smart TVs running the legacy port 55000 TCP protocol.
public enum SamsungLegacyProtocol {
    public static func payloadFrame(appString: String, body: Data) -> Data {
        let appBytes = [UInt8](appString.utf8)
        let appLen = UInt16(appBytes.count)
        let bodyLen = UInt16(body.count)

        var data = Data()
        data.append(0x00) // delimiter
        data.append(UInt8(appLen & 0xFF))
        data.append(UInt8((appLen >> 8) & 0xFF))
        data.append(contentsOf: appBytes)
        data.append(UInt8(bodyLen & 0xFF))
        data.append(UInt8((bodyLen >> 8) & 0xFF))
        data.append(body)
        return data
    }

    public static func handshakeFrame(
        appName: String = "SmartCastKit",
        id: String = "smartcastkit",
        ip: String = "127.0.0.1",
        mac: String = "00:00:00:00:00:00"
    ) -> Data {
        var body = Data()
        body.append(0x64)
        body.append(0x00)

        func appendField(_ str: String) {
            let b64 = Data(str.utf8).base64EncodedData()
            let len = UInt16(b64.count)
            body.append(UInt8(len & 0xFF))
            body.append(UInt8((len >> 8) & 0xFF))
            body.append(b64)
        }

        appendField(ip)
        appendField(mac)
        appendField(appName)

        return payloadFrame(appString: id, body: body)
    }

    public static func keyFrame(_ key: String) -> Data {
        var body = Data()
        body.append(0x00)
        body.append(0x00)
        body.append(0x00)

        let b64 = Data(key.utf8).base64EncodedData()
        let len = UInt16(b64.count)
        body.append(UInt8(len & 0xFF))
        body.append(UInt8((len >> 8) & 0xFF))
        body.append(b64)

        return payloadFrame(appString: "iapp.samsung", body: body)
    }

    public static func textFrame(_ text: String) -> Data {
        var body = Data()
        body.append(0x01)
        body.append(0x00)

        let b64 = Data(text.utf8).base64EncodedData()
        let len = UInt16(b64.count)
        body.append(UInt8(len & 0xFF))
        body.append(UInt8((len >> 8) & 0xFF))
        body.append(b64)

        return payloadFrame(appString: "iapp.samsung", body: body)
    }
}

public final class SamsungLegacyClient: Sendable {
    public let ip: String
    public let port: UInt16
    public let appName: String

    public init(ip: String, port: UInt16 = 55000, appName: String = "SmartCastKit") {
        self.ip = ip
        self.port = port
        self.appName = appName
    }

    public func sendKey(_ key: RemoteKey) async throws {
        guard let code = legacyKeyCode(for: key) else {
            throw SamsungLegacyError.unsupportedKey
        }

        let handshake = SamsungLegacyProtocol.handshakeFrame(appName: appName)
        let keyData = SamsungLegacyProtocol.keyFrame(code)
        let packet = handshake + keyData

        try await sendBytes(packet)
    }

    public func sendText(_ text: String) async throws {
        let handshake = SamsungLegacyProtocol.handshakeFrame(appName: appName)
        let textData = SamsungLegacyProtocol.textFrame(text)
        let packet = handshake + textData

        try await sendBytes(packet)
    }

    private func sendBytes(_ data: Data) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw SamsungLegacyError.invalidPort
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(ip),
            port: nwPort,
            using: .tcp
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { error in
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
                            connection.cancel()
                        }
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    })
                case .failed(let error):
                    connection.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private func legacyKeyCode(for key: RemoteKey) -> String? {
        switch key {
        case .power: return "KEY_POWER"
        case .powerOff: return "KEY_POWEROFF"
        case .volumeUp: return "KEY_VOLUP"
        case .volumeDown: return "KEY_VOLDOWN"
        case .mute: return "KEY_MUTE"
        case .up: return "KEY_UP"
        case .down: return "KEY_DOWN"
        case .left: return "KEY_LEFT"
        case .right: return "KEY_RIGHT"
        case .enter: return "KEY_ENTER"
        case .back: return "KEY_RETURN"
        case .home: return "KEY_HOME"
        case .menu: return "KEY_MENU"
        case .info: return "KEY_INFO"
        case .play: return "KEY_PLAY"
        case .pause: return "KEY_PAUSE"
        case .playPause: return "KEY_PLAYPAUSE"
        case .stop: return "KEY_STOP"
        case .rewind: return "KEY_REWIND"
        case .fastForward: return "KEY_FF"
        case .channelUp: return "KEY_CHUP"
        case .channelDown: return "KEY_CHDOWN"
        case .number(let num) where (0...9).contains(num): return "KEY_\(num)"
        case .custom(let code): return code
        default: return nil
        }
    }
}

public enum SamsungLegacyError: LocalizedError {
    case unsupportedKey
    case invalidPort

    public var errorDescription: String? {
        switch self {
        case .unsupportedKey: return "The specified key is not supported on legacy Samsung protocol."
        case .invalidPort: return "Invalid legacy Samsung TCP port number."
        }
    }
}
