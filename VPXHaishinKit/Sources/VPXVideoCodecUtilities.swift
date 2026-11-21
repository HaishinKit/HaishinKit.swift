import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import VPXBridge

func checkStatus(_ status: OSStatus) throws {
    guard status == noErr else { throw VPXVideoCodecError.coreMedia(status) }
}

func checkCodec(_ status: Int32) throws {
    guard status == 0 else { throw VPXVideoCodecError.codec(status) }
}

func makeBlockBuffer(_ data: Data) -> CMBlockBuffer? {
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
        blockLength: data.count, blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
        dataLength: data.count, flags: 0, blockBufferOut: &block) == noErr, let block else { return nil }
    let status = data.withUnsafeBytes { bytes -> OSStatus in
        guard let base = bytes.baseAddress else { return kCMBlockBufferBadLengthParameterErr }
        return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
    }
    return status == noErr ? block : nil
}
