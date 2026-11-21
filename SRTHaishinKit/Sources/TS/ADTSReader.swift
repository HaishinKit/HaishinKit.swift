import Foundation
import HaishinKit

class ADTSReader: Sequence {
    private var data: Data = .init()

    func read(_ data: Data) {
        self.data = data
    }

    func makeIterator() -> ADTSReaderIterator {
        return ADTSReaderIterator(data: data)
    }
}

struct ADTSReaderIterator: IteratorProtocol {
    private let data: Data
    private var cursor: Int = 0
    private var header: ADTSHeader = .init()

    init(data: Data) {
        self.data = data
    }

    mutating func next() -> Int? {
        guard cursor + ADTSHeader.size <= data.count else {
            return nil
        }
        let bytes = data.advanced(by: cursor)
        header.data = bytes
        let length = Int(header.aacFrameLength)
        // Stops at a broken frame (lost or corrupted packets) instead of trusting its length.
        guard
            bytes[0] == ADTSHeader.sync, bytes[1] & 0xF0 == 0xF0,
            (header.protectionAbsent ? ADTSHeader.size : ADTSHeader.sizeWithCrc) < length,
            cursor + length <= data.count else {
            return nil
        }
        cursor += length
        return length
    }
}
