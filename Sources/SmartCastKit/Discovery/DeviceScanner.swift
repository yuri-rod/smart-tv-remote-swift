import Foundation
import Network
import Combine
import os

private let logger = Logger(subsystem: "com.smartcastkit", category: "scanner")

/// Discovers Smart TVs, media renderers, and casting devices across the local Wi-Fi network.
public actor DeviceScanner {
    public static let ssdpMulticastGroup = "239.255.255.250"
    public static let ssdpPort: UInt16 = 1900

    private var discoveredDevices: [String: Device] = [:]
    private var isScanning = false

    public init() {}

    /// Performs an active network discovery scan and returns all identified Smart TVs and media devices.
    public func scan(timeout: TimeInterval = 4.0) async -> [Device] {
        discoveredDevices.removeAll()
        isScanning = true

        let ssdpTargets = [
            "urn:schemas-upnp-org:service:AVTransport:1",
            "urn:samsung.com:device:RemoteControlReceiver:1",
            "roku:ecp",
            "ssdp:all"
        ]

        // 1. Send SSDP M-SEARCH multicast packets
        await withTaskGroup(of: Void.self) { group in
            for target in ssdpTargets {
                group.addTask {
                    await self.sendSSDPQuery(target: target)
                }
            }

            // 2. Discover local IP and probe candidate ports on active subnet
            group.addTask {
                await self.sweepSubnet()
            }
        }

        // Wait for responses up to timeout
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        isScanning = false

        return Array(discoveredDevices.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func sendSSDPQuery(target: String) async {
        let message = """
        M-SEARCH * HTTP/1.1\r
        HOST: \(Self.ssdpMulticastGroup):\(Self.ssdpPort)\r
        MAN: "ssdp:discover"\r
        MX: 2\r
        ST: \(target)\r
        \r

        """

        guard let data = message.data(using: .utf8),
              let nwPort = NWEndpoint.Port(rawValue: Self.ssdpPort) else { return }

        let connection = NWConnection(
            host: NWEndpoint.Host(Self.ssdpMulticastGroup),
            port: nwPort,
            using: .udp
        )

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                connection.send(content: data, completion: .contentProcessed { _ in })
                Task {
                    await self.listenForSSDPResponses(connection: connection)
                }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func listenForSSDPResponses(connection: NWConnection) async {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, isComplete, _ in
            guard let self, let content, let text = String(data: content, encoding: .utf8) else {
                return
            }

            Task {
                await self.handleSSDPResponse(text)
                if !isComplete {
                    await self.listenForSSDPResponses(connection: connection)
                }
            }
        }
    }

    private func handleSSDPResponse(_ responseText: String) async {
        var locationURL: URL?
        var foundIp: String?

        let lines = responseText.components(separatedBy: "\r\n")
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("location:") {
                let urlStr = line.dropFirst(9).trimmingCharacters(in: .whitespaces)
                locationURL = URL(string: urlStr)
                foundIp = locationURL?.host
            }
        }

        guard let ip = foundIp, let locationURL else { return }
        await parseUPnPDescriptor(url: locationURL, ip: ip)
    }

    private func parseUPnPDescriptor(url: URL, ip: String) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let xml = String(data: data, encoding: .utf8) else { return }

            let friendlyName = extractTag(name: "friendlyName", from: xml) ?? "Smart TV (\(ip))"
            let manufacturer = extractTag(name: "manufacturer", from: xml)
            let modelName = extractTag(name: "modelName", from: xml)

            var avTransportURL: URL?
            var renderingControlURL: URL?

            if let avControl = extractServiceControlURL(serviceType: "urn:schemas-upnp-org:service:AVTransport:1", from: xml) {
                avTransportURL = resolveURL(avControl, relativeTo: url)
            }
            if let renderControl = extractServiceControlURL(serviceType: "urn:schemas-upnp-org:service:RenderingControl:1", from: xml) {
                renderingControlURL = resolveURL(renderControl, relativeTo: url)
            }

            var transports: [DeviceTransport] = []
            var endpoints: DLNAEndpoints?

            if let avTransportURL {
                transports.append(.dlna)
                endpoints = DLNAEndpoints(avTransport: avTransportURL, renderingControl: renderingControlURL)
            }

            // Probe additional ports
            let probedTransports = await probeDevicePorts(ip: ip)
            for t in probedTransports where !transports.contains(t) {
                transports.append(t)
            }

            mergeDevice(Device(
                ip: ip,
                name: friendlyName,
                manufacturer: manufacturer,
                model: modelName,
                supportedTransports: transports,
                dlnaEndpoints: endpoints
            ))
        } catch {
            logger.debug("Failed to fetch UPnP descriptor at \(url.absoluteString): \(error.localizedDescription)")
        }
    }

    private func sweepSubnet() async {
        guard let localIP = getLocalIPAddress() else { return }
        let components = localIP.components(separatedBy: ".")
        guard components.count == 4 else { return }
        let subnetPrefix = "\(components[0]).\(components[1]).\(components[2])"

        await withTaskGroup(of: Void.self) { group in
            for host in 1...254 {
                let targetIP = "\(subnetPrefix).\(host)"
                if targetIP == localIP { continue }
                group.addTask {
                    let transports = await self.probeDevicePorts(ip: targetIP)
                    if !transports.isEmpty {
                        await self.mergeDevice(Device(
                            ip: targetIP,
                            name: "Smart TV (\(targetIP))",
                            supportedTransports: transports
                        ))
                    }
                }
            }
        }
    }

    private func probeDevicePorts(ip: String) async -> [DeviceTransport] {
        var transports: [DeviceTransport] = []

        // Probe 8002 (Samsung Tizen)
        if await isPortOpen(ip: ip, port: 8002) {
            transports.append(.samsungTizen)
        }
        // Probe 8060 (Roku)
        if await isPortOpen(ip: ip, port: 8060) {
            transports.append(.roku)
        }
        // Probe 55000 (Samsung Legacy)
        if await isPortOpen(ip: ip, port: 55000) {
            transports.append(.samsungLegacy)
        }

        return transports
    }

    private func isPortOpen(ip: String, port: UInt16, timeout: TimeInterval = 0.6) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: .tcp)

        final class AtomicState: @unchecked Sendable {
            private let lock = NSLock()
            private var isResumed = false

            func trigger(action: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                if !isResumed {
                    isResumed = true
                    action()
                }
            }
        }

        let state = AtomicState()

        return await withCheckedContinuation { continuation in
            let resumeOnce: @Sendable (Bool) -> Void = { result in
                state.trigger {
                    connection.cancel()
                    continuation.resume(returning: result)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce(true)
                case .failed, .cancelled:
                    resumeOnce(false)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                resumeOnce(false)
            }
        }
    }

    private func mergeDevice(_ newDevice: Device) {
        if var existing = discoveredDevices[newDevice.ip] {
            if existing.name.contains("Smart TV (") && !newDevice.name.contains("Smart TV (") {
                existing.name = newDevice.name
            }
            if existing.manufacturer == nil { existing.manufacturer = newDevice.manufacturer }
            if existing.model == nil { existing.model = newDevice.model }
            if existing.dlnaEndpoints == nil { existing.dlnaEndpoints = newDevice.dlnaEndpoints }

            for t in newDevice.supportedTransports where !existing.supportedTransports.contains(t) {
                existing.supportedTransports.append(t)
            }
            discoveredDevices[newDevice.ip] = existing
        } else {
            discoveredDevices[newDevice.ip] = newDevice
        }
    }

    private func extractTag(name: String, from xml: String) -> String? {
        guard let start = xml.range(of: "<\(name)>"),
              let end = xml.range(of: "</\(name)>", range: start.upperBound..<xml.endIndex) else {
            return nil
        }
        return String(xml[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractServiceControlURL(serviceType: String, from xml: String) -> String? {
        guard let serviceStart = xml.range(of: "<serviceType>\(serviceType)</serviceType>") else {
            return nil
        }
        let afterService = xml[serviceStart.upperBound...]
        guard let controlStart = afterService.range(of: "<controlURL>"),
              let controlEnd = afterService.range(of: "</controlURL>", range: controlStart.upperBound..<afterService.endIndex) else {
            return nil
        }
        return String(afterService[controlStart.upperBound..<controlEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveURL(_ relativeOrAbsolute: String, relativeTo base: URL) -> URL? {
        if let direct = URL(string: relativeOrAbsolute), direct.scheme != nil {
            return direct
        }
        return URL(string: relativeOrAbsolute, relativeTo: base)?.absoluteURL
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" || name == "wlan0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }
}
