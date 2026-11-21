import Foundation
@testable import MoQTHaishinKit
import Testing

@Suite struct MoQTAdditionalMessageTests {
    @Test func trackRequests() throws {
        var status = MoQTPayload(Data([2, 1, 1, 97, 1, 98, 1, 0x35, 1]))
        #expect(try MoQTTrackStatus(&status).name == Data([98]))
        var fetch = MoQTPayload(Data([4, 0, 1, 98, 1, 0x21, 4, 1, 2, 3, 4]))
        #expect(try MoQTFetch(&fetch).parameters.fields.first?.value == Data([4, 1, 2, 3, 4]))
        var tracks = MoQTPayload(Data([6, 0, 0]))
        #expect(try MoQTSubscribeTracks(&tracks).namespacePrefix.isEmpty)
    }

    @Test func publisherMessages() throws {
        var publish = MoQTPayload(Data([1, 0, 1, 98, 42, 1, 0x36, 6, 8, 30]))
        let message = try MoQTPublish(&publish)
        #expect(message.trackAlias == 42)
        #expect(message.message.data == Data([0x1d, 10, 1, 0, 1, 98, 42, 1, 0x36, 6, 8, 30]))
        #expect(message.trackProperties.first?.type == 8)
        var skipped = MoQTPayload(Data([1, 1, 97, 1, 98]))
        #expect(try MoQTPublishSkipped(&skipped).namespaceSuffix == [Data([97])])
        var done = MoQTPayload(Data([0, 1, 2, 111, 107]))
        #expect(try MoQTPublishDone(&done).reasonPhrase == "ok")
        var notify = MoQTPayload(Data([2, 9, 1, 2, 8, 1]))
        #expect(try MoQTPublishStateNotify(&notify).parameters.fields.map(\.type) == [9, 0x11])
    }

    @Test func updateAndStatusResponse() throws {
        var update = MoQTPayload(Data([4, 1, 0x23, 1, 0x20, 128]))
        let message = try MoQTRequestUpdate(&update)
        #expect(message.requestId == 4)
        #expect(message.message.data == Data([2, 6, 4, 1, 0x23, 1, 0x20, 128]))
        var encoded = MoQTPayload()
        message.parameters.encode(into: &encoded)
        #expect(encoded.data == Data([1, 0x23, 1, 0x20, 128]))
        var ok = MoQTPayload(Data([1, 9, 4, 5, 8, 1]))
        let response = try MoQTRequestOk(&ok, includesTrackInformation: true)
        #expect(response.largestGroupId == 4)
        #expect(response.largestObjectId == 5)
        #expect(response.trackProperties.first?.type == 8)
    }
}
