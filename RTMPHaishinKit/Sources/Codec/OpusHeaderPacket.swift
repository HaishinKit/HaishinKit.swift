import AVFoundation
import Foundation

struct OpusHeaderPacket {
    static let signature = "OpusHead"

    let channels: Int
    let sampleRate: Double
    let preSkip: UInt16
    let outputGain: Int16

    var payload: Data {
        var data = Data()
        data.append(contentsOf: Self.signature.utf8)
        data.append(0x01)
        data.append(UInt8(channels))
        data.append(preSkip.littleEndian.data)
        data.append(UInt32(sampleRate).littleEndian.data)
        data.append(outputGain.littleEndian.data)
        data.append(0x00)
        return data
    }

    init?(formatDescription: CMFormatDescription?) {
        guard
            let streamDescription = formatDescription?.audioStreamBasicDescription else {
            return nil
        }
        channels = Int(streamDescription.mChannelsPerFrame)
        sampleRate = streamDescription.mSampleRate
        preSkip = 0
        outputGain = 0
    }

    /// Mapping family zero is a single mono or stereo Opus stream.
    init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 19, Array(bytes.prefix(8)) == Array(Self.signature.utf8),
              (1..<16).contains(bytes[8]), bytes[9] == 1 || bytes[9] == 2, bytes[18] == 0 else { return nil }
        channels = Int(bytes[9])
        // The ID header's input rate is informational. Decode on the 48 kHz timeline.
        sampleRate = 48_000
        preSkip = UInt16(bytes[10]) | UInt16(bytes[11]) << 8
        outputGain = Int16(bitPattern: UInt16(bytes[16]) | UInt16(bytes[17]) << 8)
    }

    func makeAudioFormat() -> AVAudioFormat? {
        var description = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatOpus,
            mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: 0, mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0)
        return AVAudioFormat(streamDescription: &description)
    }
}
