import AVFoundation
import Foundation
import Testing

@testable import RTCHaishinKit

@Suite struct RTPJitterBufferTests {
    final class Result: RTPJitterBufferDelegate {
        var count = 0
        var sequences: [UInt16] = []

        func jitterBuffer(_ buffer: RTPJitterBuffer<RTPJitterBufferTests.Result>, sequenced: RTPPacket) {
            count += 1
            sequences.append(sequenced.sequenceNumber)
        }
    }

    @Test func randomStartReordersAndIgnoresDuplicates() {
        let result = Result()
        let buffer = RTPJitterBuffer<Result>()
        buffer.delegate = result
        for sequence: UInt16 in [45000, 45002, 45001, 45001, 45003] {
            buffer.append(.init(version: 2, padding: false, extension: false, cc: 0, marker: false, payloadType: 111,
                                sequenceNumber: sequence, timestamp: 0, ssrc: 1, payload: Data([1])))
        }
        #expect(result.sequences == [45000, 45001, 45002, 45003])
    }

    @Test func sequenceWrapAndLargeLoss() {
        let result = Result()
        let buffer = RTPJitterBuffer<Result>()
        buffer.delegate = result
        for sequence: UInt16 in [65534, 0, 65535, 1, 1000, 1001, 1002, 1003] {
            buffer.append(.init(version: 2, padding: false, extension: false, cc: 0, marker: false, payloadType: 111,
                                sequenceNumber: sequence, timestamp: 0, ssrc: 1, payload: Data([1])))
        }
        #expect(result.sequences == [65534, 65535, 0, 1, 1000, 1001, 1002, 1003])
    }

    @Test func lostPacket()
 throws {
        let result = Result()
        let buffer = RTPJitterBuffer<Result>()
        buffer.delegate = result
        var packets: [RTPPacket] = []
        for i in 0...100 {
            packets.append(.init(version: 2, padding: false, extension: false, cc: 0, marker: false, payloadType: 0, sequenceNumber: UInt16(i), timestamp: UInt32(960 * (i + 1)), ssrc: 0, payload: Data()))
        }
        packets.remove(at: 30)
        packets.remove(at: 50)
        for packet in packets {
            buffer.append(packet)
        }

        #expect(result.count == 99)
    }
}
