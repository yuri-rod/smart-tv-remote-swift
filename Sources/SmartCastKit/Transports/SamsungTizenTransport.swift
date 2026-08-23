import Foundation
import os

private let logger = Logger(subsystem: "com.smartcastkit", category: "samsung-tizen")

/// Transport client for Samsung Smart TVs running Tizen OS (2016+ models) via WebSocket (port 8002).
public final class SamsungTizenClient: @unchecked Sendable {
    public enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case connected(token: String?)
        case failed(String)
    }

    public let ip: String
    public let appName: String
    private var token: String?
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let stateLock = NSLock()
    private var _state: ConnectionState = .disconnected

    public var state: ConnectionState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }

    public var onStateChange: (@Sendable (ConnectionState) -> Void)?
    public var onTokenReceived: (@Sendable (String) -> Void)?

    public init(ip: String, appName: String = "SmartCastKit", token: String? = nil) {
        self.ip = ip
        self.appName = appName
        self.token = token
    }

    public static func connectionURL(ip: String, appName: String, token: String?) -> URL? {
        let base64Name = Data(appName.utf8).base64EncodedString()
        var urlString = "wss://\(ip):8002/api/v2/channels/samsung.remote.control?name=\(base64Name)"
        if let token, !token.isEmpty {
            urlString += "&token=\(token)"
        }
        return URL(string: urlString)
    }

    public static func parseToken(fromConnectEvent jsonText: String) -> String? {
        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["event"] as? String == "ms.channel.connect",
              let eventData = json["data"] as? [String: Any] else {
            return nil
        }
        return eventData["token"] as? String
    }

    public func connect() {
        guard let url = Self.connectionURL(ip: ip, appName: appName, token: token) else {
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
            await self.listenForHandshake(task: task)
        }
    }

    private func listenForHandshake(task: URLSessionWebSocketTask) async {
        do {
            let message = try await task.receive()
            if case let .string(text) = message {
                if let newToken = Self.parseToken(fromConnectEvent: text) {
                    self.token = newToken
                    self.onTokenReceived?(newToken)
                }
                updateState(.connected(token: self.token))
                // Start continuous message receiving loop
                receiveLoop(task: task)
            } else {
                updateState(.failed("Unexpected handshake payload from TV"))
            }
        } catch {
            updateState(.failed("Connection rejected by TV or timed out: \(error.localizedDescription)"))
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case let .string(text) = message, let newToken = Self.parseToken(fromConnectEvent: text) {
                    self.token = newToken
                    self.onTokenReceived?(newToken)
                }
                self.receiveLoop(task: task)
            case .failure(let error):
                logger.debug("Samsung WebSocket disconnected: \(error.localizedDescription)")
                self.updateState(.disconnected)
            }
        }
    }

    public func sendKey(_ key: RemoteKey) async throws {
        guard let code = tizenKeyCode(for: key) else {
            throw SamsungTizenError.unsupportedKey
        }

        let payload: [String: Any] = [
            "method": "ms.remote.control",
            "params": [
                "Cmd": "Click",
                "DataOfCmd": code,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey"
            ]
        ]
        try await sendJSON(payload)
    }

    public func sendText(_ text: String) async throws {
        let base64Text = Data(text.utf8).base64EncodedString()
        let payload: [String: Any] = [
            "method": "ms.remote.control",
            "params": [
                "Cmd": base64Text,
                "DataOfCmd": "base64",
                "Option": "false",
                "TypeOfRemote": "SendInputString"
            ]
        ]
        try await sendJSON(payload)
    }

    public func launchApp(appId: String) async throws {
        let payload: [String: Any] = [
            "method": "ms.channel.emit",
            "params": [
                "event": "ed.apps.launch",
                "to": "host",
                "data": [
                    "appId": appId,
                    "action_type": "DEEP_LINK"
                ]
            ]
        ]
        try await sendJSON(payload)
    }

    private func sendJSON(_ dictionary: [String: Any]) async throws {
        guard let webSocket else {
            throw SamsungTizenError.notConnected
        }
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SamsungTizenError.invalidPayload
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

    private func tizenKeyCode(for key: RemoteKey) -> String? {
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

public enum SamsungTizenError: LocalizedError {
    case notConnected
    case unsupportedKey
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Samsung Tizen TV is not connected."
        case .unsupportedKey: return "The specified key is not supported on Samsung Tizen."
        case .invalidPayload: return "Failed to serialize JSON payload for Samsung Tizen."
        }
    }
}
