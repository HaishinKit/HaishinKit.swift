import Foundation
@testable import MoQTHaishinKit
import Testing

@Suite struct MoQTFetchDecoderTests {
    @Test func objectDeltasAndRangeMarkers() throws {
        var decoder = MoQTFetchDecoder()
        var data = MoQTPayload(Data([0x1c, 2, 4, 128, 1, 65, 0, 1, 66, 0x80, 0x80, 0x0c, 0, 0, 1, 67]))
        let first = try decoder.decode(&data)
        let second = try decoder.decode(&data)
        let marker = try decoder.decode(&data)
        let third = try decoder.decode(&data)
        #expect(first?.groupId == 2)
        #expect(first?.id == 4)
        #expect(second?.id == 5)
        #expect(marker == nil)
        #expect(third?.groupId == 3)
        #expect(third?.id == 0)
        #expect(data.bytesAvailable == 0)
    }

    @Test func truncatedObjectDoesNotAdvanceDeltaState() throws {
        var decoder = MoQTFetchDecoder()
        var truncated = MoQTPayload(Data([0x1c, 2, 4, 128, 1]))
        #expect(throws: MoQTPayload.Error.eof) { try decoder.decode(&truncated) }
        var complete = MoQTPayload(Data([0x1c, 2, 4, 128, 1, 65]))
        #expect(try decoder.decode(&complete)?.groupId == 2)
    }
}
