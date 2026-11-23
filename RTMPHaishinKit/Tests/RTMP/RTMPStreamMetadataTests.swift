import HaishinKit
import Testing

@testable import RTMPHaishinKit

@Suite struct RTMPStreamMetadataTests {
    @Test func publishingMergesFieldsAndDoesNotRetainThem() async throws {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        let publishing = Task {
            try await stream.publish("test", type: .live, metadata: [
                "encoder": "Example", "duration": 123, "videodatarate": 4500, "2026": "season"
            ])
        }
        try await wait(for: .publish, on: stream)
        await receiveMetadata(["encoder": "Received", "title": "Other stream"], on: stream)
        await respond("NetStream.Publish.Start", on: stream)
        _ = try await publishing.value
        let metadata = await stream.metadata
        #expect(metadata["encoder"] as? String == "Example")
        #expect(metadata["duration"] as? Int == 0)
        #expect(metadata["videodatarate"] as? Int == 4500)
        #expect(metadata["2026"] as? String == "season")
        #expect(metadata["title"] as? String == nil)
        try await close(stream, code: "NetStream.Unpublish.Success")
        try await publish(stream)
        #expect(await stream.metadata["encoder"] as? String == nil)
        #expect(await stream.metadata["videodatarate"] as? Int == nil)
        try await close(stream, code: "NetStream.Unpublish.Success")
        try await publish(stream, metadata: ["encoder": "Next"])
        #expect(await stream.metadata["encoder"] as? String == "Next")
        try await close(stream, code: "NetStream.Unpublish.Success")
    }

    @Test func publishingDoesNotReusePlaybackMetadata() async throws {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        let playing = Task { try await stream.play("test") }
        try await wait(for: .play, on: stream)
        await respond("NetStream.Play.Start", on: stream)
        _ = try await playing.value
        await receiveMetadata(["title": "Playback title"], on: stream)
        try await close(stream, code: "NetStream.Play.Stop")
        #expect(await stream.metadata["title"] as? String == "Playback title")
        try await publish(stream)
        #expect(await stream.metadata["title"] as? String == nil)
        try await close(stream, code: "NetStream.Unpublish.Success")
    }

    @Test func originalPublishMethodReferenceRemainsAvailable() async throws {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        let originalPublish = stream.publish(_:type:)
        let publishing = Task { try await originalPublish("test", .live) }
        try await wait(for: .publish, on: stream)
        await respond("NetStream.Publish.Start", on: stream)
        _ = try await publishing.value
        #expect(await stream.metadata["duration"] as? Int == 0)
        try await close(stream, code: "NetStream.Unpublish.Success")
    }

    private func receiveMetadata(_ fields: AMFObject, on stream: RTMPStream) async {
        await stream.dispatch(RTMPDataMessage(
            streamId: 0,
            objectEncoding: .amf0,
            timestamp: 0,
            handlerName: "onMetaData",
            arguments: [AMFArray(fields)]
        ), type: .zero)
    }

    private func respond(_ code: String, on stream: RTMPStream) async {
        await stream.dispatch(RTMPCommandMessage(
            streamId: 0,
            transactionId: 0,
            objectEncoding: .amf0,
            commandName: "onStatus",
            commandObject: nil,
            arguments: [["level": "status", "code": code] as AMFObject]
        ), type: .zero)
    }

    private func publish(_ stream: RTMPStream, metadata: AMFObject = [:]) async throws {
        let publishing = Task { try await stream.publish("test", metadata: metadata) }
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
