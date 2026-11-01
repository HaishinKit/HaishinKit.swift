import Foundation
import Testing

@testable import HaishinKit

@Suite struct NALUnitReaderByteStreamTests {
    @Test(arguments: [[3, 3, 3], [4, 4, 4], [3, 4, 3], [4, 3, 4]])
    func h264PreservesByteStreamOrder(startCodeLengths: [Int]) {
        let expected = [Data([0x67, 0x80]), Data([0x65, 0x11, 0x80]), Data([0x65, 0x22, 0x80])]
        var data = byteStream(expected, startCodeLengths: startCodeLengths)
        let original = data
        let units = NALUnitReader().read(&data, type: H264NALUnit.self)
        #expect(units.map(\.data) == expected)
        #expect(data == original)
    }

    @Test(arguments: [[3, 3, 3], [4, 4, 4], [3, 4, 3], [4, 3, 4]])
    func hevcPreservesByteStreamOrder(startCodeLengths: [Int]) {
        let expected = [Data([0x40, 0x01, 0x80]), Data([0x02, 0x01, 0x11]), Data([0x02, 0x01, 0x22])]
        var data = byteStream(expected, startCodeLengths: startCodeLengths)
        let units = NALUnitReader().read(&data, type: HEVCNALUnit.self)
        #expect(units.map(\.data) == expected)
    }

    @Test(arguments: [Data(), Data([0]), Data([0, 0]), Data([7, 8, 9]), Data([0, 0, 1]), Data([0, 0, 0, 1])])
    func noNALUnits(data: Data) {
        var data = data
        #expect(NALUnitReader().read(&data, type: H264NALUnit.self).isEmpty)
        #expect(NALUnitReader().read(&data, type: HEVCNALUnit.self).isEmpty)
    }

    @Test func skipsEmptyUnits() {
        var data = Data([0, 0, 1, 0, 0, 0, 1, 0x65, 0x80, 0, 0, 1])
        let units = NALUnitReader().read(&data, type: H264NALUnit.self)
        #expect(units.map(\.data) == [Data([0x65, 0x80])])
    }

    @Test func nonzeroDataStartIndex() {
        var data = Data([0xff, 0, 0, 1, 0x65, 0x11, 0, 0, 0, 1, 0x65, 0x22]).dropFirst()
        let units = NALUnitReader().read(&data, type: H264NALUnit.self)
        #expect(units.map(\.data) == [Data([0x65, 0x11]), Data([0x65, 0x22])])
    }

    private func byteStream(_ units: [Data], startCodeLengths: [Int]) -> Data {
        zip(units, startCodeLengths).reduce(into: Data()) { data, entry in
            data.append(contentsOf: Array(repeating: 0, count: entry.1 - 1) + [1])
            data.append(entry.0)
        }
    }
}
