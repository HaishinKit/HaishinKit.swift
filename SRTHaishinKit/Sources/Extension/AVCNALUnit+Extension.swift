import CoreMedia
import HaishinKit

extension [H264NALUnit] {
    func makeFormatDescription(_ nalUnitHeaderLength: Int32 = 4) -> CMFormatDescription? {
        guard
            let pps = last(where: { $0.type == .pps }),
            let sps = last(where: { $0.type == .sps }) else {
            return nil
        }
        var formatDescription: CMFormatDescription?
        let status = pps.data.withUnsafeBytes { (ppsBuffer: UnsafeRawBufferPointer) -> OSStatus in
            guard let ppsBaseAddress = ppsBuffer.baseAddress else {
                return kCMFormatDescriptionBridgeError_InvalidParameter
            }
            return sps.data.withUnsafeBytes { (spsBuffer: UnsafeRawBufferPointer) -> OSStatus in
                guard let spsBaseAddress = spsBuffer.baseAddress else {
                    return kCMFormatDescriptionBridgeError_InvalidParameter
                }
                let pointers: [UnsafePointer<UInt8>] = [
                    spsBaseAddress.assumingMemoryBound(to: UInt8.self),
                    ppsBaseAddress.assumingMemoryBound(to: UInt8.self)
                ]
                let sizes: [Int] = [spsBuffer.count, ppsBuffer.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: pointers.count,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: nalUnitHeaderLength,
                    formatDescriptionOut: &formatDescription
                )
            }
        }
        if status != noErr {
            logger.error(status)
        }
        return formatDescription
    }
}
