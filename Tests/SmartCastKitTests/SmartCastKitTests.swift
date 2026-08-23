import Foundation

@main
struct SmartCastKitTestsRunner {
    static func main() {
        print("Running SmartCastKit Test Suite...")

        // 1. DLNA Protocol
        let input = "Stranger Things & Friends <\"Special's\">"
        let escaped = DLNAProtocol.xmlEscape(input)
        assert(escaped == "Stranger Things &amp; Friends &lt;&quot;Special&apos;s&quot;&gt;", "XMLEscaping failed")
        print("  testXMLEscaping passed")

        let seconds: Double = 3723
        let formatted = DLNAProtocol.formatTimestamp(seconds)
        assert(formatted == "01:02:03", "Timestamp format failed")
        assert(DLNAProtocol.parseTimestamp(formatted) == seconds, "Timestamp parse failed")
        print("  testDLNATimestampFormattingAndParsing passed")

        let media = MediaItem(
            url: URL(string: "http://192.168.1.100:8096/stream.mp4")!,
            title: "Avatar & Pandora",
            mimeType: "video/mp4",
            posterURL: URL(string: "http://192.168.1.100:8096/poster.jpg")!
        )
        let xml = DLNAProtocol.didlMetadata(for: media)
        assert(xml.contains("<dc:title>Avatar &amp; Pandora</dc:title>"), "DIDL title missing")
        assert(xml.contains("http://192.168.1.100:8096/stream.mp4"), "DIDL URL missing")
        assert(xml.contains("http://192.168.1.100:8096/poster.jpg"), "DIDL poster missing")
        print("  testDIDLMetadataGeneration passed")

        let soap = DLNAProtocol.soapEnvelope(
            serviceType: "urn:schemas-upnp-org:service:AVTransport:1",
            action: "SetAVTransportURI",
            arguments: ["InstanceID": "0", "CurrentURI": "http://example.com/test.mp4"]
        )
        assert(soap.contains("<s:Envelope"), "SOAP envelope tag missing")
        assert(soap.contains("<u:SetAVTransportURI xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"), "SOAP action missing")
        assert(soap.contains("<InstanceID>0</InstanceID>"), "SOAP param missing")
        print("  testSOAPEnvelopeBuilder passed")

        // 2. Samsung Legacy Protocol
        let handshake = SamsungLegacyProtocol.handshakeFrame(appName: "SmartCastKit", id: "smartcastkit", ip: "192.168.1.50", mac: "AA:BB:CC:DD:EE:FF")
        assert(handshake.count > 10, "Handshake too short")
        assert(handshake[0] == 0x00, "Handshake delimiter wrong")

        let key = SamsungLegacyProtocol.keyFrame("KEY_VOLDOWN")
        assert(key.count > 5, "Key frame too short")
        assert(key[0] == 0x00, "Key frame delimiter wrong")
        print("  testSamsungLegacyFrames passed")

        // 3. Samsung Tizen WebSocket Protocol
        let urlWithToken = SamsungTizenClient.connectionURL(ip: "192.168.1.50", appName: "SmartCast", token: "12345678")
        assert(urlWithToken != nil, "URL generation failed")
        assert(urlWithToken!.absoluteString.contains("wss://192.168.1.50:8002/api/v2/channels/samsung.remote.control"), "URL missing endpoint")
        assert(urlWithToken!.absoluteString.contains("token=12345678"), "URL missing token")

        let urlWithoutToken = SamsungTizenClient.connectionURL(ip: "192.168.1.50", appName: "SmartCast", token: nil)
        assert(urlWithoutToken != nil, "URL without token generation failed")
        assert(!urlWithoutToken!.absoluteString.contains("token="), "URL should not contain token")

        let json = """
        {
            "event": "ms.channel.connect",
            "data": {
                "token": "987654321",
                "clients": []
            }
        }
        """
        assert(SamsungTizenClient.parseToken(fromConnectEvent: json) == "987654321", "Token parse failed")
        print("  testSamsungTizenURLAndToken passed")

        // 4. Wake on LAN Magic Packet
        let mac = "00:11:22:33:44:55"
        let payload = WakeOnLAN.magicPacketPayload(for: mac)
        assert(payload != nil, "Payload is nil")
        assert(payload?.count == 102, "Payload length must be 102 bytes")
        if let payload {
            for i in 0..<6 {
                assert(payload[i] == 0xFF, "Magic packet header byte must be 0xFF")
            }
        }
        assert(WakeOnLAN.magicPacketPayload(for: "invalid_mac") == nil, "Invalid MAC should return nil")
        print("  testWakeOnLANMagicPacket passed")

        // 5. Device Preferred Transport
        let tv = Device(
            ip: "192.168.1.42",
            name: "Living Room Samsung TV",
            manufacturer: "Samsung Electronics",
            model: "QN90B",
            supportedTransports: [.samsungTizen, .dlna]
        )
        assert(tv.preferredRemoteTransport == .samsungTizen, "Preferred remote should be samsungTizen")
        assert(tv.preferredPlaybackTransport == .dlna, "Preferred playback should be dlna")
        print("  testDevicePreferredTransports passed")

        print("All 7 test suites passed.")
    }
}
