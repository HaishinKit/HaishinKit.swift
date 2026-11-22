@preconcurrency import AVFoundation
import Combine
import HaishinKit

@MainActor
final class TVMediaProbe: ObservableObject, StreamOutput, MediaMixerOutput {
    @Published private(set) var videoDescription = "Waiting for video"
    @Published private(set) var audioDescription = "Waiting for audio"
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var videoFrames: UInt64 = 0
    @Published private(set) var audioBuffers: UInt64 = 0
    func resetAudioLevel() { audioLevel = 0 }

    nonisolated let videoTrackId: UInt8? = UInt8.max
    nonisolated let audioTrackId: UInt8? = UInt8.max
    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {}
    nonisolated func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) { observe(buffer) }
    nonisolated func mixer(_ mixer: MediaMixer, didOutput buffer: CMSampleBuffer) { observe(buffer) }
    nonisolated func stream(_ stream: some StreamConvertible, didOutput audio: AVAudioBuffer, when: AVAudioTime) {
        if let pcm = audio as? AVAudioPCMBuffer { observe(pcm) }
    }
    nonisolated func stream(_ stream: some StreamConvertible, didOutput video: CMSampleBuffer) { observe(video) }
    nonisolated private func observe(_ buffer: CMSampleBuffer) {
        guard let format = buffer.formatDescription else { return }
        let size = CMVideoFormatDescriptionGetDimensions(format)
        Task { @MainActor in
            self.videoDescription = "\(size.width) × \(size.height)"
            self.videoFrames += 1
        }
    }
    nonisolated private func observe(_ buffer: AVAudioPCMBuffer) {
        let rate = Int(buffer.format.sampleRate)
        let channels = buffer.format.channelCount
        var peak: Float = 0
        if let data = buffer.floatChannelData {
            for frame in stride(from: 0, to: Int(buffer.frameLength), by: 16) { peak = max(peak, abs(data[0][frame])) }
        } else if let data = buffer.int16ChannelData {
            for frame in stride(from: 0, to: Int(buffer.frameLength), by: 16) { peak = max(peak, abs(Float(data[0][frame])) / 32768) }
        }
        let level = min(1, peak)
        Task { @MainActor in
            self.audioDescription = "\(rate / 1000) kHz · \(channels) ch PCM"
            self.audioLevel = level
            self.audioBuffers += 1
        }
    }
}
