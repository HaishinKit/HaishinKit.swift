import Foundation
@testable import MoQTHaishinKit
import Testing

@Suite struct MoQTStreamHeaderSubgroupTests {
    @Test func subgroupObjectDeltas() throws {
        var payload = MoQTPayload(Data([0x12, 0x03, 0x04, 0xff, 0x06, 0x01, 0x41, 0x00, 0x01, 0x42]))
        let flags = try payload.getInt()
        let header = try MoQTStreamHeaderSubgroup(flags: flags, payload: &payload)
        #expect(header.publisherPriority == 255)
        let first = try MoQTObject.readSubgroup(&payload, header: header, previous: nil, subgroupId: nil)
        let second = try MoQTObject.readSubgroup(&payload, header: header, previous: first.id, subgroupId: first.subgroupId)
        #expect(first.id == 6)
        #expect(second.id == 7)
        #expect(second.trackAlias == 3)
        #expect(second.groupId == 4)
        #expect(second.subgroupId == 6)
        #expect(second.data == Data([0x42]))
        #expect(payload.bytesAvailable == 0)
    }

    @Test func datagramPayloadConsumesRemainder() throws {
        var payload = MoQTPayload(Data([0x0c, 0x03, 0x04, 0x41, 0x42]))
        let decoded = try MoQTObject.readDatagram(&payload)
        let object = try #require(decoded)
        #expect(object.id == 0)
        #expect(object.trackAlias == 3)
        #expect(object.groupId == 4)
        #expect(object.data == Data([0x41, 0x42]))
    }

    @Test func subgroupEncoding() throws {
        let header = MoQTStreamHeaderSubgroup(trackAlias: 2, groupId: 3, subgroupId: 4, publisherPriority: 255)
        var payload = MoQTPayload(header.payload)
        try MoQTObject(id: 5, status: nil, data: Data([0xaa])).encode(after: nil, into: &payload)
        try MoQTObject(id: 6, status: 3, data: Data()).encode(after: 5, into: &payload)
        #expect(payload.data == Data([0x14, 2, 3, 4, 255, 5, 1, 0xaa, 0, 0, 3]))
    }
}
