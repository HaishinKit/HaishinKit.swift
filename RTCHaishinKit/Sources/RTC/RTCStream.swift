import AVFoundation
import HaishinKit
import libdatachannel

/// Encodes outgoing media and processes incoming media for a WebRTC stream.
///
/// Use `RTCPeerConnection` to associate media tracks with the stream. Outgoing
/// audio uses Opus, and outgoing video uses H.264.
public actor RTCStream {
    enum Error: Swift.Error {
        case unsupportedCodec
    }

    static let supportedAudioCodecs: [AudioCodecSettings.Format] = [.opus]
    static let supportedVideoCodecs: [VideoCodecSettings.Format] = [.h264]

    let id: String = UUID().uuidString
    private(set) var tracks: [RTCSendableStreamTrack] = []
    /// The readiness state reported by the stream.
    public private(set) var readyState: StreamReadyState = .idle
    /// The selected mixer video track. `UInt8.max` selects mixed output; `nil` disables video delivery.
    public private(set) var videoTrackId: UInt8? = UInt8.max
    /// The selected mixer audio track. `UInt8.max` selects mixed output; `nil` disables audio delivery.
    public private(set) var audioTrackId: UInt8? = UInt8.max
    package lazy var incoming = IncomingStream(self)
    package lazy var outgoing: OutgoingStream = {
        var stream = OutgoingStream()
        stream.audioSettings = .init(channelMap: [0, 0], format: .opus)
        return stream
    }()
    package var outputs: [any StreamOutput] = []
    package var bitRateStrategy: (any StreamBitRateStrategy)?
    private var direction: RTCDirection = .sendonly

    /// Creates a WebRTC media stream with default encoding settings.
    public init() {
    }

    /// Selects the media direction and starts the corresponding processing.
    ///
    /// `.recvonly` starts incoming media processing. `.sendonly` and `.sendrecv` start
    /// outgoing encoding. `.unknown` and `.inactive` do not start or stop processing.
    ///
    /// - Parameter direction: The media direction to use.
    public func setDirection(_ direction: RTCDirection) {
        self.direction = direction
        switch direction {
        case .recvonly:
            Task {
                await incoming.startRunning()
            }
        case .sendonly, .sendrecv:
            outgoing.startRunning()
            Task {
                for await audio in outgoing.audioOutputStream {
                    append(audio.0, when: audio.1)
                }
            }
            Task {
                for await video in outgoing.videoOutputStream {
                    append(video)
                }
            }
            Task {
                for await video in outgoing.videoInputStream {
                    outgoing.append(video: video)
                }
            }
        default:
            break
        }
    }

    /// Removes associated tracks and stops processing for a send-only or receive-only stream.
    ///
    /// This method does not close the peer connection.
    public func close() async {
        tracks.removeAll()
        switch direction {
        case .sendonly:
            outgoing.stopRunning()
        case .recvonly:
            Task {
                await incoming.stopRunning()
            }
        default:
            break
        }
    }

    func addTrack(_ track: RTCSendableStreamTrack) async {
        await track.setDelegate(self)
        tracks.append(track)
    }
}

extension RTCStream: _Stream {
    /// Sets the outgoing audio encoding settings.
    ///
    /// - Parameter audioSettings: Settings that select Opus encoding.
    /// - Throws: An error if the selected format is not Opus.
    public func setAudioSettings(_ audioSettings: AudioCodecSettings) throws {
        guard Self.supportedAudioCodecs.contains(audioSettings.format) else {
            throw Error.unsupportedCodec
        }
        outgoing.audioSettings = audioSettings
    }

    /// Sets the outgoing video encoding settings.
    ///
    /// - Parameter videoSettings: Settings that select H.264 encoding.
    /// - Throws: An error if the selected codec is not H.264.
    public func setVideoSettings(_ videoSettings: VideoCodecSettings) throws {
        guard Self.supportedVideoCodecs.contains(videoSettings.format) else {
            throw Error.unsupportedCodec
        }
        outgoing.videoSettings = videoSettings
    }

    /// Processes an audio or video sample buffer.
    ///
    /// Uncompressed buffers are queued for encoding. Compressed video is sent to
    /// associated tracks, while compressed audio is passed to incoming media processing.
    /// Uncompressed video is also delivered to stream outputs.
    ///
    /// - Parameter sampleBuffer: The sample buffer to process.
    public func append(_ sampleBuffer: CMSampleBuffer) {
        switch sampleBuffer.formatDescription?.mediaType {
        case .video:
            if sampleBuffer.formatDescription?.isCompressed == true {
                Task {
                    for track in tracks {
                        await track.send(sampleBuffer)
                    }
                }
            } else {
                outgoing.append(sampleBuffer)
                outputs.forEach { $0.stream(self, didOutput: sampleBuffer) }
            }
        case .audio:
            if sampleBuffer.formatDescription?.isCompressed == true {
                Task { await incoming.append(sampleBuffer) }
            } else {
                outgoing.append(sampleBuffer)
            }
        default:
            break
        }
    }

    /// Supplies audio for encoding or transmission.
    ///
    /// PCM audio is queued for encoding and delivered to stream outputs.
    /// Compressed audio is sent to associated tracks.
    ///
    /// - Parameters:
    ///   - audioBuffer: The PCM or compressed audio buffer.
    ///   - when: The timestamp associated with the buffer.
    public func append(_ audioBuffer: AVAudioBuffer, when: AVAudioTime) {
        switch audioBuffer {
        case let audioBuffer as AVAudioPCMBuffer:
            outgoing.append(audioBuffer, when: when)
            outputs.forEach { $0.stream(self, didOutput: audioBuffer, when: when) }
        case let audioBuffer as AVAudioCompressedBuffer:
            Task {
                for track in tracks {
                    await track.send(audioBuffer, when: when)
                }
            }
        default:
            break
        }
    }

    /// Passes a network monitoring event to the configured bit rate strategy.
    public func dispatch(_ event: NetworkMonitorEvent) async {
        await bitRateStrategy?.adjustBitrate(event, stream: self)
    }
}

extension RTCStream: RTCTrackDelegate {
    // MARK: RTCTrackDelegate
    nonisolated func track(_ track: RTCTrack, readyStateChanged readyState: RTCTrack.ReadyState) {
    }

    nonisolated func track(_ track: RTCTrack, didOutput buffer: CMSampleBuffer) {
        Task {
            await incoming.append(buffer)
        }
    }

    nonisolated func track(_ track: RTCTrack, didOutput buffer: AVAudioCompressedBuffer, when: AVAudioTime) {
        Task {
            await incoming.append(buffer, when: when)
        }
    }
}

extension RTCStream: MediaMixerOutput {
    // MARK: MediaMixerOutput
    /// Selects a mixer track for the specified media type.
    ///
    /// - Parameters:
    ///   - id: The track ID, `UInt8.max` for mixed output, or `nil` to disable delivery.
    ///   - mediaType: The audio or video media type to configure. Other types are ignored.
    public func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) {
        switch mediaType {
        case .audio:
            audioTrackId = id
        case .video:
            videoTrackId = id
        default:
            break
        }
    }

    /// Receives a video buffer from a mixer and schedules it for processing by the stream.
    nonisolated public func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        Task { await append(sampleBuffer) }
    }

    /// Receives a PCM audio buffer and its timestamp from a mixer and schedules them for processing.
    nonisolated public func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        Task { await append(buffer, when: when) }
    }
}
