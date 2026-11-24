@preconcurrency import AVFoundation
import Testing

@testable import HaishinKit
@testable import RTMPHaishinKit

@Suite struct RTMPAudioPlaybackTests {
    @Test func attachingAndReplacingAudioPlayerDuringPlaybackRendersSound() async throws {
        let stream = RTMPStream(connection: RTMPConnection())
        let incoming = await stream.incoming
        let output = AudioOutput()
        await stream.addOutput(output)
        await incoming.startRunning()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        var players: [AudioPlayer] = []
        var engines: [AVAudioEngine] = []
        defer { engines.forEach { $0.stop() } }
        // Ensure decoding has already started before attaching any output player.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while output.count == 0, ContinuousClock.now < deadline {
            await incoming.append(try buffer(format), when: AVAudioTime(sampleTime: 0, atRate: 48_000))
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(output.count > 0)
        for _ in 0..<2 {
            let engine = AVAudioEngine()
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
            _ = engine.mainMixerNode
            try engine.start()
            engines.append(engine)
            let player = AudioPlayer(audioEngine: engine)
            players.append(player)
            await stream.attachAudioPlayer(player)
            let rendered = try #require(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024))
            let initialCount = output.count
            for index in 0..<32 {
                await incoming.append(try buffer(format), when: AVAudioTime(sampleTime: Int64(index * 1024), atRate: 48_000))
                try await waitForAudio(output, count: initialCount + index + 1)
            }
            var peak: Float = 0
            for _ in 0..<16 {
                await Task.yield()
                if try engine.renderOffline(1024, to: rendered) == .success, let samples = rendered.floatChannelData?.pointee {
                    for index in 0..<Int(rendered.frameLength) { peak = max(peak, abs(samples[index])) }
                }
            }
            #expect(peak > 0.1)
        }
        await incoming.stopRunning()
        await stream.attachAudioPlayer(nil)
        withExtendedLifetime(players) {}
    }

    private func buffer(_ format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        let samples = try #require(buffer.floatChannelData?.pointee)
        for index in 0..<1024 { samples[index] = 0.25 }
        return buffer
    }

    private func waitForAudio(_ output: AudioOutput, count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while output.count < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(output.count >= count)
    }

    private final class AudioOutput: StreamOutput, @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        func stream(_ stream: some StreamConvertible, didOutput buffer: CMSampleBuffer) {}
        func stream(_ stream: some StreamConvertible, didOutput audio: AVAudioBuffer, when: AVAudioTime) {
            lock.lock()
            defer { lock.unlock() }
            value += 1
        }
    }
}
