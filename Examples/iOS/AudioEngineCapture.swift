import AVFoundation
import Foundation
import HaishinKit

protocol AudioEngineCaptureDelegate: AnyObject {
    func audioCapture(_ audioCapture: AudioEngineCapture, buffer: AVAudioPCMBuffer, time: AVAudioTime)
}

final class AudioEngineCapture {
    var delegate: (any AudioEngineCaptureDelegate)?

    private(set) var isRunning = false
    private var audioEngine = AVAudioEngine()

    func startCaptureIfNeeded() {
        guard isRunning else {
            return
        }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine = AVAudioEngine()
        do {
            try startCapture()
        } catch {
            logger.warn(error)
        }
    }

    private func startCapture() throws {
        let input = audioEngine.inputNode
        let mixer = audioEngine.mainMixerNode
        audioEngine.connect(input, to: mixer, format: input.inputFormat(forBus: 0))
        input.installTap(onBus: 0, bufferSize: 1024, format: input.inputFormat(forBus: 0)) { buffer, when in
            self.delegate?.audioCapture(self, buffer: buffer, time: when)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }
}

extension AudioEngineCapture: Runner {
    // MARK: Runner
    func startRunning() {
        guard !isRunning else {
            return
        }
        do {
            try startCapture()
            isRunning = true
        } catch {
            logger.error(error)
        }
    }

    func stopRunning() {
        guard isRunning else {
            return
        }
        audioEngine.stop()
        isRunning = false
    }
}
