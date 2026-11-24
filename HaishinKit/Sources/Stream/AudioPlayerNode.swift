@preconcurrency import AVFoundation
import Foundation

final actor AudioPlayerNode {
    static let bufferCounts: Int = 10

    var currentTime: TimeInterval? {
        if playerNode.isPlaying {
            guard
                let nodeTime = playerNode.lastRenderTime,
                nodeTime.isSampleTimeValid || nodeTime.isHostTimeValid,
                let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
                return nil
            }
            return TimeInterval(playerTime.sampleTime) / playerTime.sampleRate
        }
        return nil
    }
    private(set) var isPaused = false
    private(set) var isRunning = false
    private(set) var soundTransfrom = SoundTransform()
    private let playerNode: AVAudioPlayerNode
    private var audioTime = AudioTime()
    private var scheduledAudioBuffers: Int = 0
    private var playbackGeneration: UInt = 0
    private var isBuffering = true
    private weak var player: AudioPlayer?
    private var format: AVAudioFormat? {
        didSet {
            guard format != oldValue else {
                return
            }
            Task { [format] in
                await player?.connect(self, format: format)
            }
        }
    }

    init(player: AudioPlayer, playerNode: AVAudioPlayerNode) {
        self.player = player
        self.playerNode = playerNode
    }

    func setSoundTransfrom(_ soundTransfrom: SoundTransform) {
        soundTransfrom.apply(playerNode)
    }

    func enqueue(_ audioBuffer: AVAudioBuffer, when: AVAudioTime) async {
        guard isRunning else {
            return
        }
        let generation = playbackGeneration
        format = audioBuffer.format
        guard
            let audioBuffer = audioBuffer as? AVAudioPCMBuffer,
            await player?.isConnected(self) == true,
            isRunning, generation == playbackGeneration else {
            return
        }
        if !audioTime.hasAnchor {
            // Scheduled sample times belong to the player, not the engine's render clock.
            audioTime.anchor(AVAudioTime(sampleTime: 0, atRate: audioBuffer.format.sampleRate))
        }
        let scheduledTime = audioTime.at
        audioTime.advanced(Int64(audioBuffer.frameLength))
        scheduledAudioBuffers += 1
        if !isPaused && !playerNode.isPlaying && Self.bufferCounts <= scheduledAudioBuffers {
            playerNode.play()
        }
        Task {
            guard isRunning, generation == playbackGeneration else {
                return
            }
            await playerNode.scheduleBuffer(audioBuffer, at: scheduledTime)
            guard isRunning, generation == playbackGeneration else {
                return
            }
            scheduledAudioBuffers -= 1
            if scheduledAudioBuffers == 0 {
                isBuffering = true
            }
        }
    }

    func detach() async {
        stopRunning()
        await player?.detach(self)
    }
}

extension AudioPlayerNode: AsyncRunner {
    // MARK: AsyncRunner
    func startRunning() {
        guard !isRunning else {
            return
        }
        scheduledAudioBuffers = 0
        playbackGeneration &+= 1
        audioTime.reset()
        isRunning = true
    }

    func stopRunning() {
        guard isRunning else {
            return
        }
        isRunning = false
        playbackGeneration &+= 1
        playerNode.stop()
        playerNode.reset()
        audioTime.reset()
        format = nil
    }
}

extension AudioPlayerNode: Hashable {
    // MARK: Hashable
    nonisolated public static func == (lhs: AudioPlayerNode, rhs: AudioPlayerNode) -> Bool {
        lhs === rhs
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
