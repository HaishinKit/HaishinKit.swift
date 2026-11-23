import Testing

@testable import RTMPHaishinKit

@Suite struct RTMPStreamMetadataTests {
    @Test func publishingMergesAndReplacesMetadata() async throws {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        try await stream.setMetadata(["encoder": "Example", "duration": 123, "videodatarate": 4500])
        let publishing = Task { try await stream.publish("test") }
        while await stream.readyState != .publish {
            await Task.yield()
        }
        await stream.dispatch(RTMPCommandMessage(
            streamId: 0,
            transactionId: 0,
            objectEncoding: .amf0,
            commandName: "onStatus",
            commandObject: nil,
            arguments: [["level": "status", "code": "NetStream.Publish.Start"] as AMFObject]
        ), type: .zero)
        _ = try await publishing.value
        let metadata = await stream.metadata
        #expect(metadata["encoder"] as? String == "Example")
        #expect(metadata["duration"] as? Int == 0)
        #expect(metadata["videodatarate"] as? Int == 4500)
        try await stream.setMetadata([:])
        #expect(await stream.metadata.dict.isEmpty)
    }

    @Test func playbackClearsMetadataAndRejectsChanges() async throws {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        try await stream.setMetadata(["encoder": "Example"])
        let playing = Task { try await stream.play("test") }
        while await stream.readyState != .play {
            await Task.yield()
        }
        #expect(await stream.metadata.dict.isEmpty)
        await #expect {
            try await stream.setMetadata(["encoder": "Rejected"])
        } throws: { error in
            if case RTMPStream.Error.invalidState = error { return true }
            return false
        }
        await stream.dispatch(RTMPCommandMessage(
            streamId: 0,
            transactionId: 0,
            objectEncoding: .amf0,
            commandName: "onStatus",
            commandObject: nil,
            arguments: [["level": "status", "code": "NetStream.Play.Start"] as AMFObject]
        ), type: .zero)
        _ = try await playing.value
        await #expect {
            try await stream.setMetadata(["encoder": "Rejected"])
        } throws: { error in
            if case RTMPStream.Error.invalidState = error { return true }
            return false
        }
    }
}
