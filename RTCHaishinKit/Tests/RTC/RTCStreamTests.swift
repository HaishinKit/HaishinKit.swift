import AVFoundation
import Testing
@testable import HaishinKit
@testable import RTCHaishinKit

@Suite struct RTCStreamTests {
    @Test func duplexLifecycle() async {
        let stream = RTCStream()
        await stream.setDirection(.sendrecv)
        #expect(await stream.isSending)
        #expect(await stream.incoming.isRunning)
        await stream.setDirection(.sendrecv)
        await stream.setDirection(.recvonly)
        #expect(await !stream.isSending)
        #expect(await stream.incoming.isRunning)
        await stream.setDirection(.sendonly)
        #expect(await stream.isSending)
        #expect(await !stream.incoming.isRunning)
        await stream.setDirection(.sendrecv)
        await stream.close()
        #expect(await !stream.isSending)
        #expect(await !stream.incoming.isRunning)
        await stream.setDirection(.sendrecv)
        #expect(await stream.isSending)
        #expect(await stream.incoming.isRunning)
        await stream.close()
    }

    @Test func decodedRemoteAudioIsNotReencoded() async throws {
        let stream = RTCStream()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 960))
        buffer.frameLength = 960
        await stream.setDirection(.sendrecv)
        await stream.didReceive(buffer, when: AVAudioTime(sampleTime: 0, atRate: 48_000))
        #expect(await !stream.hasEncodedInput)
        // Local microphone input still reaches the outgoing encoder.
        await stream.append(buffer, when: AVAudioTime(sampleTime: 0, atRate: 48_000))
        #expect(await stream.hasEncodedInput)
        await stream.close()
    }
}

private extension RTCStream {
    var isSending: Bool { outgoing.isRunning }
    var hasEncodedInput: Bool { outgoing.audioInputFormat != nil }
}
