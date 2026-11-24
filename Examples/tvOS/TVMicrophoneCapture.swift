@preconcurrency import AVFoundation
import HaishinKit

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
