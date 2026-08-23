import XCTest
@testable import SmartCastKit

final class SmartCastKitTests: XCTestCase {

    func testXMLEscaping() {
        let input = "Stranger Things & Friends <\"Special's\">"
        let escaped = DLNAProtocol.xmlEscape(input)
        XCTAssertEqual(escaped, "Stranger Things &amp; Friends &lt;&quot;Special&apos;s&quot;&gt;")
    }

    func testDLNATimestampFormattingAndParsing() {
        let seconds: Double = 3723
        let formatted = DLNAProtocol.formatTimestamp(seconds)
        XCTAssertEqual(formatted, "01:02:03")
        XCTAssertEqual(DLNAProtocol.parseTimestamp(formatted), seconds)
    }

    func testDIDLMetadataGeneration() {
        let media = MediaItem(
            url: URL(string: "http://192.168.1.100:8096/stream.mp4")!,
            title: "Avatar & Pandora",
            mimeType: "video/mp4",
            posterURL: URL(string: "http://192.168.1.100:8096/poster.jpg")!
        )
        let xml = DLNAProtocol.didlMetadata(for: media)
        XCTAssertTrue(xml.contains("<dc:title>Avatar &amp; Pandora</dc:title>"))
        XCTAssertTrue(xml.contains("http://192.168.1.100:8096/stream.mp4"))
        XCTAssertTrue(xml.contains("http://192.168.1.100:8096/poster.jpg"))
    }

    func testSOAPEnvelopeBuilder() {
        let soap = DLNAProtocol.soapEnvelope(
            serviceType: "urn:schemas-upnp-org:service:AVTransport:1",
            action: "SetAVTransportURI",
            arguments: ["InstanceID": "0", "CurrentURI": "http://example.com/test.mp4"]
        )
        XCTAssertTrue(soap.contains("<s:Envelope"))
        XCTAssertTrue(soap.contains("<u:SetAVTransportURI xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"))
        XCTAssertTrue(soap.contains("<InstanceID>0</InstanceID>"))
    }

    func testSamsungLegacyFrames() {
        let handshake = SamsungLegacyProtocol.handshakeFrame(appName: "SmartCastKit", id: "smartcastkit", ip: "192.168.1.50", mac: "AA:BB:CC:DD:EE:FF")
        XCTAssertGreaterThan(handshake.count, 10)
        XCTAssertEqual(handshake[0], 0x00)

        let key = SamsungLegacyProtocol.keyFrame("KEY_VOLDOWN")
        XCTAssertGreaterThan(key.count, 5)
        XCTAssertEqual(key[0], 0x00)
    }

    func testSamsungTizenURLAndToken() {
        let urlWithToken = SamsungTizenClient.connectionURL(ip: "192.168.1.50", appName: "SmartCast", token: "12345678")
        XCTAssertNotNil(urlWithToken)
        XCTAssertTrue(urlWithToken!.absoluteString.contains("wss://192.168.1.50:8002/api/v2/channels/samsung.remote.control"))
        XCTAssertTrue(urlWithToken!.absoluteString.contains("token=12345678"))

        let urlWithoutToken = SamsungTizenClient.connectionURL(ip: "192.168.1.50", appName: "SmartCast", token: nil)
        XCTAssertNotNil(urlWithoutToken)
        XCTAssertFalse(urlWithoutToken!.absoluteString.contains("token="))

        let json = """
        {
            "event": "ms.channel.connect",
            "data": {
                "token": "987654321",
                "clients": []
            }
        }
        """
        XCTAssertEqual(SamsungTizenClient.parseToken(fromConnectEvent: json), "987654321")
    }

    func testWakeOnLANMagicPacket() {
        let mac = "00:11:22:33:44:55"
        let payload = WakeOnLAN.magicPacketPayload(for: mac)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.count, 102)
        if let payload {
            for i in 0..<6 {
                XCTAssertEqual(payload[i], 0xFF)
            }
        }
        XCTAssertNil(WakeOnLAN.magicPacketPayload(for: "invalid_mac"))
    }

    func testDevicePreferredTransports() {
        let tv = Device(
            ip: "192.168.1.42",
            name: "Living Room Samsung TV",
            manufacturer: "Samsung Electronics",
            model: "QN90B",
            supportedTransports: [.samsungTizen, .dlna]
        )
        XCTAssertEqual(tv.preferredRemoteTransport, .samsungTizen)
        XCTAssertEqual(tv.preferredPlaybackTransport, .dlna)
    }
}
