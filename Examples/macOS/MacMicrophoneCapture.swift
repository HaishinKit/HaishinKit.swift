@preconcurrency import AVFoundation
import HaishinKit

/// AVAudioEngine input avoids putting the microphone in the camera's AVCaptureSession.
final class MacMicrophoneCapture {
    private let engine = AVAudioEngine()
    private let mixer: MediaMixer
    private var hasTap = false
    private var consumer: Task<Void, Never>?

    init(mixer: MediaMixer) {
        self.mixer = mixer
    }

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.fileReadUnknown) }
        let buffers = AsyncStream<(AVAudioPCMBuffer, AVAudioTime)>.makeStream(bufferingPolicy: .bufferingNewest(4))
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            // The tap can reuse its buffer after returning; retain an independent copy.
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
            copy.frameLength = buffer.frameLength
            let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
            let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for index in source.indices {
                if let from = source[index].mData, let to = destination[index].mData {
                    memcpy(to, from, Int(source[index].mDataByteSize))
                }
            }
            buffers.continuation.yield((copy, time))
        }
        hasTap = true
        consumer = Task { [mixer] in
            for await (buffer, time) in buffers.stream {
                guard !Task.isCancelled else { break }
                await mixer.append(buffer, when: time, track: 0)
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
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        consumer?.cancel()
        consumer = nil
    }
}
