import CoreImage
import CoreMedia
import Foundation

protocol VideoMixerDelegate: AnyObject {
    func videoMixer(_ videoMixer: VideoMixer<Self>, track: UInt8, didInput sampleBuffer: CMSampleBuffer)
    func videoMixer(_ videoMixer: VideoMixer<Self>, didOutput sampleBuffer: CMSampleBuffer)
}

private let kVideoMixer_lockFlags = CVPixelBufferLockFlags(rawValue: .zero)

final class VideoMixer<T: VideoMixerDelegate> {
    weak var delegate: T?
    var settings: VideoMixerSettings = .default
    // Written from two queues: append(_:sampleBuffer:) on the capture-output queue for every
    // frame, and reset(_:) on VideoCaptureUnit's lockQueue during attach/detach. The delegate
    // callback stays outside the critical section so a re-entrant delegate cannot deadlock.
    private let inputFormatsLock = NSLock()
    private var storedInputFormats: [UInt8: CMFormatDescription] = [:]
    var inputFormats: [UInt8: CMFormatDescription] {
        inputFormatsLock.lock()
        defer { inputFormatsLock.unlock() }
        return storedInputFormats
    }
    private var currentPixelBuffer: CVPixelBuffer?

    func append(_ track: UInt8, sampleBuffer: CMSampleBuffer) {
        inputFormatsLock.lock()
        storedInputFormats[track] = sampleBuffer.formatDescription
        inputFormatsLock.unlock()
        delegate?.videoMixer(self, track: track, didInput: sampleBuffer)
        switch settings.mode {
        case .offscreen:
            break
        case .passthrough:
            if settings.mainTrack == track {
                outputSampleBuffer(sampleBuffer)
            }
        }
    }

    func reset(_ track: UInt8) {
        inputFormatsLock.lock()
        storedInputFormats[track] = nil
        inputFormatsLock.unlock()
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
            try sampleBuffer.imageBuffer?.mutate(kVideoMixer_lockFlags) { imageBuffer in
                try imageBuffer.copy(currentPixelBuffer)
            }
            delegate?.videoMixer(self, didOutput: sampleBuffer)
        } catch {
            logger.warn(error)
        }
    }
}
