import AVFoundation
import Foundation

protocol IOTellyUnitDelegate: AnyObject {
    func tellyUnit(_ tellyUnit: IOTellyUnit, didSetAudioFormat audioFormat: AVAudioFormat?)
    func tellyUnit(_ tellyUnit: IOTellyUnit, dequeue sampleBuffer: CMSampleBuffer)
    func tellyUnit(_ tellyUnit: IOTellyUnit, didBufferingChanged: Bool)
}

final class IOTellyUnit {
    var isRunning: Atomic<Bool> = .init(false)

    var bufferTime: Double {
        get {
            mediaLink.bufferTime
        }
        set {
            mediaLink.bufferTime = newValue
        }
    }

    var audioFormat: AVAudioFormat? {
        didSet {
            delegate?.tellyUnit(self, didSetAudioFormat: audioFormat)
        }
    }

    var videoFormat: CMFormatDescription? {
        didSet {
            mediaLink.hasVideo = videoFormat != nil
        }
    }

    var soundTransform: SoundTransform = .init() {
        didSet {
            soundTransform.apply(mediaLink.playerNode)
        }
    }

    var playerNode: AVAudioPlayerNode {
        return mediaLink.playerNode
    }

    weak var delegate: (any IOTellyUnitDelegate)?

    private lazy var mediaLink = {
        var mediaLink = MediaLink<IOTellyUnit>()
        mediaLink.delegate = self
        return mediaLink
    }()
}

extension IOTellyUnit: Running {
    func startRunning() {
        guard !isRunning.value else {
            return
        }
        isRunning.mutate { $0 = true }
        mediaLink.startRunning()
    }

    func stopRunning() {
        guard isRunning.value else {
            return
        }
        mediaLink.stopRunning()
        audioFormat = nil
        videoFormat = nil
        isRunning.mutate { $0 = false }
    }
}

extension IOTellyUnit: IOMuxer {
    // MARK: IOMuxer
    func append(_ audioBuffer: AVAudioBuffer, when: AVAudioTime) {
        mediaLink.enqueue(audioBuffer, when: when)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        mediaLink.enqueue(sampleBuffer)
    }
}

extension IOTellyUnit: MediaLinkDelegate {
    // MARK: MediaLinkDelegate
    func mediaLink(_ mediaLink: MediaLink<IOTellyUnit>, dequeue sampleBuffer: CMSampleBuffer) {
        delegate?.tellyUnit(self, dequeue: sampleBuffer)
    }

    func mediaLink(_ mediaLink: MediaLink<IOTellyUnit>, didBufferingChanged: Bool) {
        delegate?.tellyUnit(self, didBufferingChanged: didBufferingChanged)
    }
}
