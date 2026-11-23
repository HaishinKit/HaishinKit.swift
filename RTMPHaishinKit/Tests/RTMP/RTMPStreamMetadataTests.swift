import HaishinKit
import Testing

@testable import RTMPHaishinKit

@Suite struct RTMPStreamMetadataTests {
    @Test func publishingMergesAndReplacesMetadata() async throws {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        try await stream.setMetadata(["encoder": "Example", "duration": 123, "videodatarate": 4500])
        let publishing = Task { try await stream.publish("test") }
        try await wait(for: .publish, on: stream)
        await stream.dispatch(RTMPDataMessage(
            streamId: 0,
            objectEncoding: .amf0,
            timestamp: 0,
            handlerName: "onMetaData",
            arguments: [AMFArray(["encoder": "Received", "title": "Other stream"])]
        ), type: .zero)
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
        #expect(metadata["title"] as? String == nil)
        try await close(stream, code: "NetStream.Unpublish.Success")
        try await publish(stream)
        #expect(await stream.metadata["encoder"] as? String == nil)
        #expect(await stream.metadata["videodatarate"] as? Int == nil)
        try await stream.setMetadata([:])
        #expect(await stream.metadata.dict.isEmpty)
        try await close(stream, code: "NetStream.Unpublish.Success")
    }

    @Test func playbackClearsMetadataAndRejectsChanges() async throws {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        try await stream.setMetadata(["encoder": "Example"])
        let playing = Task { try await stream.play("test") }
        try await wait(for: .play, on: stream)
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
        await stream.dispatch(RTMPDataMessage(
            streamId: 0,
            objectEncoding: .amf0,
            timestamp: 0,
            handlerName: "onMetaData",
            arguments: [AMFArray(["title": "Playback title"])]
        ), type: .zero)
        try await close(stream, code: "NetStream.Play.Stop")
        #expect(await stream.metadata["title"] as? String == "Playback title")
        try await publish(stream)
        #expect(await stream.metadata["title"] as? String == nil)
        try await close(stream, code: "NetStream.Unpublish.Success")
    }

    private func publish(_ stream: RTMPStream) async throws {
        let publishing = Task { try await stream.publish("test") }
        try await wait(for: .publish, on: stream)
        await stream.dispatch(RTMPCommandMessage(
            streamId: 0,
            transactionId: 0,
            objectEncoding: .amf0,
            commandName: "onStatus",
            commandObject: nil,
            arguments: [["level": "status", "code": "NetStream.Publish.Start"] as AMFObject]
        ), type: .zero)
        _ = try await publishing.value
    }

    private func wait(for state: StreamReadyState, on stream: RTMPStream) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await stream.readyState != state && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(await stream.readyState == state)
    }

    private func close(_ stream: RTMPStream, code: String) async throws {
        let closing = Task { try await stream.close() }
        try await wait(for: .idle, on: stream)
        await stream.dispatch(RTMPCommandMessage(
            streamId: 0,
            transactionId: 0,
            objectEncoding: .amf0,
            commandName: "onStatus",
            commandObject: nil,
            arguments: [["level": "status", "code": code] as AMFObject]
        ), type: .zero)
        _ = try await closing.value
    }
}
