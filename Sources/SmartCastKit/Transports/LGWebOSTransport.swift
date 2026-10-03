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
    private var inputSocket: URLSessionWebSocketTask?
    private var pendingResponses: [String: CheckedContinuation<String, Error>] = [:]

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

    public static func parseMessageType(fromResponse jsonText: String) -> String? {
        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["type"] as? String
    }

    public static func parseMessageId(fromResponse jsonText: String) -> String? {
        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["id"] as? String
    }

    /// Builds the plain-text button press frame sent on the pointer input socket.
    public static func buttonMessage(name: String) -> String {
        "type:button\nname:\(name)\n\n"
    }

    /// Connects and suspends until the TV completes pairing, rejects it, or the timeout elapses.
    public func connectAndWait(timeout: TimeInterval = 20) async throws {
        connect()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch state {
            case .paired:
                return
            case .failed(let message):
                throw LGWebOSError.connectionFailed(message)
            case .disconnected:
                throw LGWebOSError.notConnected
            case .connecting:
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        disconnect()
        throw LGWebOSError.timeout
    }

    /// Ensures a paired channel, pairing only when the current state is not paired.
    public func ensurePaired(timeout: TimeInterval = 20) async throws {
        if case .paired = state { return }
        try await connectAndWait(timeout: timeout)
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

            // First-time pairing yields a "response" prompt message followed by a
            // "registered" message carrying the client key, so keep reading until
            // the key arrives instead of trusting the first frame.
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                let message = try await task.receive()
                guard case let .string(respText) = message else {
                    updateState(.failed("Unexpected handshake format from LG TV"))
                    return
                }
                if let key = Self.parseClientKey(fromResponse: respText) {
                    self.clientKey = key
                    self.onClientKeyReceived?(key)
                    updateState(.paired(clientKey: key))
                    receiveLoop(task: task)
                    return
                }
                // Already-paired clients get an acknowledgement without a fresh key.
                let msgType = Self.parseMessageType(fromResponse: respText)
                if msgType == "registered" || (msgType == "response" && clientKey != nil) {
                    updateState(.paired(clientKey: clientKey))
                    receiveLoop(task: task)
                    return
                }
            }
            updateState(.failed("Pairing timed out waiting for the TV to approve the prompt"))
        } catch {
            updateState(.failed("Connection rejected or timed out: \(error.localizedDescription)"))
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case let .string(text) = message {
                    if let id = Self.parseMessageId(fromResponse: text),
                       let continuation = self.takePendingResponse(id: id) {
                        continuation.resume(returning: text)
                    } else if let key = Self.parseClientKey(fromResponse: text) {
                        self.clientKey = key
                        self.onClientKeyReceived?(key)
                    }
                }
                self.receiveLoop(task: task)
            case .failure(let error):
                logger.debug("LG webOS WebSocket disconnected: \(error.localizedDescription)")
                self.failPendingResponses(error: error)
                self.updateState(.disconnected)
            }
        }
    }

    public func sendKey(_ key: RemoteKey) async throws {
        try await ensurePaired()
        if let button = lgButtonName(for: key) {
            try await sendButton(button)
            return
        }
        guard let uri = lgKeyURI(for: key) else {
            throw LGWebOSError.unsupportedKey
        }
        try await sendRequest(uri: uri)
    }

    public func sendText(_ text: String) async throws {
        try await ensurePaired()
        try await sendRequest(uri: "ssap://system.notifications/createToast", payload: ["message": text])
    }

    public func launchApp(appId: String) async throws {
        try await ensurePaired()
        try await sendRequest(uri: "ssap://system.launcher/open", payload: ["id": appId])
    }

    public func setVolume(_ volume: Int) async throws {
        try await ensurePaired()
        try await sendRequest(uri: "ssap://audio/setVolume", payload: ["volume": max(0, min(100, volume))])
    }

    public func setMute(_ mute: Bool) async throws {
        try await ensurePaired()
        try await sendRequest(uri: "ssap://audio/setMute", payload: ["mute": mute])
    }

    public func showToast(message: String) async throws {
        try await ensurePaired()
        try await sendRequest(uri: "ssap://system.notifications/createToast", payload: ["message": message])
    }

    /// Sends a navigation or digit button press over the pointer input socket.
    public func sendButton(_ name: String) async throws {
        try await ensurePaired()
        let socket = try await ensureInputSocket()
        let text = Self.buttonMessage(name: name)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.send(.string(text)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Opens the pointer input socket once and reuses it for later button presses.
    private func ensureInputSocket() async throws -> URLSessionWebSocketTask {
        if let inputSocket { return inputSocket }
        guard let session = urlSession else {
            throw LGWebOSError.notConnected
        }
        let response = try await requestResponse(uri: "ssap://com.webos.service.networkinput/getPointerInputSocket")
        guard let payload = response["payload"] as? [String: Any],
              let socketPath = payload["socketPath"] as? String,
              let url = URL(string: socketPath) else {
            throw LGWebOSError.inputSocketUnavailable
        }
        let socket = session.webSocketTask(with: url)
        socket.resume()
        inputSocket = socket
        return socket
    }

    /// Sends a request and suspends until the matching response id arrives or the timeout elapses.
    private func requestResponse(uri: String, payload: [String: Any]? = nil, timeout: TimeInterval = 8) async throws -> [String: Any] {
        guard webSocket != nil else {
            throw LGWebOSError.notConnected
        }
        let reqId = nextRequestId()
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
        let responseText: String = try await withCheckedThrowingContinuation { continuation in
            stateLock.lock()
            pendingResponses[reqId] = continuation
            stateLock.unlock()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let pending = self.takePendingResponse(id: reqId) {
                    pending.resume(throwing: LGWebOSError.timeout)
                }
            }
            Task {
                do {
                    try await self.sendRaw(text)
                } catch {
                    if let pending = self.takePendingResponse(id: reqId) {
                        pending.resume(throwing: error)
                    }
                }
            }
        }
        guard let responseData = responseText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw LGWebOSError.invalidPayload
        }
        return json
    }

    private func sendRequest(uri: String, payload: [String: Any]? = nil) async throws {
        let reqId = nextRequestId()
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
        try await sendRaw(text)
    }

    private func sendRaw(_ text: String) async throws {
        guard let webSocket else {
            throw LGWebOSError.notConnected
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

    private func nextRequestId() -> String {
        stateLock.lock()
        defer { stateLock.unlock() }
        let reqId = "req_\(requestCounter)"
        requestCounter += 1
        return reqId
    }

    private func takePendingResponse(id: String) -> CheckedContinuation<String, Error>? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingResponses.removeValue(forKey: id)
    }

    private func failPendingResponses(error: Error) {
        stateLock.lock()
        let pending = pendingResponses
        pendingResponses.removeAll()
        stateLock.unlock()
        for continuation in pending.values {
            continuation.resume(throwing: error)
        }
    }

    public func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        inputSocket?.cancel(with: .normalClosure, reason: nil)
        urlSession?.invalidateAndCancel()
        webSocket = nil
        inputSocket = nil
        urlSession = nil
        failPendingResponses(error: LGWebOSError.notConnected)
        updateState(.disconnected)
    }

    private func updateState(_ newState: ConnectionState) {
        stateLock.lock()
        _state = newState
        stateLock.unlock()
        onStateChange?(newState)
    }

    /// Navigation and digit keys travel as button presses on the pointer input
    /// socket; media and audio keys keep their direct ssap:// URIs.
    private func lgButtonName(for key: RemoteKey) -> String? {
        switch key {
        case .up: return "UP"
        case .down: return "DOWN"
        case .left: return "LEFT"
        case .right: return "RIGHT"
        case .enter: return "ENTER"
        case .back: return "BACK"
        case .home: return "HOME"
        case .menu: return "MENU"
        case .info: return "INFO"
        case .number(let num) where (0...9).contains(num): return "\(num)"
        default: return nil
        }
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
    case connectionFailed(String)
    case timeout
    case inputSocketUnavailable

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "LG webOS TV is not connected."
        case .unsupportedKey: return "The specified key is not supported on LG webOS."
        case .invalidPayload: return "Failed to serialize JSON payload for LG webOS."
        case .connectionFailed(let message): return "LG webOS connection failed: \(message)."
        case .timeout: return "Timed out waiting for the LG TV. Accept the on-screen pairing prompt and retry."
        case .inputSocketUnavailable: return "LG TV did not provide a pointer input socket for button presses."
        }
    }
}
