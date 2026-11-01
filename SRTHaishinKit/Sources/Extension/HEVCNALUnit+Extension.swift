import CoreMedia
import HaishinKit

extension [HEVCNALUnit] {
    func makeFormatDescription(_ nalUnitHeaderLength: Int32 = 4) -> CMFormatDescription? {
        guard
            let vps = last(where: { $0.type == .vps }),
            let sps = last(where: { $0.type == .sps }),
            let pps = last(where: { $0.type == .pps }) else {
            return nil
        }
        return vps.data.withUnsafeBytes { (vpsBuffer: UnsafeRawBufferPointer) -> CMFormatDescription? in
            guard let vpsBaseAddress = vpsBuffer.baseAddress else {
                return nil
            }
            return sps.data.withUnsafeBytes { (spsBuffer: UnsafeRawBufferPointer) -> CMFormatDescription? in
                guard let spsBaseAddress = spsBuffer.baseAddress else {
                    return nil
                }
                return pps.data.withUnsafeBytes { (ppsBuffer: UnsafeRawBufferPointer) -> CMFormatDescription? in
                    guard let ppsBaseAddress = ppsBuffer.baseAddress else {
                        return nil
                    }
                    var formatDescriptionOut: CMFormatDescription?
                    let pointers: [UnsafePointer<UInt8>] = [
                        vpsBaseAddress.assumingMemoryBound(to: UInt8.self),
                        spsBaseAddress.assumingMemoryBound(to: UInt8.self),
                        ppsBaseAddress.assumingMemoryBound(to: UInt8.self)
                    ]
                    let sizes: [Int] = [vpsBuffer.count, spsBuffer.count, ppsBuffer.count]
                    CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: pointers.count,
                        parameterSetPointers: pointers,
                        parameterSetSizes: sizes,
                        nalUnitHeaderLength: nalUnitHeaderLength,
                        extensions: nil,
                        formatDescriptionOut: &formatDescriptionOut
                    )
                    return formatDescriptionOut
                }
            }
        }
    }
}
