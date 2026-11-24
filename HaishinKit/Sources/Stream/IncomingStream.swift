@preconcurrency import AVFoundation
import Foundation

/// An actor that provides a stream playback feature.
package final actor IncomingStream {
    public private(set) var isRunning = false
    /// The sound transform value control.
    public var soundTransfrom: SoundTransform? {
        get async {
            return await audioPlayerNode?.soundTransfrom
        }
    }
    private lazy var mediaLink = MediaLink()
    private lazy var audioCodec = AudioCodec()
    private lazy var videoCodec = VideoCodec()
    private weak var stream: (any _Stream)?
    private var audioPlayerNode: AudioPlayerNode?

    /// Creates a new instance.
    package init(_ stream: some _Stream) {
        self.stream = stream
    }

    /// Sets the sound transform value control.
    public func setSoundTransform(_ soundTransfrom: SoundTransform) async {
        await audioPlayerNode?.setSoundTransfrom(soundTransfrom)
    }

    /// Appends a sample buffer for playback.
    public func append(_ buffer: CMSampleBuffer) {
        switch buffer.formatDescription?.mediaType {
        case .audio:
            audioCodec.append(buffer)
        case .video:
            videoCodec.append(buffer)
        default:
            break
        }
    }

    /// Appends an audio buffer for playback.
    public func append(_ buffer: AVAudioBuffer, when: AVAudioTime) {
        audioCodec.append(buffer, when: when)
    }

    /// Attaches an audio player.
    public func attachAudioPlayer(_ audioPlayer: AudioPlayer?) async {
        await audioPlayerNode?.detach()
        audioPlayerNode = await audioPlayer?.makePlayerNode()
        await mediaLink.setAudioPlayer(audioPlayerNode)
    }
}

extension IncomingStream: AsyncRunner {
    // MARK: AsyncRunner
    public func startRunning() {
        guard !isRunning else {
            return
        }
        audioCodec.settings.format = .pcm
        videoCodec.startRunning()
        audioCodec.startRunning()
        isRunning = true
        Task {
            await mediaLink.startRunning()
            for await video in await mediaLink.dequeue {
                await stream?.didReceive(video)
            }
        }
        Task {
            for await video in videoCodec.outputStream {
                await mediaLink.enqueue(video)
            }
        }
        Task {
            await audioPlayerNode?.startRunning()
            for await audio in audioCodec.outputStream {
                await audioPlayerNode?.enqueue(audio.0, when: audio.1)
                await stream?.didReceive(audio.0, when: audio.1)
            }
        }
    }

    public func stopRunning() {
        guard isRunning else {
            return
        }
        videoCodec.stopRunning()
        audioCodec.stopRunning()
        Task { await mediaLink.stopRunning() }
        Task { await audioPlayerNode?.stopRunning() }
        isRunning = false
    }
}
