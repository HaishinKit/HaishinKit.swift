import CoreImage
import CoreMedia
import Foundation

protocol IOVideoMixerDelegate: AnyObject {
    func videoMixer(_ videoMixer: IOVideoMixer<Self>, track: UInt8, didInput sampleBuffer: CMSampleBuffer)
    func videoMixer(_ videoMixer: IOVideoMixer<Self>, didOutput sampleBuffer: CMSampleBuffer)
}

private let kIOVideoMixer_lockFlags = CVPixelBufferLockFlags(rawValue: .zero)

final class IOVideoMixer<T: IOVideoMixerDelegate> {
    weak var delegate: T?

    lazy var screen: Screen = {
        var screen = Screen()
        screen.observer = self
        videoTrackScreenObject.track = settings.mainTrack
        try? screen.addChild(videoTrackScreenObject)
        return screen
    }()

    var settings: IOVideoMixerSettings = .default {
        didSet {
            if settings.mainTrack != oldValue.mainTrack {
                videoTrackScreenObject.track = settings.mainTrack
            }
        }
    }

    private(set) var inputFormats: [UInt8: CMFormatDescription] = [:]
    private var currentPixelBuffer: CVPixelBuffer?
    private var videoTrackScreenObject = VideoTrackScreenObject()

    func append(_ track: UInt8, sampleBuffer: CMSampleBuffer) {
        inputFormats[track] = sampleBuffer.formatDescription
        delegate?.videoMixer(self, track: track, didInput: sampleBuffer)
        switch settings.mode {
        case .offscreen:
            let screens: [VideoTrackScreenObject] = screen.getScreenObjects()
            for screen in screens where screen.track == track {
                screen.enqueue(sampleBuffer)
            }
            if track == settings.mainTrack && 0 < screen.targetTimestamp.value {
                let diff = ceil((screen.targetTimestamp.value - sampleBuffer.presentationTimeStamp.seconds) * 10000) / 10000
                screen.videoCaptureLatency.mutate { $0 = diff }
            }
        case .passthrough:
            if settings.mainTrack == track {
                outputSampleBuffer(sampleBuffer)
            }
        }
    }

    func registerEffect(_ effect: VideoEffect) -> Bool {
        return videoTrackScreenObject.registerVideoEffect(effect)
    }

    func unregisterEffect(_ effect: VideoEffect) -> Bool {
        return videoTrackScreenObject.unregisterVideoEffect(effect)
    }

    func reset(_ track: UInt8) {
        inputFormats[track] = nil
        let screens: [VideoTrackScreenObject] = screen.getScreenObjects()
        for screen in screens where screen.track == track {
            screen.reset()
        }
    }

    @inline(__always)
    private func outputSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        defer {
            currentPixelBuffer = sampleBuffer.imageBuffer
        }
        guard settings.isMuted else {
            delegate?.videoMixer(self, didOutput: sampleBuffer)
            return
        }
        do {
            try sampleBuffer.imageBuffer?.mutate(kIOVideoMixer_lockFlags) { imageBuffer in
                try imageBuffer.copy(currentPixelBuffer)
            }
            delegate?.videoMixer(self, didOutput: sampleBuffer)
        } catch {
            logger.warn(error)
        }
    }
}

extension IOVideoMixer: ScreenObserver {
    func screen(_ screen: Screen, didOutput sampleBuffer: CMSampleBuffer) {
        guard settings.mode == .offscreen else {
            return
        }
        outputSampleBuffer(sampleBuffer)
    }
}
