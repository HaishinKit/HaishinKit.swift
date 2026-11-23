import HaishinKit
import Testing

@testable import RTMPHaishinKit

@Suite struct RTMPStreamMetadataTests {
    @Test func publishingTransformsFieldsAndDoesNotRetainCallback() async throws {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        let publishing = Task {
            try await stream.publish("test", type: .live) { generated in
                #expect(generated["duration"] as? Int == 0)
                var metadata = generated
                metadata.removeValue(forKey: "duration")
                metadata["encoder"] = "Example"
                metadata["videodatarate"] = 4500
                metadata["2026"] = "season"
                return metadata
            }
        }
        try await wait(for: .publish, on: stream)
        await receiveMetadata(["encoder": "Received", "title": "Other stream"], on: stream)
        await respond("NetStream.Publish.Start", on: stream)
        _ = try await publishing.value
        let metadata = await stream.metadata
        #expect(metadata["encoder"] as? String == "Example")
        #expect(metadata.dict.index(forKey: "duration") == nil)
        #expect(metadata["videodatarate"] as? Int == 4500)
        #expect(metadata["2026"] as? String == "season")
        #expect(metadata["title"] as? String == nil)
        try await close(stream, code: "NetStream.Unpublish.Success")
        try await publish(stream)
        #expect(await stream.metadata["encoder"] as? String == nil)
        #expect(await stream.metadata["videodatarate"] as? Int == nil)
        try await close(stream, code: "NetStream.Unpublish.Success")
        try await publish(stream, metadata: { _ in ["encoder": "Next", "duration": 123] })
        #expect(await stream.metadata["encoder"] as? String == "Next")
        #expect(await stream.metadata["duration"] as? Int == 123)
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

    @Test func nilCallbackResultSkipsMetadataAndEmptyResultIsPreserved() async throws {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        let (inputs, captured) = AsyncStream<AMFObject>.makeStream()
        await receiveMetadata(["title": "Old metadata"], on: stream)
        try await publish(stream, metadata: { generated in
            captured.yield(generated)
            return nil
        })
        captured.finish()
        var calls = 0
        for await input in inputs {
            calls += 1
            #expect(input["duration"] as? Int == 0)
        }
        #expect(calls == 1)
        #expect(await stream.metadata.dict.isEmpty)
        try await close(stream, code: "NetStream.Unpublish.Success")
        try await publish(stream, metadata: { _ in [:] })
        #expect(await stream.metadata.dict.isEmpty)
        try await close(stream, code: "NetStream.Unpublish.Success")
    }

    @Test func stoppingDoesNotInvokeMetadataCallback() async throws {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        try await publish(stream)
        let (inputs, captured) = AsyncStream<AMFObject>.makeStream()
        let stopping = Task {
            try await stream.publish(nil) { generated in
                captured.yield(generated)
                return generated
            }
        }
        try await wait(for: .idle, on: stream)
        await respond("NetStream.Unpublish.Success", on: stream)
        _ = try await stopping.value
        captured.finish()
        var calls = 0
        for await _ in inputs { calls += 1 }
        #expect(calls == 0)
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

    private func publish(_ stream: RTMPStream, metadata: @escaping @Sendable (AMFObject) -> AMFObject? = { $0 }) async throws {
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
