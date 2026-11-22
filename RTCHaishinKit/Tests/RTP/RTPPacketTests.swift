import AVFoundation
import Foundation
import Testing

@testable import RTCHaishinKit

@Suite struct RTPPacketTests {
    @Test func removesCSRCHeaderExtensionsAndPaddingFromMediaPayload() throws {
        let header: [UInt8] = [0xb1, 111, 0, 1, 0, 0, 0, 1, 0, 0, 0, 2]
        let data = Data(header + [0, 0, 0, 3] + [0xbe, 0xde, 0, 1, 0x10, 0x7f, 0, 0] + [0xfc, 0x23, 0, 2])
        let packet = try RTPPacket(data)
        #expect(packet.payload == Data([0xfc, 0x23]))
        #expect(packet.data == data)
    }

    @Test(arguments: [
        Data([0x90, 111, 0, 1, 0, 0, 0, 1, 0, 0, 0, 2, 0xbe, 0xde, 0, 9, 1]),
        Data([0xa0, 111, 0, 1, 0, 0, 0, 1, 0, 0, 0, 2, 1, 8])
    ])
    func rejectsTruncatedExtensionAndInvalidPadding(_ data: Data) {
        #expect(throws: RTPPacket.Error.self) { try RTPPacket(data) }
    }

    @Test func packet1()
 throws {
        let data = Data([128, 226, 2, 7, 0, 1, 201, 8, 14, 44, 247, 214, 28, 76, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 128])
        let packet = try RTPPacket(data)
        #expect(packet.version == 2)
        #expect(packet.padding == false)
        #expect(packet.marker == true)
        #expect(packet.payloadType == 98)
        #expect(packet.sequenceNumber == 519)
        #expect(packet.timestamp == 117000)
        #expect(packet.ssrc == 237828054)
        #expect(packet.data == data)
    }

    @Test func packet2() throws {
        let data = Data([128, 111, 0, 173, 0, 2, 136, 192, 41, 147, 97, 224, 252, 23, 218, 183, 83, 181, 164, 207, 10, 78, 74, 42, 42, 249, 40, 72, 142, 88, 51, 132, 23, 107, 145, 143, 6, 242, 109, 235, 187, 177, 55, 195, 232, 243, 46, 157, 1, 21, 214, 170, 16, 197, 227, 115, 186, 183, 132, 229, 107, 63, 238, 227, 166, 27, 77, 128, 120, 49, 249, 174, 241, 250, 236, 250, 154, 140, 253, 68, 152, 242, 187, 1, 196, 52, 198, 130, 62, 235, 20, 196, 1, 223, 126, 158, 142, 138, 35, 215, 22, 252, 235, 69, 166, 241, 237, 13, 155, 16, 6, 61, 26, 138, 90, 207, 213, 22, 33, 198, 209, 110, 198, 118, 174, 232, 21, 6, 206, 237, 190, 47, 214, 61, 161, 168, 192, 17, 248, 87, 21, 172, 79, 90, 183, 66, 221, 232, 206, 153, 205, 57, 195, 106, 119, 12, 130, 190, 105, 234, 116, 78, 72, 190, 85, 189, 149, 73, 150, 139, 147, 230, 71, 149, 39, 87, 207, 245, 247, 226, 176, 246, 14, 220, 3, 158, 81, 129, 96, 13, 52, 126, 49, 139, 179, 176, 108, 0, 220, 77, 40, 5, 201, 219, 218, 86, 76, 241, 204, 152, 209, 215, 241, 18, 247, 151, 206, 20, 110, 188, 245, 89, 25, 254, 206, 87, 76, 210, 51, 55, 117, 127, 177, 149, 13, 23, 226, 214, 24, 122, 205, 225, 42, 66, 172, 10, 16, 129, 222, 50, 253, 125, 178, 46, 221, 91, 181, 171, 83, 85, 164, 240, 245, 80, 240])
        let packet = try RTPPacket(data)
        #expect(packet.version == 2)
        #expect(packet.padding == false)
        #expect(packet.payloadType == 111)
        #expect(packet.sequenceNumber == 173)
        #expect(packet.data == data)
    }
}
