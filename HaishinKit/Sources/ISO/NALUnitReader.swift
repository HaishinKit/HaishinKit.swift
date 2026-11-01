import CoreMedia
import Foundation

final package class NALUnitReader {
    static package let defaultNALUnitHeaderLength: Int32 = 4
    package var nalUnitHeaderLength: Int32 = NALUnitReader.defaultNALUnitHeaderLength

    package init() {
    }

    /// Reads Annex B NAL units in byte-stream order.
    package func read<T: NALUnit>(_ data: inout Data, type: T.Type) -> [T] {
        guard 3 <= data.count else {
            return []
        }
        return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var units: [T] = .init()
            var startIndex = bytes.count
            let offset = data.startIndex
            for i in 2..<bytes.count {
                guard bytes[i] == 1 && bytes[i - 1] == 0 && bytes[i - 2] == 0 else {
                    continue
                }
                let startCodeLength = 0 <= i - 3 && bytes[i - 3] == 0 ? 4 : 3
                let endIndex = i - startCodeLength + 1
                if startIndex < endIndex {
                    units.append(T.init(data.subdata(in: offset + startIndex..<offset + endIndex)))
                }
                startIndex = i + 1
            }
            if startIndex < bytes.count {
                units.append(T.init(data.subdata(in: offset + startIndex..<data.endIndex)))
            }
            return units
        }
    }

    package func read(_ buffer: CMSampleBuffer) -> [Data] {
        var offset = 0
        let header = Int(Self.defaultNALUnitHeaderLength)
        let length = buffer.dataBuffer?.dataLength ?? 0
        var result: [Data] = []

        if !buffer.isNotSync {
            if let formatDescription = buffer.formatDescription {
                result.append(Data([0x09, 0x10]))
                formatDescription.parameterSets.forEach {
                    result.append($0)
                }
            }
        } else {
            result.append(Data([0x09, 0x30]))
        }

        try? buffer.dataBuffer?.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }
            while offset + header < length {
                var nalUnitLength: UInt32 = 0
                memcpy(&nalUnitLength, baseAddress + offset, header)
                nalUnitLength = CFSwapInt32BigToHost(nalUnitLength)
                let start = offset + header
                let end = start + Int(nalUnitLength)
                if end <= length {
                    result.append(Data(bytes: baseAddress + start, count: Int(nalUnitLength)))
                } else {
                    break
                }
                offset = end
            }
        }
        return result
    }
}
