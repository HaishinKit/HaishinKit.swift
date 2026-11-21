import Foundation
@testable import MoQTHaishinKit
import Testing

@Suite struct MoQTPayloadTests {
    @Test func variableLengthIntegers() throws {
        let vectors: [(UInt64, [UInt8])] = [
            (0, [0]), (127, [0x7f]), (128, [0x80, 0x80]),
            (16_383, [0xbf, 0xff]), (16_384, [0xc0, 0x40, 0]),
            (1 << 56, [0xff, 1, 0, 0, 0, 0, 0, 0, 0]),
            (.max, Array(repeating: 0xff, count: 9))
        ]
        for (value, bytes) in vectors {
            var writer = MoQTPayload()
            writer.putInt(value)
            #expect(writer.data == Data(bytes))
            var reader = MoQTPayload(Data(bytes))
            #expect(try reader.getInt() == value)
            #expect(reader.bytesAvailable == 0)
        }
    }

    @Test func acceptsNonMinimalInteger() throws {
        var payload = MoQTPayload(Data([0x80, 0x25]))
        #expect(try payload.getInt() == 37)
    }

    @Test func truncatedInteger() {
        var payload = MoQTPayload(Data([0xff, 1, 2]))
        #expect(throws: MoQTPayload.Error.eof) { try payload.getInt() }
    }

    @Test func clientSetup() throws {
        let message = MoQTSetup.clientMessage(authority: "example.com", path: "/live")
        var payload = MoQTPayload(message.data)
        let frame = try MoQTControlMessage(&payload)
        #expect(frame.type == 0x2f00)
        #expect(payload.bytesAvailable == 0)
        var body = MoQTPayload(frame.body)
        let options = try MoQTKeyValue.decode(&body)
        #expect(options.map(\.type) == [1, 5])
        guard case .bytes(let path) = options.first?.value, case .bytes(let authority) = options.last?.value else {
            Issue.record("Missing SETUP options")
            return
        }
        #expect(path == Data("/live".utf8))
        #expect(authority == Data("example.com".utf8))
    }

    @Test func requestError() throws {
        var payload = MoQTPayload(Data([0x05, 0x08, 0x03, 0x01, 0x02, 0x6e, 0x6f, 0x07, 0x01, 0x41]))
        let frame = try MoQTControlMessage(&payload)
        #expect(frame.type == MoQTMessageType.requestError.rawValue)
        var body = MoQTPayload(frame.body)
        let error = try MoQTRequestError(&body)
        #expect(error.code == 3)
        #expect(error.retryAfterMilliseconds == 0)
        #expect(error.reasonPhrase == "no")
        #expect(error.details.map(\.type) == [7])
    }

    @Test func subscribeOK() throws {
        var body = MoQTPayload(Data([0x2a, 0x02, 0x08, 0x10, 0x01, 0x09, 0x05, 0x08, 0x01]))
        let response = try MoQTSubscribeOk(&body)
        #expect(response.trackAlias == 42)
        #expect(response.expires == 16)
        #expect(response.largestGroupId == 9)
        #expect(response.largestObjectId == 5)
        #expect(response.trackProperties.map(\.type) == [8])
    }
}
