@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import HaishinKit
import UIKit

/// A deterministic 720p30 moving test image with 440/880 Hz stereo PCM.
@MainActor
final class TVTestSignal {
    private var task: Task<Void, Never>?
    private var pool: CVPixelBufferPool?
    private let width = 1280
    private let height = 720

    func start(mixer: MediaMixer) throws {
        stop()
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess,
            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)
        else {
            throw CocoaError(.coderInvalidValue)
        }
        let startTime = CMClockGetTime(CMClockGetHostTimeClock())
        let clock = ContinuousClock()
        let start = clock.now
        task = Task { [weak self] in
            var frame: Int64 = 0
            while !Task.isCancelled {
                guard let self else { return }
                let time = startTime + CMTime(value: frame, timescale: 30)
                if let video = self.makeVideo(frame: frame, time: time) { await mixer.append(video) }
                if let audio = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600), let channels = audio.floatChannelData {
                    audio.frameLength = 1600
                    for sample in 0..<1600 {
                        let seconds = Double(frame * 1600 + Int64(sample)) / 48_000
                        channels[0][sample] = Float(sin(2 * .pi * 440 * seconds) * 0.08)
                        channels[1][sample] = Float(sin(2 * .pi * 880 * seconds) * 0.08)
                    }
                    await mixer.append(
                        audio, when: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: time.seconds), sampleTime: frame * 1600, atRate: 48_000))
                }
                frame += 1
                do { try await clock.sleep(until: start.advanced(by: .nanoseconds(frame * 1_000_000_000 / 30))) } catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        pool = nil
    }

    private func makeVideo(frame: Int64, time: CMTime) -> CMSampleBuffer? {
        guard let pool else { return nil }
        var image: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &image) == kCVReturnSuccess, let image else { return nil }
        CVPixelBufferLockBaseAddress(image, [])
        defer { CVPixelBufferUnlockBaseAddress(image, []) }
        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(image), width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(image),
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let colors: [UIColor] = [.white, .yellow, .cyan, .green, .magenta, .red, .blue, .black]
        for (index, color) in colors.enumerated() {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: index * width / 8, y: 0, width: width / 8, height: height))
        }
        context.setFillColor(UIColor.black.withAlphaComponent(0.85).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: 140))
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: Int(frame * 9 % Int64(width - 24)), y: 150, width: 24, height: height - 160))
        UIGraphicsPushContext(context)
        ("HaishinKit  •  720p30  •  frame \(frame)\nStereo test tone: L 440 Hz / R 880 Hz" as NSString).draw(
            in: CGRect(x: 30, y: 20, width: width - 60, height: 110),
            withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 30, weight: .medium), .foregroundColor: UIColor.white])
        UIGraphicsPopContext()
        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, formatDescriptionOut: &description) == noErr,
            let description
        else { return nil }
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        guard
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: image, formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample) == noErr
        else { return nil }
        return sample
    }
}

/// Copies tap buffers before the input node can reuse their memory.
@MainActor
final class TVMicrophoneCapture {
    private let engine = AVAudioEngine()
    private var consumer: Task<Void, Never>?
    private var hasTap = false

    func start(mixer: MediaMixer) throws {
        stop()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.fileReadUnknown) }
        let buffers = AsyncStream<(AVAudioPCMBuffer, AVAudioTime)>.makeStream(bufferingPolicy: .bufferingNewest(4))
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
            copy.frameLength = buffer.frameLength
            let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
            let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for index in source.indices {
                if let from = source[index].mData, let to = target[index].mData {
                    memcpy(to, from, Int(min(source[index].mDataByteSize, target[index].mDataByteSize)))
                }
            }
            buffers.continuation.yield((copy, time))
        }
        hasTap = true
        consumer = Task {
            for await (buffer, time) in buffers.stream {
                guard !Task.isCancelled else { break }
                await mixer.append(buffer, when: time)
            }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            throw error
        }
    }
    func stop() {
        engine.stop()
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        consumer?.cancel()
        consumer = nil
    }
}
