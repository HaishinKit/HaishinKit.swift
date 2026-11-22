import AVFoundation
import Foundation
import Testing

@testable import RTCHaishinKit

@Suite struct RTPH264PacketizerTests {
    final class Output: RTPPacketizerDelegate {
        var video: [CMSampleBuffer] = []
        func packetizer(_ packetizer: some RTPPacketizer, didOutput buffer: CMSampleBuffer) { video.append(buffer) }
        func packetizer(_ packetizer: some RTPPacketizer, didOutput buffer: AVAudioCompressedBuffer, when: AVAudioTime) {}
    }

    // A 64 × 64 red Baseline H.264 frame, with SPS/PPS aggregated as a server sends them.
    private let units = ["Z0LACtkEJsBEAAADAAQAAAMAejxImSA=", "aMuDyyA=", "ZYiEBLxGKAAKi8cAASjY4AAvrScnJ1111111111114A="]

    @Test func decodesAggregatedParameterSetsAndIDR() throws {
        let output = Output()
        let decoder = RTPH264Packetizer<Output>(ssrc: 1, payloadType: 98)
        decoder.delegate = output
        var payload = Data([24])
        for value in units {
            let nal = try #require(Data(base64Encoded: value))
            payload.append(UInt8(nal.count >> 8))
            payload.append(UInt8(nal.count & 255))
            payload.append(nal)
        }
        decoder.append(
            .init(
                version: 2, padding: false, extension: false, cc: 0, marker: true, payloadType: 98,
                sequenceNumber: 40000, timestamp: 90000, ssrc: 1, payload: payload))
        let sample = try #require(output.video.first)
        #expect(output.video.count == 1)
        #expect(sample.presentationTimeStamp == CMTime(value: 90000, timescale: 90000))
        #expect(CMVideoFormatDescriptionGetDimensions(try #require(sample.formatDescription)).width == 64)
    }

    @Test func fragmentedFramesPreserveEachTimestamp() throws {
        let output = Output()
        let decoder = RTPH264Packetizer<Output>(ssrc: 1, payloadType: 98)
        decoder.delegate = output
        var sequence: UInt16 = 30000
        for value in units.prefix(2) {
            decoder.append(
                .init(
                    version: 2, padding: false, extension: false, cc: 0, marker: false, payloadType: 98,
                    sequenceNumber: sequence, timestamp: 90000, ssrc: 1, payload: try #require(Data(base64Encoded: value))))
            sequence &+= 1
        }
        let idr = try #require(Data(base64Encoded: units[2]))
        for timestamp: UInt32 in [90000, 96000] {
            let chunks = [Data([0x7c, 0x85]) + idr[1..<12], Data([0x7c, 0x45]) + idr[12...]]
            for (index, chunk) in chunks.enumerated() {
                decoder.append(
                    .init(
                        version: 2, padding: false, extension: false, cc: 0, marker: index == chunks.count - 1, payloadType: 98,
                        sequenceNumber: sequence, timestamp: timestamp, ssrc: 1, payload: chunk))
                sequence &+= 1
            }
        }
        #expect(output.video.map(\.presentationTimeStamp) == [CMTime(value: 90000, timescale: 90000), CMTime(value: 96000, timescale: 90000)])
    }
}
