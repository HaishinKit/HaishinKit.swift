import AVFoundation
import Foundation

final class AudioMixerBySingleTrack: AudioMixer {
    weak var delegate: (any AudioMixerDelegate)?
    var settings = AudioMixerSettings.default {
        didSet {
            if settings.invalidateOutputFormat(oldValue), let inSourceFormat {
                outputFormat = settings.makeOutputFormat(inSourceFormat)
            }
            if let trackSettings = settings.tracks[settings.mainTrack] {
                track?.settings = trackSettings
            }
        }
    }
    var inputFormats: [UInt8: AVAudioFormat] {
        var formats: [UInt8: AVAudioFormat] = .init()
        if let track = track, let inputFormat = track.inputFormat {
            formats[track.id] = inputFormat
        }
        return formats
    }
    private(set) var outputFormat: AVAudioFormat? {
        didSet {
            guard let outputFormat, outputFormat != oldValue else {
                return
            }
            let track = AudioMixerTrack<AudioMixerBySingleTrack>(id: settings.mainTrack, outputFormat: outputFormat)
            track.delegate = self
            self.track = track
        }
    }
    private var inSourceFormat: CMFormatDescription? {
        didSet {
            guard inSourceFormat != oldValue else {
                return
            }
            outputFormat = settings.makeOutputFormat(inSourceFormat)
        }
    }
    private var track: AudioMixerTrack<AudioMixerBySingleTrack>?

    func append(_ track: UInt8, buffer: CMSampleBuffer) {
        guard settings.mainTrack == track else {
            return
        }
        inSourceFormat = buffer.formatDescription
        self.track?.append(buffer)
    }

    func append(_ track: UInt8, buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        guard settings.mainTrack == track else {
            return
        }
        inSourceFormat = buffer.format.formatDescription
        self.track?.append(buffer, when: when)
    }
}

extension AudioMixerBySingleTrack: AudioMixerTrackDelegate {
    // MARK: AudioMixerTrackDelegate
    func track(_ track: AudioMixerTrack<AudioMixerBySingleTrack>, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        delegate?.audioMixer(self, track: track.id, didInput: buffer, when: when)
        delegate?.audioMixer(self, didOutput: buffer.muted(settings.isMuted), when: when)
    }

    func track(_ rtrack: AudioMixerTrack<AudioMixerBySingleTrack>, errorOccurred error: AudioMixerError) {
        delegate?.audioMixer(self, errorOccurred: error)
    }
}
