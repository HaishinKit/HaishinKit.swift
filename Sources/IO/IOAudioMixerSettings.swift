import AVFoundation
import Foundation

/// Constraints on the audio mixier settings.
public struct IOAudioMixerSettings: Sendable {
    /// The default value.
    public static let `default` = IOAudioMixerSettings()
    /// Maximum sampleRate supported by the system
    public static let maximumSampleRate: Float64 = 48000.0

    #if os(macOS)
    static let commonFormat: AVAudioCommonFormat = .pcmFormatFloat32
    #else
    static let commonFormat: AVAudioCommonFormat = .pcmFormatInt16
    #endif

    /// Specifies the sampleRate of audio output. A value of 0 will be the same as the main track source.
    public let sampleRate: Float64

    /// Specifies the channels of audio output. A value of 0 will be the same as the main track source.
    /// - Warning: If you are using IOStreamRecorder, please set it to 1 or 2. Otherwise, the audio will not be saved in local recordings.
    public let channels: UInt32

    /// Specifies the muted that indicates whether the audio output is muted.
    public var isMuted: Bool

    /// Specifies the main track number.
    public var mainTrack: UInt8

    /// Specifies the track settings.
    public var tracks: [UInt8: IOAudioMixerTrackSettings]

    /// Specifies the maximum number of channels supported by the system
    /// - Description: The maximum number of channels to be used when the number of channels is 0 (not set). More than 2 channels are not supported by the service. It is defined to prevent audio issues since recording does not support more than 2 channels.
    public var maximumNumberOfChannels: UInt32 = 2

    /// Creates a new instance of a settings.
    public init(
        sampleRate: Float64 = 0,
        channels: UInt32 = 0,
        isMuted: Bool = false,
        mainTrack: UInt8 = 0,
        tracks: [UInt8: IOAudioMixerTrackSettings] = .init()
    ) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.isMuted = isMuted
        self.mainTrack = mainTrack
        self.tracks = tracks
    }

    func invalidateOutputFormat(_ oldValue: Self) -> Bool {
        return !(sampleRate == oldValue.sampleRate &&
                    channels == oldValue.channels)
    }

    func makeOutputFormat(_ formatDescription: CMFormatDescription?) -> AVAudioFormat? {
        guard let format = AVAudioUtil.makeAudioFormat(formatDescription) else {
            return nil
        }
        let sampleRate = min(sampleRate == 0 ? format.sampleRate : sampleRate, Self.maximumSampleRate)
        let channelCount = channels == 0 ? min(format.channelCount, maximumNumberOfChannels) : channels
        if let channelLayout = AVAudioUtil.makeChannelLayout(channelCount) {
            return .init(
                commonFormat: Self.commonFormat,
                sampleRate: sampleRate,
                interleaved: format.isInterleaved,
                channelLayout: channelLayout
            )
        }
        return .init(
            commonFormat: Self.commonFormat,
            sampleRate: sampleRate,
            channels: min(channelCount, 2),
            interleaved: format.isInterleaved
        )
    }
}
