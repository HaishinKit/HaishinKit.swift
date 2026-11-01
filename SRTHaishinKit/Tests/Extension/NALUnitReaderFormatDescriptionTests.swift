import CoreMedia
import Foundation
import HaishinKit
import Testing

@testable import SRTHaishinKit

@Suite struct NALUnitReaderFormatDescriptionTests {
    @Test func h264UsesLastParameterSets() throws {
        let parameterSets = [
            Data([103, 77, 64, 13, 218, 5, 7, 236, 4, 64, 0, 0, 3, 0, 64, 0, 0, 7, 131, 197, 10, 168]),
            Data([104, 239, 60, 128])
        ]
        // Earlier, incomplete parameter sets must not override the later ones.
        var data = byteStream([Data([0x67, 0]), Data([0x68, 0])] + parameterSets)
        let format = try #require(NALUnitReader().makeFormatDescription(&data, type: .h264))
        #expect(format.parameterSets.map { Data($0) } == parameterSets)
    }

    @Test func hevcUsesLastParameterSets() throws {
        let parameterSets = [
            Data([64, 1, 12, 1, 255, 255, 1, 96, 0, 0, 3, 0, 176, 0, 0, 3, 0, 0, 3, 0, 93, 21, 192, 144]),
            Data([66, 1, 1, 1, 96, 0, 0, 3, 0, 176, 0, 0, 3, 0, 0, 3, 0, 93, 160, 2, 40, 128, 39, 28, 178, 226, 5, 123, 145, 101, 83, 80, 16, 16, 16, 8]),
            Data([68, 1, 192, 44, 188, 20, 201])
        ]
        var data = byteStream([Data([0x40, 1]), Data([0x42, 1]), Data([0x44, 1])] + parameterSets)
        let format = try #require(NALUnitReader().makeFormatDescription(&data, type: .h265))
        #expect(format.parameterSets.map { Data($0) } == parameterSets)
    }

    private func byteStream(_ units: [Data]) -> Data {
        units.reduce(into: Data()) { data, unit in
            data.append(contentsOf: [0, 0, 0, 1])
            data.append(unit)
        }
    }
}
