import AVFoundation
import Foundation

extension AVAudioCompressedBuffer {
    @discardableResult
    @inline(__always)
    final func copy(_ buffer: AVAudioBuffer) -> Bool {
        guard let buffer = buffer as? AVAudioCompressedBuffer, buffer.byteLength <= byteCapacity else {
            return false
        }
        if let packetDescriptions = buffer.packetDescriptions {
            self.packetDescriptions?.pointee = packetDescriptions.pointee
        }
        packetCount = buffer.packetCount
        byteLength = buffer.byteLength
        data.copyMemory(from: buffer.data, byteCount: Int(buffer.byteLength))
        return true
    }

    package func encode(to data: inout Data) {
        guard let config = AudioSpecificConfig(formatDescription: format.formatDescription) else {
            return
        }
        config.encode(to: &data, length: Int(byteLength))
        data.withUnsafeMutableBytes {
            guard let baseAddress = $0.baseAddress else {
                return
            }
            memcpy(baseAddress.advanced(by: AudioSpecificConfig.adtsHeaderSize), self.data, Int(self.byteLength))
        }
    }
}
