import AVFAudio
import AVFoundation
import CoreImage
import CoreMedia

/// The interface is the foundation of the RTMPStream and SRTStream.
public protocol StreamConvertible: Actor, MediaMixerOutput {
    /// The current state of the stream.
    var readyState: StreamReadyState { get }
    /// The sound transform value control.
    var soundTransform: SoundTransform? { get async }
    /// The audio compression properties.
    var audioSettings: AudioCodecSettings { get }
    /// The video compression properties.
    var videoSettings: VideoCodecSettings { get }

    /// Sets the bitrate strategy object.
    func setBitRateStrategy(_ bitRateStrategy: (some StreamBitRateStrategy)?)

    /// Sets the audio compression properties.
    func setAudioSettings(_ audioSettings: AudioCodecSettings) throws

    /// Sets the video compression properties.
    func setVideoSettings(_ videoSettings: VideoCodecSettings) throws

    /// Sets the sound transform value control.
    func setSoundTransform(_ soundTransfrom: SoundTransform) async

    /// Sets the video input buffer counts.
    func setVideoInputBufferCounts(_ videoInputBufferCounts: Int)

    /// Appends a CMSampleBuffer.
    /// - Parameters:
    ///   - sampleBuffer:The sample buffer to append.
    func append(_ sampleBuffer: CMSampleBuffer)

    /// Appends an AVAudioBuffer.
    /// - Parameters:
    ///   - audioBuffer:The audio buffer to append.
    ///   - when: The audio time to append.
    func append(_ audioBuffer: AVAudioBuffer, when: AVAudioTime)

    /// Attaches an audio player instance for playback.
    func attachAudioPlayer(_ audioPlayer: AudioPlayer?) async

    /// Adds an output observer.
    func addOutput(_ obserber: some StreamOutput)

    /// Removes an output observer.
    func removeOutput(_ observer: some StreamOutput)

    /// Dispatch a network monitor event.
    func dispatch(_ event: NetworkMonitorEvent) async
}

package protocol _Stream: StreamConvertible {
    func didReceive(_ buffer: CMSampleBuffer)
    func didReceive(_ buffer: AVAudioBuffer, when: AVAudioTime)
    var incoming: IncomingStream { get }
    var outgoing: OutgoingStream { get }
    var outputs: [any StreamOutput] { get set }
    var bitRateStrategy: (any StreamBitRateStrategy)? { get set }
}

extension _Stream {
    package func didReceive(_ buffer: CMSampleBuffer) {
        append(buffer)
    }

    package func didReceive(_ buffer: AVAudioBuffer, when: AVAudioTime) {
        append(buffer, when: when)
    }

    public var soundTransform: SoundTransform? {
        get async {
            await incoming.soundTransfrom
        }
    }

    public var audioSettings: AudioCodecSettings {
        outgoing.audioSettings
    }

    public var videoSettings: VideoCodecSettings {
        outgoing.videoSettings
    }

    public func setBitRateStrategy(_ bitRateStrategy: (some StreamBitRateStrategy)?) {
        self.bitRateStrategy = bitRateStrategy
    }

    public func setVideoInputBufferCounts(_ videoInputBufferCounts: Int) {
        outgoing.videoInputBufferCounts = videoInputBufferCounts
    }

    public func setSoundTransform(_ soundTransform: SoundTransform) async {
        await incoming.setSoundTransform(soundTransform)
    }

    public func attachAudioPlayer(_ audioPlayer: AudioPlayer?) async {
        await incoming.attachAudioPlayer(audioPlayer)
    }

    public func addOutput(_ observer: some StreamOutput) {
        guard !outputs.contains(where: { $0 === observer }) else {
            return
        }
        outputs.append(observer)
    }

    public func removeOutput(_ observer: some StreamOutput) {
        if let index = outputs.firstIndex(where: { $0 === observer }) {
            outputs.remove(at: index)
        }
    }
}
