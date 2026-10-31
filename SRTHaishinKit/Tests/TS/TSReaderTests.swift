import CoreMedia
import Foundation
import HaishinKit
import Testing

@testable import SRTHaishinKit

@Suite struct TSReaderTests {
    @Test(arguments: [3, 4], [UInt8(0x65), UInt8(0x41)])
    func multipleH264SlicesPreserveOrder(startCodeLength: Int, nalHeader: UInt8) async throws {
        try await expectH264Slices(startCodeLength: startCodeLength, nalHeader: nalHeader, sliceCount: 3)
    }

    @Test(arguments: [3, 4], [UInt8(0x65), UInt8(0x41)])
    func singleH264SliceIsPreserved(startCodeLength: Int, nalHeader: UInt8) async throws {
        try await expectH264Slices(startCodeLength: startCodeLength, nalHeader: nalHeader, sliceCount: 1)
    }

    private func expectH264Slices(startCodeLength: Int, nalHeader: UInt8, sliceCount: Int) async throws {
        let programMapPID: UInt16 = 4096
        let videoPID: UInt16 = 256
        let pat = TSProgramAssociation()
        pat.programs = [1: programMapPID]
        let pmt = TSProgramMap()
        pmt.PCRPID = videoPID
        var video = ESSpecificData()
        video.streamType = .h264
        video.elementaryPID = videoPID
        pmt.elementaryStreamSpecificData = [video]

        let parameterSets = [
            Data([103, 77, 64, 13, 218, 5, 7, 236, 4, 64, 0, 0, 3, 0, 64, 0, 0, 7, 131, 197, 10, 168]),
            Data([104, 239, 60, 128])
        ]
        // Distinct synthetic slices test byte preservation, not video decoding.
        // Multiple slices span TS packets so PES reassembly is exercised too.
        let slices = (1...sliceCount).map { index in
            Data([nalHeader, UInt8(index)]) + Data(repeating: 0x80, count: 94)
        }
        let units = [Data([0x09, 0xf0])] + parameterSets + [Data([0x06, 0x05, 0x80])] + slices
        var annexB = Data()
        for unit in units {
            annexB.append(contentsOf: Array(repeating: 0, count: startCodeLength - 1) + [1])
            annexB.append(unit)
        }

        // Video PES with unspecified length and PTS = 0, flushed by the next PES.
        let header = Data([0, 0, 1, 0xe0, 0, 0, 0x80, 0x80, 5, 0x21, 0, 1, 0, 1])
        let pes = try #require(PacketizedElementaryStream(header + annexB))
        let videoPackets = pes.arrayOfPackets(videoPID, PCR: nil)
        let nextPES = try #require(videoPackets.first)
        let packets = pat.arrayOfPackets(0) + pmt.arrayOfPackets(programMapPID) + videoPackets + [nextPES]
        let transportStream = packets.reduce(into: Data()) { $0.append($1.data) }

        let reader = TSReader()
        var output = reader.output.makeAsyncIterator()
        #expect(reader.read(transportStream) == transportStream.count)
        // Finish the stream before awaiting, so a missing sample fails instead of hanging.
        reader.clear()
        let (pid, sampleBuffer) = try #require(await output.next())
        let blockBuffer = try #require(sampleBuffer.dataBuffer)
        var expected = Data()
        for slice in slices {
            expected.append(contentsOf: [0, 0, 0, UInt8(slice.count)])
            expected.append(slice)
        }
        #expect(pid == videoPID)
        #expect(sampleBuffer.formatDescription?.mediaSubType == .h264)
        #expect(sampleBuffer.numSamples == 1)
        #expect(sampleBuffer.isNotSync == (nalHeader == 0x41))
        #expect(try blockBuffer.dataBytes() == expected)
        #expect(await output.next() == nil)
    }
}
