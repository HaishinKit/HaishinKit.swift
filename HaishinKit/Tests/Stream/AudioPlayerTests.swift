@preconcurrency import AVFoundation
import Testing

@testable import HaishinKit

@Suite struct AudioPlayerTests {
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
