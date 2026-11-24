@preconcurrency import AVFoundation
import Testing

@testable import HaishinKit

@Suite struct AudioPlayerTests {
    @Test func enqueueContinuesAfterAStopOvertakesAStart() async throws {
        let engine = AVAudioEngine()
        defer { engine.stop() }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        let player = AudioPlayer(audioEngine: engine)
        let node = await player.makePlayerNode()
        await player.connect(node, format: format)
        await node.startRunning()
        // Model a restart reaching the node before the previous stream's queued stop.
        await node.startRunning()
        await node.stopRunning()
        for _ in 0..<12 {
            let input = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
            input.frameLength = 1024
            let samples = try #require(input.floatChannelData?.pointee)
            for index in 0..<1024 { samples[index] = 0.25 }
            await node.enqueue(input, when: AVAudioTime(sampleTime: 0, atRate: 48_000))
        }
        let output = try #require(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024))
        var peak: Float = 0
        for _ in 0..<16 {
            await Task.yield()
            if try engine.renderOffline(1024, to: output) == .success, let samples = output.floatChannelData?.pointee {
                for index in 0..<Int(output.frameLength) { peak = max(peak, abs(samples[index])) }
            }
        }
        #expect(peak > 0.1)
        await node.detach()
    }

    @Test func playbackStartsAfterTheEngineClockHasAdvanced() async throws {
        let engine = AVAudioEngine()
        defer { engine.stop() }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        let player = AudioPlayer(audioEngine: engine)
        let node = await player.makePlayerNode()
        await player.connect(node, format: format)
        await node.startRunning()
        let output = try #require(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024))
        // Advance the engine before starting this player's own timeline.
        for _ in 0..<100 {
            _ = try engine.renderOffline(1024, to: output)
        }
        for _ in 0..<12 {
            let input = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
            input.frameLength = 1024
            let channel = try #require(input.floatChannelData?.pointee)
            for index in 0..<1024 { channel[index] = 0.25 }
            await node.enqueue(input, when: AVAudioTime(sampleTime: 0, atRate: 48_000))
        }
        var peak: Float = 0
        for _ in 0..<16 {
            await Task.yield()
            if try engine.renderOffline(1024, to: output) == .success, let channel = output.floatChannelData?.pointee {
                for index in 0..<Int(output.frameLength) { peak = max(peak, abs(channel[index])) }
            }
        }
        #expect(peak > 0.1)
        await node.detach()
    }

    @Test func playbackRestartsWithoutKeepingThePreviousTimeline() async throws {
        let engine = AVAudioEngine()
        defer { engine.stop() }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        let player = AudioPlayer(audioEngine: engine)
        let node = await player.makePlayerNode()
        await player.connect(node, format: format)
        let output = try #require(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024))
        for _ in 0..<2 {
            await node.startRunning()
            for _ in 0..<12 {
                let input = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
                input.frameLength = 1024
                let samples = try #require(input.floatChannelData?.pointee)
                for index in 0..<1024 { samples[index] = 0.25 }
                await node.enqueue(input, when: AVAudioTime(sampleTime: 0, atRate: 48_000))
            }
            var peak: Float = 0
            for _ in 0..<8 {
                await Task.yield()
                if try engine.renderOffline(1024, to: output) == .success, let samples = output.floatChannelData?.pointee {
                    for index in 0..<Int(output.frameLength) { peak = max(peak, abs(samples[index])) }
                }
            }
            #expect(peak > 0.1)
            await node.stopRunning()
        }
        await node.detach()
    }

    @Test func unusedNodeHasNoPlaybackClock() async {
        let player = AudioPlayer(audioEngine: AVAudioEngine())
        let node = await player.makePlayerNode()
        #expect(await node.currentTime == nil)
        await node.detach()
    }

    @Test(.enabled(if: !TestEnvironment.isCI))
    func repeatedlyDetachesConnectedPlaybackNodes() async throws {
        let engine = AVAudioEngine()
        defer { engine.stop() }
        let player = AudioPlayer(audioEngine: engine)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        for _ in 0..<3 {
            let node = await player.makePlayerNode()
            await player.connect(node, format: format)
            #expect(await player.isConnected(node))
            await node.detach()
            #expect(await player.isConnected(node) == false)
            #expect(engine.isRunning)
        }
    }

    @Test(.enabled(if: !TestEnvironment.isCI))
    func detachingUnusedNodePreservesAnAlreadyRunningEngine() async throws {
        let engine = AVAudioEngine()
        _ = engine.mainMixerNode
        try engine.start()
        defer { engine.stop() }
        let player = AudioPlayer(audioEngine: engine)
        let unusedNode = await player.makePlayerNode()
        await unusedNode.detach()
        #expect(engine.isRunning)
    }
}
