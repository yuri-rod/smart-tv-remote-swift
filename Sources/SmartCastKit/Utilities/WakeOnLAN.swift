import Foundation
import Network

/// Sends Wake-on-LAN magic packets over UDP to wake sleeping Smart TVs.
public enum WakeOnLAN {
    /// Builds a 102-byte Wake-on-LAN Magic Packet payload for a given MAC address.
    public static func magicPacketPayload(for macAddress: String) -> Data? {
        let cleaned = macAddress
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")

        guard cleaned.count == 12 else { return nil }

        var macBytes = [UInt8]()
        for i in stride(from: 0, to: 12, by: 2) {
            let start = cleaned.index(cleaned.startIndex, offsetBy: i)
            let end = cleaned.index(start, offsetBy: 2)
            guard let byte = UInt8(cleaned[start..<end], radix: 16) else { return nil }
            macBytes.append(byte)
        }

        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        return packet
    }

    /// Broadcasts a Wake-on-LAN packet to wake the specified device.
    public static func wake(
        macAddress: String,
        broadcastAddress: String = "255.255.255.255",
        port: UInt16 = 9
    ) async throws {
        guard let payload = magicPacketPayload(for: macAddress) else {
            throw WakeOnLANError.invalidMACAddress
        }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw WakeOnLANError.invalidPort
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(broadcastAddress),
            port: nwPort,
            using: .udp
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        connection.cancel()
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
}

public enum WakeOnLANError: LocalizedError {
    case invalidMACAddress
    case invalidPort

    public var errorDescription: String? {
        switch self {
        case .invalidMACAddress: return "Invalid MAC address format. Expected 12 hex digits."
        case .invalidPort: return "Invalid Wake-on-LAN UDP port number."
        }
    }
}
