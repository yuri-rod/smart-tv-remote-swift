import Foundation
import os

private let logger = Logger(subsystem: "com.smartcastkit", category: "lg-webos")

/// Transport client for LG Smart TVs running webOS via SSAP WebSocket protocol (ports 3000/3001).
public final class LGWebOSClient: @unchecked Sendable {
    public enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case paired(clientKey: String?)
        case failed(String)
    }

    public let ip: String
    public let port: UInt16
    private var clientKey: String?
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let stateLock = NSLock()
    private var _state: ConnectionState = .disconnected
    private var requestCounter: Int = 1

    public var state: ConnectionState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }

    public var onStateChange: (@Sendable (ConnectionState) -> Void)?
    public var onClientKeyReceived: (@Sendable (String) -> Void)?

    public init(ip: String, port: UInt16 = 3000, clientKey: String? = nil) {
        self.ip = ip
        self.port = port
        self.clientKey = clientKey
    }

    public static func connectionURL(ip: String, port: UInt16) -> URL? {
        URL(string: "ws://\(ip):\(port)")
    }

    public static func makeRegistrationPayload(clientKey: String? = nil) -> [String: Any] {
        var payload: [String: Any] = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": [
                "manifestVersion": 1,
                "appVersion": "1.1",
                "signed": [
                    "created": "20260101",
                    "appId": "com.smartcastkit.client",
                    "vendorId": "com.smartcastkit",
                    "localizedAppNames": [
                        "": "SmartCastKit Remote"
                    ],
                    "permissions": [
                        "CONTROL_AUDIO",
                        "CONTROL_POWER",
                        "READ_INSTALLED_APPS",
                        "CONTROL_DISPLAY",
                        "CONTROL_INPUT_JOYSTICK",
                        "CONTROL_INPUT_MEDIA_PLAYBACK",
                        "WRITE_NOTIFICATION_TOAST"
                    ],
                    "serial": "smartcastkit-v1"
                ],
                "permissions": [
                    "LAUNCH",
                    "CONTROL_AUDIO",
                    "CONTROL_INPUT_MEDIA_PLAYBACK",
                    "WRITE_NOTIFICATION_TOAST",
                    "READ_POWER_STATE"
                ]
            ]
        ]
        if let clientKey, !clientKey.isEmpty {
            payload["client-key"] = clientKey
        }
        return [
            "type": "register",
            "id": "register_0",
            "payload": payload
        ]
    }

    public static func parseClientKey(fromResponse jsonText: String) -> String? {
        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any] else {
            return nil
        }
        return payload["client-key"] as? String
    }

    public func connect() {
        guard let url = Self.connectionURL(ip: ip, port: port) else {
            updateState(.failed("Invalid WebSocket URL"))
            return
        }

        updateState(.connecting)
        let session = URLSession(configuration: .default, delegate: LocalTrustDelegate.shared, delegateQueue: nil)
        self.urlSession = session
        let task = session.webSocketTask(with: url)
        self.webSocket = task
        task.resume()

        Task {
            await self.performHandshake(task: task)
        }
    }

    private func performHandshake(task: URLSessionWebSocketTask) async {
        let reg = Self.makeRegistrationPayload(clientKey: clientKey)
        do {
            let data = try JSONSerialization.data(withJSONObject: reg)
            guard let text = String(data: data, encoding: .utf8) else {
                updateState(.failed("Failed to build registration payload"))
                return
            }
            try await task.send(.string(text))

            let message = try await task.receive()
            if case let .string(respText) = message {
                if let key = Self.parseClientKey(fromResponse: respText) {
                    self.clientKey = key
                    self.onClientKeyReceived?(key)
                }
                updateState(.paired(clientKey: self.clientKey))
                receiveLoop(task: task)
            } else {
                updateState(.failed("Unexpected handshake format from LG TV"))
            }
        } catch {
            updateState(.failed("Connection rejected or timed out: \(error.localizedDescription)"))
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case let .string(text) = message, let key = Self.parseClientKey(fromResponse: text) {
                    self.clientKey = key
                    self.onClientKeyReceived?(key)
                }
                self.receiveLoop(task: task)
            case .failure(let error):
                logger.debug("LG webOS WebSocket disconnected: \(error.localizedDescription)")
                self.updateState(.disconnected)
            }
        }
    }

    public func sendKey(_ key: RemoteKey) async throws {
        guard let uri = lgKeyURI(for: key) else {
            throw LGWebOSError.unsupportedKey
        }
        try await sendRequest(uri: uri)
    }

    public func sendText(_ text: String) async throws {
        try await sendRequest(uri: "ssap://system.notifications/createToast", payload: ["message": text])
    }

    public func launchApp(appId: String) async throws {
        try await sendRequest(uri: "ssap://system.launcher/open", payload: ["id": appId])
    }

    public func setVolume(_ volume: Int) async throws {
        try await sendRequest(uri: "ssap://audio/setVolume", payload: ["volume": max(0, min(100, volume))])
    }

    public func setMute(_ mute: Bool) async throws {
        try await sendRequest(uri: "ssap://audio/setMute", payload: ["mute": mute])
    }

    public func showToast(message: String) async throws {
        try await sendRequest(uri: "ssap://system.notifications/createToast", payload: ["message": message])
    }

    private func sendRequest(uri: String, payload: [String: Any]? = nil) async throws {
        guard let webSocket else {
            throw LGWebOSError.notConnected
        }

        let reqId = "req_\(requestCounter)"
        requestCounter += 1

        var dict: [String: Any] = [
            "type": "request",
            "id": reqId,
            "uri": uri
        ]
        if let payload {
            dict["payload"] = payload
        }

        let data = try JSONSerialization.data(withJSONObject: dict)
        guard let text = String(data: data, encoding: .utf8) else {
            throw LGWebOSError.invalidPayload
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webSocket.send(.string(text)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        urlSession?.invalidateAndCancel()
        webSocket = nil
        urlSession = nil
        updateState(.disconnected)
    }

    private func updateState(_ newState: ConnectionState) {
        stateLock.lock()
        _state = newState
        stateLock.unlock()
        onStateChange?(newState)
    }

    private func lgKeyURI(for key: RemoteKey) -> String? {
        switch key {
        case .power, .powerOff: return "ssap://system/turnOff"
        case .volumeUp: return "ssap://audio/volumeUp"
        case .volumeDown: return "ssap://audio/volumeDown"
        case .mute: return "ssap://audio/volumeMute"
        case .play: return "ssap://media.controls/play"
        case .pause: return "ssap://media.controls/pause"
        case .playPause: return "ssap://media.controls/play"
        case .stop: return "ssap://media.controls/stop"
        case .rewind: return "ssap://media.controls/rewind"
        case .fastForward: return "ssap://media.controls/fastForward"
        case .channelUp: return "ssap://tv/channelUp"
        case .channelDown: return "ssap://tv/channelDown"
        case .custom(let uri): return uri.hasPrefix("ssap://") ? uri : "ssap://\(uri)"
        default: return nil
        }
    }
}

public enum LGWebOSError: LocalizedError {
    case notConnected
    case unsupportedKey
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "LG webOS TV is not connected."
        case .unsupportedKey: return "The specified key is not supported on LG webOS."
        case .invalidPayload: return "Failed to serialize JSON payload for LG webOS."
        }
    }
}
